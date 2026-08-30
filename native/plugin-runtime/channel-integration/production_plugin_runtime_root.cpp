#include "production_plugin_runtime_root.hpp"

#include <utility>

namespace omarchy::plugin_runtime::channel {

std::unique_ptr<ProductionPluginRuntimeRoot>
ProductionPluginRuntimeRoot::open(
    ProductionPluginRuntimeConfiguration &&configuration) {
  if (configuration.trusted_uid ==
      std::numeric_limits<std::uint32_t>::max())
    return {};
  auto authority = host_session::AuthorityStore::open(
      configuration.authority_root_fd, configuration.trusted_uid,
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
                  runtime_factory_.scope_validator(), activation_record_) {}

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
