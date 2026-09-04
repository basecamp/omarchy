#include "plugin_runtime_root.hpp"

#include <QThread>

#include <algorithm>
#include <utility>

namespace omarchy::plugin_runtime::channel {

class RootSurfaceSessionPort final : public SurfaceSessionPort {
public:
  explicit RootSurfaceSessionPort(PluginRuntimeRoot &root) noexcept
      : root_(root), owner_thread_(std::this_thread::get_id()) {}

  [[nodiscard]] std::optional<SurfaceDescription>
  describe(std::string_view declared_surface) const noexcept override;
  [[nodiscard]] bool
  attach(const SurfaceDescription &expected,
         session::SurfaceEndpoint &endpoint) noexcept override;
  [[nodiscard]] bool
  detach(const SurfaceDescription &expected,
         const session::SurfaceEndpoint &endpoint) noexcept override;
  [[nodiscard]] bool
  arm_surface_intent(const SurfaceDescription &expected,
                     std::uint64_t input_sequence) noexcept override;
  void clear_surface_intent_eligibility(
      const SurfaceDescription &expected) noexcept override;

private:
  [[nodiscard]] bool send_render_packet_impl(
      const SurfaceDescription &expected,
      const plugin::wire::EnvelopeHeader &header,
      std::vector<std::byte> payload,
      std::vector<session::OwnedFd> descriptors) noexcept override;
  [[nodiscard]] PluginSession *running_session() const noexcept;
  [[nodiscard]] bool
  matches(const PluginSession &session,
          const SurfaceDescription &expected) const noexcept;
  [[nodiscard]] bool on_owner_thread() const noexcept {
    return std::this_thread::get_id() == owner_thread_;
  }

  PluginRuntimeRoot &root_;
  const std::thread::id owner_thread_;
};

PluginSession *RootSurfaceSessionPort::running_session() const noexcept {
  return root_.running_session_unlocked();
}

bool RootSurfaceSessionPort::matches(
    const PluginSession &session,
    const SurfaceDescription &expected) const noexcept {
  if (session.binding() != expected.binding ||
      session.session_nonce_value() != expected.session_nonce ||
      expected.key.generation != expected.binding.generation ||
      expected.plugin_id != session.manifest().id ||
      expected.plugin_id != expected.binding.plugin.view())
    return false;
  const auto &names = session.manifest().surface_names;
  const auto found =
      std::find(names.begin(), names.end(), expected.surface_name);
  return found != names.end() &&
         expected.key.id ==
             static_cast<std::uint64_t>(found - names.begin()) + 1;
}

std::optional<SurfaceDescription> RootSurfaceSessionPort::describe(
    std::string_view declared_surface) const noexcept {
  if (!on_owner_thread())
    return {};
  try {
    std::scoped_lock lock(root_.mutex_);
    auto *session = running_session();
    if (session == nullptr)
      return {};
    const auto &names = session->manifest().surface_names;
    const auto found = std::find(names.begin(), names.end(), declared_surface);
    if (found == names.end())
      return {};
    const auto index = static_cast<std::uint64_t>(found - names.begin());
    return SurfaceDescription{
        .binding = session->binding(),
        .key = {.id = index + 1, .generation = session->binding().generation},
        .session_nonce = session->session_nonce_value(),
        .plugin_id = session->manifest().id,
        .surface_name = std::string(declared_surface),
        .canonical_surfaces = session->manifest().canonical_surfaces,
    };
  } catch (...) {
    return {};
  }
}

bool RootSurfaceSessionPort::attach(
    const SurfaceDescription &expected,
    session::SurfaceEndpoint &endpoint) noexcept {
  if (!on_owner_thread())
    return false;
  try {
    std::scoped_lock lock(root_.mutex_);
    auto *session = running_session();
    if (session == nullptr || !matches(*session, expected))
      return false;
    const auto correlations =
        session::surface::render_correlations(expected.key);
    const auto result =
        session->attach(expected.surface_name, correlations, endpoint);
    return result && result.key == expected.key;
  } catch (...) {
    // PluginSession::attach is transactional: exceptions never publish.
    return false;
  }
}

bool RootSurfaceSessionPort::detach(
    const SurfaceDescription &expected,
    const session::SurfaceEndpoint &endpoint) noexcept {
  if (!on_owner_thread())
    std::terminate();
  std::scoped_lock lock(root_.mutex_);
  auto *session = running_session();
  // A stopped or replacement session has already fenced this exact endpoint.
  return session == nullptr || !matches(*session, expected) ||
         session->detach(expected.surface_name, endpoint);
}

bool RootSurfaceSessionPort::send_render_packet_impl(
    const SurfaceDescription &expected,
    const plugin::wire::EnvelopeHeader &header, std::vector<std::byte> payload,
    std::vector<session::OwnedFd> descriptors) noexcept {
  if (!on_owner_thread())
    return false;
  try {
    std::scoped_lock lock(root_.mutex_);
    auto *session = running_session();
    return session != nullptr && matches(*session, expected) &&
           header.endpoint_role == plugin::wire::EndpointRole::render &&
           header.launch_generation == session->binding().generation &&
           header.role_protocol_version ==
               session::surface::kRenderRoleVersion &&
           header.flags == 0 && header.payload_length == payload.size() &&
           session->send_render(header.message_type, header.correlation_id,
                                std::move(payload), std::move(descriptors));
  } catch (...) {
    return false;
  }
}

bool RootSurfaceSessionPort::arm_surface_intent(
    const SurfaceDescription &expected,
    std::uint64_t input_sequence) noexcept {
  if (!on_owner_thread())
    return false;
  try {
    std::scoped_lock lock(root_.mutex_);
    auto *session = running_session();
    return session != nullptr && matches(*session, expected) &&
           session->arm_surface_intent(expected.key, input_sequence);
  } catch (...) {
    return false;
  }
}

void RootSurfaceSessionPort::clear_surface_intent_eligibility(
    const SurfaceDescription &expected) noexcept {
  if (!on_owner_thread())
    std::terminate();
  std::scoped_lock lock(root_.mutex_);
  auto *session = running_session();
  if (session != nullptr && matches(*session, expected))
    session->clear_surface_intent_eligibility(expected.key);
}

PluginRuntimePreparationResult PluginRuntimeRoot::prepare(
    Configuration &&configuration) {
  try {
    if (!configuration.permissions)
      return {};
    auto root = std::unique_ptr<PluginRuntimeRoot>(
        new PluginRuntimeRoot(configuration));
    auto loaded = root->permissions_->load_activation();
    if (!loaded.snapshot) {
      if (loaded.error != host_session::ActivationError::grant_unavailable)
        return {};
      // No active grant resolved for the selected revision. Keep the exact
      // authority reachable only when it can build a coherent immutable
      // review. Torn/corrupt or candidate-only authority remains unavailable.
      // No plugin-controlled runtime is assembled before review promotion.
      const auto review = root->permissions_->prepare_review();
      return {.runtime = {}, .permission_disabled = review != nullptr};
    }
    auto &snapshot = *loaded.snapshot;
    const auto binding = snapshot.grants.binding;
    const auto live = snapshot.live;
    if (snapshot.record.plugin_id !=
        root->permissions_->expected_plugin_.view())
      return {};
    if (loaded.grant_status ==
        host_session::GrantStatus::permission_disabled)
      return {.runtime = {}, .permission_disabled = true};
    if (loaded.grant_status != host_session::GrantStatus::activatable)
      return {};
    auto live_binding =
        root->permissions_->prepare_live_activation(binding, live);
    if (!live_binding)
      return {};

    // Bind before construction so an already-stale active revision cannot
    // enter even the side-effect-free runtime assembly phase.
    PluginSessionCreateError create_error = PluginSessionCreateError::none;
    auto session = PluginSession::prepare(
        root->supervisor(), std::move(snapshot), root->runtime_factory_,
        create_error, root->session_limits_, std::move(configuration.settings),
        std::move(configuration.presentation));
    if (!session)
      return {};
    auto prepared =
        std::unique_ptr<PreparedPluginRuntime>(new PreparedPluginRuntime);
    prepared->root = std::move(root);
    prepared->session = std::move(session);
    prepared->live_binding = std::move(live_binding);
    return {.runtime = std::move(prepared)};
  } catch (...) {
    return {};
  }
}

std::unique_ptr<PluginRuntimeRoot>
PluginRuntimeRoot::commit(
    std::unique_ptr<PreparedPluginRuntime> prepared,
    PluginRuntimeHooks &hooks, QObject &ui_owner) {
  if (!prepared || !prepared->root || !prepared->session ||
      !prepared->live_binding || QThread::currentThread() != ui_owner.thread())
    return {};
  try {
    auto root = std::move(prepared->root);
    root->surface_session_ = std::make_unique<RootSurfaceSessionPort>(*root);
    const auto expected_binding = prepared->session->grants.binding;
    const auto expected_live = prepared->session->live;
    PluginSessionCreateError create_error = PluginSessionCreateError::none;
    auto session = PluginSession::commit(std::move(prepared->session),
                                         create_error, &hooks, &hooks, nullptr);
    if (!session)
      return {};
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
    if (root->before_final_fence_)
      root->before_final_fence_(root->permissions_->authority_for_test(),
                                root->before_final_fence_context_);
#endif
    if (!root->permissions_->commit_live_activation(
            std::move(*prepared->live_binding), expected_binding,
            expected_live))
      return {};
    session->start();
    root->session_ = std::move(session);
    return root;
  } catch (...) {
    return {};
  }
}

PluginRuntimeRoot::PluginRuntimeRoot(Configuration &configuration)
    : runtime_factory_(configuration.permissions->definitions_,
                       configuration.permissions->services_,
                       configuration.runtime_limits),
      permissions_(std::move(configuration.permissions)),
      session_limits_(configuration.session_limits) {
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  supervisor_factory_ = std::move(configuration.test_supervisor_factory);
  before_final_fence_ = configuration.test_before_final_fence;
  before_final_fence_context_ = configuration.test_before_final_fence_context;
#endif
}

PluginRuntimeRoot::~PluginRuntimeRoot() noexcept {
  // Destruction concurrent with a public call is outside the ownership
  // contract; avoid a throwing lock in this noexcept teardown path.
  stop();
}

launcher::Supervisor PluginRuntimeRoot::supervisor() const {
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  if (supervisor_factory_)
    return supervisor_factory_();
#endif
  return launcher::Supervisor::packaged();
}

void PluginRuntimeRoot::stop() noexcept {
  if (!session_)
    return;
  session_->revoke();
  session_->stop();
  session_.reset();
}

std::optional<permissions::ActivationBinding>
PluginRuntimeRoot::session_binding() const {
  std::scoped_lock lock(mutex_);
  const auto *session = running_session_unlocked();
  return session ? std::optional(session->binding()) : std::nullopt;
}

std::optional<PluginRuntimeRoot::DeclaredSurfaceSet>
PluginRuntimeRoot::declared_surfaces() const noexcept {
  try {
    std::scoped_lock lock(mutex_);
    const auto *session = running_session_unlocked();
    if (session == nullptr)
      return std::nullopt;
    return DeclaredSurfaceSet{
        .binding = session->binding(),
        .plugin_id = session->manifest().id,
        .names = session->manifest().surface_names,
        .canonical_surfaces = session->manifest().canonical_surfaces,
    };
  } catch (...) {
    return std::nullopt;
  }
}

SurfaceSessionPort &
PluginRuntimeRoot::surface_session() noexcept {
  return *surface_session_;
}

PluginSession *PluginRuntimeRoot::running_session_unlocked() const noexcept {
  auto *session = session_unlocked();
  return session != nullptr &&
                 session->state() == host_session::SessionState::running
             ? session
             : nullptr;
}

PluginSession *PluginRuntimeRoot::session_unlocked() const noexcept {
  return session_.get();
}

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
PluginRuntimePreparationResult
PluginRuntimeRootTestAccess::prepare_from_parts(
    int activation_root_fd, int revision_root_fd, int state_root_fd,
    host_session::OwnedDescriptor authority_root,
    permissions::PluginId plugin, std::uint32_t trusted_uid,
    std::string activation_record,
    std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
    std::shared_ptr<const RuntimeServices> services, Limits runtime_limits,
    session::SessionLimits session_limits,
    std::function<launcher::Supervisor()> supervisor_factory,
    void (*before_final_fence)(host_session::AuthorityStore &, void *) noexcept,
    void *before_final_fence_context) {
  return PluginRuntimeRoot::prepare({
      .permissions = PluginPermissionAuthority::open(
          activation_root_fd, revision_root_fd, state_root_fd,
          std::move(authority_root), std::move(plugin), trusted_uid,
          std::move(definitions), std::move(services), activation_record),
      .settings = std::nullopt,
      .presentation = std::nullopt,
      .runtime_limits = runtime_limits,
      .session_limits = session_limits,
      .test_supervisor_factory = std::move(supervisor_factory),
      .test_before_final_fence = before_final_fence,
      .test_before_final_fence_context = before_final_fence_context,
  });
}

std::unique_ptr<PluginRuntimeRoot>
PluginRuntimeRootTestAccess::commit(
    std::unique_ptr<PreparedPluginRuntime> prepared,
    PluginRuntimeHooks &hooks, QObject &ui_owner) {
  return PluginRuntimeRoot::commit(std::move(prepared), hooks,
                                             ui_owner);
}

bool PluginRuntimeRootTestAccess::ui_affine(
    const PluginRuntimeRoot &root,
    const QObject &ui_owner) noexcept {
  const auto *session = root.session_unlocked();
  return session != nullptr &&
         PluginSessionTestAccess::ui_affine(*session, ui_owner.thread());
}

#endif

} // namespace omarchy::plugin_runtime::channel
