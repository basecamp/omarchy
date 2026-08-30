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
           session->send(session::ChannelLane::render, header.message_type,
                         header.correlation_id, std::move(payload),
                         std::move(descriptors));
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

std::unique_ptr<PreparedPluginRuntime> PluginRuntimeRoot::prepare(
    Configuration &&configuration) {
  if (configuration.trusted_uid == std::numeric_limits<std::uint32_t>::max())
    return {};
  auto authority = host_session::AuthorityStore::open(
      configuration.authority_root.get(), configuration.trusted_uid,
      configuration.plugin);
  if (!authority)
    return {};
  try {
    auto root = std::unique_ptr<PluginRuntimeRoot>(
        new PluginRuntimeRoot(configuration, std::move(authority)));
    auto activation = root->coordinator_.prepare(root->activation_record_);
    if (!activation)
      return {};
    auto prepared =
        std::unique_ptr<PreparedPluginRuntime>(new PreparedPluginRuntime);
    prepared->root = std::move(root);
    prepared->session = std::move(activation.prepared);
    prepared->live_binding = std::move(activation.live_binding);
    return prepared;
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
    const auto activated = root->coordinator_.commit(
        std::move(prepared->session), std::move(*prepared->live_binding),
        &hooks, &hooks);
    return activated ? std::move(root) : nullptr;
  } catch (...) {
    return {};
  }
}

PluginRuntimeRoot::PluginRuntimeRoot(
    Configuration &configuration,
    std::unique_ptr<host_session::AuthorityStore> authority)
    : runtime_factory_(std::move(configuration.definitions),
                       std::move(configuration.services),
                       configuration.runtime_limits),
      authority_(std::move(authority)),
      activation_record_(std::move(configuration.activation_record)),
      coordinator_(configuration.activation_root_fd,
                   configuration.revision_root_fd, configuration.state_root_fd,
                   *authority_, configuration.plugin, configuration.trusted_uid,
                   runtime_factory_, nullptr,
                   configuration.session_limits, nullptr),
      controller_(coordinator_, runtime_factory_.definitions(),
                  runtime_factory_.scope_validator(), activation_record_) {
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  if (configuration.test_supervisor_factory)
    coordinator_.set_supervisor_factory(
        std::move(configuration.test_supervisor_factory));
  if (configuration.test_before_final_fence)
    coordinator_.set_before_final_fence(
        configuration.test_before_final_fence,
        configuration.test_before_final_fence_context);
#endif
}

PluginRuntimeRoot::~PluginRuntimeRoot() noexcept {
  // Destruction concurrent with a public call is outside the ownership
  // contract; avoid a throwing lock in this noexcept teardown path.
  coordinator_.stop();
}

std::optional<host_session::AuthorityView>
PluginRuntimeRoot::list() const {
  std::scoped_lock lock(mutex_);
  return controller_.list();
}

std::shared_ptr<const host_session::ConsentReview>
PluginRuntimeRoot::prepare_review() {
  std::scoped_lock lock(mutex_);
  return controller_.prepare_review();
}

ReviewedPermissionApplyResult PluginRuntimeRoot::apply_review(
    const host_session::ConsentConfirmation &confirmation,
    std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
    std::span<const host_session::DynamicConsentDecision> dynamic_decisions) {
  std::scoped_lock lock(mutex_);
  return controller_.apply_review(confirmation, builtin_decisions,
                                  dynamic_decisions);
}

PermissionRevokeApplyResult PluginRuntimeRoot::revoke(
    const permissions::CapabilityKey &capability,
    std::uint64_t expected_sequence) {
  std::scoped_lock lock(mutex_);
  return controller_.revoke(capability, expected_sequence);
}

PermissionRevokeApplyResult PluginRuntimeRoot::revoke(
    const definitions::CapabilityReference &definition,
    std::uint64_t expected_sequence) {
  std::scoped_lock lock(mutex_);
  return controller_.revoke(definition, expected_sequence);
}

std::optional<permissions::ActivationBinding>
PluginRuntimeRoot::session_binding() const {
  std::scoped_lock lock(mutex_);
  const auto *session = running_session_unlocked();
  return session ? std::optional(session->binding()) : std::nullopt;
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
  return coordinator_.session();
}

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
std::unique_ptr<PreparedPluginRuntime>
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
      .activation_root_fd = activation_root_fd,
      .revision_root_fd = revision_root_fd,
      .state_root_fd = state_root_fd,
      .authority_root = std::move(authority_root),
      .plugin = std::move(plugin),
      .trusted_uid = trusted_uid,
      .activation_record = std::move(activation_record),
      .definitions = std::move(definitions),
      .services = std::move(services),
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

std::shared_ptr<session::LiveGenerationState>
PluginRuntimeRootTestAccess::live_generation(
    const PluginRuntimeRoot &root) noexcept {
  const auto *session = root.running_session_unlocked();
  return session ? PluginSessionTestAccess::live_generation(*session) : nullptr;
}
#endif

} // namespace omarchy::plugin_runtime::channel
