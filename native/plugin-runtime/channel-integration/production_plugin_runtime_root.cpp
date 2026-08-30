#include "production_plugin_runtime_root.hpp"

#include <algorithm>
#include <utility>

namespace omarchy::plugin_runtime::channel {

class RootSurfaceSessionPort final : public ProductionSurfaceSessionPort {
public:
  explicit RootSurfaceSessionPort(ProductionPluginRuntimeRoot &root) noexcept
      : root_(root), owner_thread_(std::this_thread::get_id()) {}

  [[nodiscard]] std::optional<ProductionSurfaceDescription>
  describe(std::string_view declared_surface) const noexcept override;
  [[nodiscard]] bool
  attach(const ProductionSurfaceDescription &expected,
         session::SurfaceEndpoint &endpoint) noexcept override;
  [[nodiscard]] bool
  detach(const ProductionSurfaceDescription &expected,
         const session::SurfaceEndpoint &endpoint) noexcept override;
  [[nodiscard]] bool
  arm_surface_intent(const ProductionSurfaceDescription &expected,
                     std::uint64_t input_sequence) noexcept override;
  void clear_surface_intent_eligibility(
      const ProductionSurfaceDescription &expected) noexcept override;

private:
  [[nodiscard]] bool send_render_packet_impl(
      const ProductionSurfaceDescription &expected,
      const plugin::wire::EnvelopeHeader &header,
      std::vector<std::byte> payload,
      std::vector<session::OwnedFd> descriptors) noexcept override;
  [[nodiscard]] PluginSession *running_session() const noexcept;
  [[nodiscard]] bool matches(const PluginSession &session,
                             const ProductionSurfaceDescription &expected)
      const noexcept;
  [[nodiscard]] bool on_owner_thread() const noexcept {
    return std::this_thread::get_id() == owner_thread_;
  }

  ProductionPluginRuntimeRoot &root_;
  const std::thread::id owner_thread_;
};

PluginSession *RootSurfaceSessionPort::running_session() const noexcept {
  auto *session = root_.coordinator_.session();
  return session != nullptr &&
                 session->state() == host_session::SessionState::running
             ? session
             : nullptr;
}

bool RootSurfaceSessionPort::matches(
    const PluginSession &session,
    const ProductionSurfaceDescription &expected) const noexcept {
  if (session.binding() != expected.binding ||
      session.session_nonce_value() != expected.session_nonce ||
      expected.key.generation != expected.binding.generation ||
      expected.plugin_id != session.manifest().id ||
      expected.plugin_id != expected.binding.plugin.view())
    return false;
  const auto &names = session.manifest().surface_names;
  const auto found = std::find(names.begin(), names.end(), expected.surface_name);
  return found != names.end() &&
         expected.key.id ==
             static_cast<std::uint64_t>(found - names.begin()) + 1;
}

std::optional<ProductionSurfaceDescription>
RootSurfaceSessionPort::describe(
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
    return ProductionSurfaceDescription{
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
    const ProductionSurfaceDescription &expected,
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
    const ProductionSurfaceDescription &expected,
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
    const ProductionSurfaceDescription &expected,
    const plugin::wire::EnvelopeHeader &header,
    std::vector<std::byte> payload,
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
    const ProductionSurfaceDescription &expected,
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
    const ProductionSurfaceDescription &expected) noexcept {
  if (!on_owner_thread())
    std::terminate();
  std::scoped_lock lock(root_.mutex_);
  auto *session = running_session();
  if (session != nullptr && matches(*session, expected))
    session->clear_surface_intent_eligibility();
}

std::unique_ptr<ProductionPluginRuntimeRoot>
ProductionPluginRuntimeRoot::open(
    ProductionPluginRuntimeConfiguration &&configuration) {
  if (configuration.trusted_uid ==
      std::numeric_limits<std::uint32_t>::max())
    return {};
  auto authority = host_session::AuthorityStore::open(
      configuration.authority_root.get(), configuration.trusted_uid,
      configuration.plugin);
  if (!authority)
    return {};
  try {
    return std::unique_ptr<ProductionPluginRuntimeRoot>(
        new ProductionPluginRuntimeRoot(configuration,
                                        std::move(authority)));
  } catch (...) {
    return {};
  }
}

ProductionPluginRuntimeRoot::ProductionPluginRuntimeRoot(
    ProductionPluginRuntimeConfiguration &configuration,
    std::unique_ptr<host_session::AuthorityStore> authority)
    : runtime_factory_(std::move(configuration.definitions),
                       std::move(configuration.services),
                       configuration.runtime_limits),
      authority_(std::move(authority)),
      activation_record_(std::move(configuration.activation_record)),
      coordinator_(
          configuration.activation_root_fd, configuration.revision_root_fd,
          configuration.state_root_fd, *authority_, configuration.plugin,
          configuration.trusted_uid, runtime_factory_,
          configuration.hooks, configuration.session_limits,
          configuration.hooks),
      controller_(coordinator_, runtime_factory_.definitions(),
                  runtime_factory_.scope_validator(), activation_record_),
      surface_session_(std::make_unique<RootSurfaceSessionPort>(*this)) {}

ProductionPluginRuntimeRoot::~ProductionPluginRuntimeRoot() noexcept {
  // Destruction concurrent with a public call is outside the ownership
  // contract; avoid a throwing lock in this noexcept teardown path.
  coordinator_.stop();
}

std::optional<host_session::AuthorityView>
ProductionPluginRuntimeRoot::list() const {
  std::scoped_lock lock(mutex_);
  return controller_.list();
}

std::shared_ptr<const host_session::ConsentReview>
ProductionPluginRuntimeRoot::prepare_review() {
  std::scoped_lock lock(mutex_);
  return controller_.prepare_review();
}

ReviewedPermissionApplyResult ProductionPluginRuntimeRoot::apply_review(
    const host_session::ConsentConfirmation &confirmation,
    std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
    std::span<const host_session::DynamicConsentDecision> dynamic_decisions) {
  std::scoped_lock lock(mutex_);
  return controller_.apply_review(confirmation, builtin_decisions,
                                  dynamic_decisions);
}

PermissionRevokeApplyResult ProductionPluginRuntimeRoot::revoke(
    const permissions::CapabilityKey &capability,
    std::uint64_t expected_sequence) {
  std::scoped_lock lock(mutex_);
  return controller_.revoke(capability, expected_sequence);
}

PermissionRevokeApplyResult ProductionPluginRuntimeRoot::revoke(
    const definitions::CapabilityReference &definition,
    std::uint64_t expected_sequence) {
  std::scoped_lock lock(mutex_);
  return controller_.revoke(definition, expected_sequence);
}

PluginActivationResult ProductionPluginRuntimeRoot::activate() {
  std::scoped_lock lock(mutex_);
  return coordinator_.activate(activation_record_);
}

void ProductionPluginRuntimeRoot::stop() {
  std::scoped_lock lock(mutex_);
  coordinator_.stop();
}

std::optional<permissions::ActivationBinding>
ProductionPluginRuntimeRoot::session_binding() const {
  std::scoped_lock lock(mutex_);
  const auto *session = coordinator_.session();
  if (!session || session->state() != host_session::SessionState::running)
    return {};
  return session->binding();
}

ProductionSurfaceSessionPort &
ProductionPluginRuntimeRoot::surface_session() noexcept {
  return *surface_session_;
}

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
void ProductionPluginRuntimeRootTestAccess::set_supervisor_factory(
    ProductionPluginRuntimeRoot &root,
    std::function<launcher::Supervisor()> factory) {
  PluginActivationCoordinatorTestAccess::set_supervisor_factory(
      root.coordinator_, std::move(factory));
}

std::shared_ptr<session::LiveGenerationState>
ProductionPluginRuntimeRootTestAccess::live_generation(
    const ProductionPluginRuntimeRoot &root) noexcept {
  const auto *session = root.coordinator_.session();
  return session ? PluginSessionTestAccess::live_generation(*session) : nullptr;
}
#endif

} // namespace omarchy::plugin_runtime::channel
