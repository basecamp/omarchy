#include "production_session_runtime_factory.hpp"

#include "audit_store.hpp"
#include "omarchy/plugin_runtime/providers/private_storage_backend.hpp"
#include "structured_broker.hpp"

#include <fcntl.h>

#include <algorithm>
#include <optional>
#include <stdexcept>
#include <utility>

namespace omarchy::plugin_runtime::channel {
namespace audit = omarchy::plugins::audit;
namespace permissions = omarchy::plugins::permissions;
namespace policy = omarchy::plugin_runtime::policy;
namespace {

const permissions::CapabilityKey kStorage{
    .id = permissions::CapabilityId("storage.private"), .version = 1};
const permissions::CapabilityKey kNotifications{
    .id = permissions::CapabilityId("notifications.send"), .version = 1};
const permissions::CapabilityKey kAudio{
    .id = permissions::CapabilityId("audio.play-cue"), .version = 1};

struct PreparedRuntime final {
  std::optional<permissions::QuotaScope> storage;
  std::vector<runtime::DynamicRoute> dynamic_routes;
};

class LiveDispatchAuthority final : public host_session::DispatchAuthority {
  class Lease final : public host_session::DispatchAuthorityLease {
  public:
    explicit Lease(session::LiveGenerationState::EffectToken token)
        : token_(std::move(token)) {}

    [[nodiscard]] bool current_at_effect() const noexcept override {
      return token_.current();
    }

  private:
    session::LiveGenerationState::EffectToken token_;
  };

public:
  LiveDispatchAuthority(permissions::ActivationBinding binding,
                        std::uint64_t session_nonce,
                        std::shared_ptr<session::LiveGenerationState> live)
      : binding_(std::move(binding)), session_nonce_(session_nonce),
        live_(std::move(live)) {}

  [[nodiscard]] std::unique_ptr<host_session::DispatchAuthorityLease>
  acquire(const permissions::ActivationBinding &binding,
          std::uint64_t session_nonce,
          const plugin::wire::PacketView &request) override {
    if (binding != binding_ || session_nonce != session_nonce_ ||
        request.header.launch_generation != binding_.generation || !live_)
      return {};
    auto token = live_->acquire_effect(binding_);
    if (!token)
      return {};
    return std::make_unique<Lease>(std::move(*token));
  }

  [[nodiscard]] bool
  fence_builtin(const policy::Revocation &) noexcept override {
    return false;
  }
  [[nodiscard]] bool
  fence_dynamic(const definitions::DynamicRevisionGrant &) noexcept override {
    return false;
  }

private:
  permissions::ActivationBinding binding_;
  std::uint64_t session_nonce_ = 0;
  std::shared_ptr<session::LiveGenerationState> live_;
};

providers::ProviderConfiguration provider_configuration(
    providers::PrivateStorageBackend &storage,
    const ProductionRuntimeServices &services,
    const PreparedRuntime &prepared) {
  providers::ProviderConfiguration configuration;
  if (prepared.storage)
    configuration.storage = storage.configuration();
  configuration.notification = {
      .send = services.notification_send, .context = services.context.get()};
  configuration.audio = {
      .play = services.audio_play, .context = services.context.get()};
  return configuration;
}

class ProductionRuntime final : public AuthenticatedSessionRuntime {
public:
  ProductionRuntime(
      std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
      const ProductionRuntimeServices &services,
      const policy::GrantSnapshot &grants,
      PreparedRuntime prepared, int state_directory_fd,
      std::uint64_t session_nonce,
      std::shared_ptr<session::LiveGenerationState> live,
      const ProductionRuntimeLimits &limits)
      : definitions_(std::move(definitions)), context_(services.context),
        storage_(state_directory_fd,
                 prepared.storage ? prepared.storage->total_bytes : 0,
                 prepared.storage ? prepared.storage->item_bytes : 0),
        audit_(limits.maximum_audit_records),
        authority_(grants.binding, session_nonce, std::move(live)),
        builtin_(grants,
                 provider_configuration(storage_, services, prepared),
                 audit_),
        dynamic_(*definitions_, std::move(prepared.dynamic_routes), audit_),
        broker_(grants.binding, session_nonce, builtin_, dynamic_, authority_) {
    if (prepared.storage && !storage_.valid())
      throw std::runtime_error("private storage descriptor unavailable");
  }

  [[nodiscard]] host_session::StructuredBroker &broker() noexcept override {
    return broker_;
  }

private:
  std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions_;
  std::shared_ptr<void> context_;
  providers::PrivateStorageBackend storage_;
  audit::BoundedAuditLog audit_;
  LiveDispatchAuthority authority_;
  runtime::AuditedBrokerRuntime builtin_;
  runtime::DynamicBrokerRuntime dynamic_;
  host_session::StructuredBroker broker_;
};

std::optional<PreparedRuntime> prepare_runtime(
    const policy::GrantSnapshot &grants,
    const definitions::TrustedDefinitionRegistry &registry,
    const ProductionRuntimeServices &services,
    const ProductionRuntimeLimits &limits) {
  PreparedRuntime prepared;
  for (const auto &grant : grants.grants.values()) {
    if (grant.state != permissions::GrantState::granted)
      continue;
    if (grant.capability == kStorage) {
      const auto *quota = std::get_if<permissions::QuotaScope>(&grant.scope);
      if (!quota || quota->total_bytes > limits.maximum_storage_bytes ||
          quota->item_bytes > limits.maximum_storage_item_bytes)
        return std::nullopt;
      prepared.storage = *quota;
    } else if (grant.capability == kNotifications) {
      if (!services.notification_send)
        return std::nullopt;
    } else if (grant.capability == kAudio) {
      if (!services.audio_play)
        return std::nullopt;
    } else {
      return std::nullopt;
    }
  }

  const definitions::DynamicScopeValidator validator{
      .compare = services.compare_scope, .context = services.context.get()};
  for (const auto &grant : grants.dynamic_grants) {
    if (grant.grant.state != permissions::GrantState::granted)
      continue;
    if (grant.binding != grants.binding ||
        !definitions::review_dynamic_grant(registry, grant, validator))
      return std::nullopt;
    const auto resolved = registry.resolve(grant.request.definition);
    if (!resolved)
      return std::nullopt;
    const auto matches = std::ranges::count(
        services.dynamic_services, resolved->definition->adapter,
        &TrustedDynamicService::binding);
    const auto configured = std::ranges::find(
        services.dynamic_services, resolved->definition->adapter,
        &TrustedDynamicService::binding);
    if (matches != 1 || configured == services.dynamic_services.end() ||
        !configured->dispatch)
      return std::nullopt;
    prepared.dynamic_routes.push_back({
        .grant = grant,
        .adapter = {.binding = configured->binding,
                    .dispatch = configured->dispatch,
                    .context = services.context.get()},
        .scope_validator = validator});
  }
  return prepared;
}

} // namespace

ProductionSessionRuntimeFactory::ProductionSessionRuntimeFactory(
    definitions::TrustedDefinitionRegistry definitions,
    ProductionRuntimeServices services, ProductionRuntimeLimits limits)
    : definitions_(
          std::make_shared<const definitions::TrustedDefinitionRegistry>(
              std::move(definitions))),
      services_(std::move(services)),
      limits_(limits) {
  if (limits_.maximum_audit_records == 0 ||
      limits_.maximum_audit_records > audit::kHardMaximumRecords ||
      limits_.maximum_storage_item_bytes == 0 ||
      limits_.maximum_storage_item_bytes > limits_.maximum_storage_bytes)
    throw std::invalid_argument("invalid production runtime configuration");
}

const definitions::TrustedDefinitionRegistry &
ProductionSessionRuntimeFactory::definitions() const noexcept {
  return *definitions_;
}

definitions::DynamicScopeValidator
ProductionSessionRuntimeFactory::scope_validator() const noexcept {
  return {.compare = services_.compare_scope,
          .context = services_.context.get()};
}

std::unique_ptr<AuthenticatedSessionRuntime>
ProductionSessionRuntimeFactory::create(
    const plugins::manifest::ManifestV2 &manifest,
    const session::policy::GrantSnapshot &grants, int revision_directory_fd,
    int private_state_directory_fd, std::uint64_t session_nonce,
    std::shared_ptr<session::LiveGenerationState> live_generation,
    std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility) {
  if (session_nonce == 0 || !live_generation || !gesture_eligibility ||
      manifest.id != grants.binding.plugin.view() ||
      !live_generation->current(grants.binding) ||
      ::fcntl(revision_directory_fd, F_GETFD) < 0 ||
      ::fcntl(private_state_directory_fd, F_GETFD) < 0)
    return {};
  auto prepared = prepare_runtime(grants, *definitions_, services_, limits_);
  if (!prepared)
    return {};
  try {
    auto runtime = std::make_unique<ProductionRuntime>(
        definitions_, services_, grants, std::move(*prepared),
        private_state_directory_fd, session_nonce, std::move(live_generation),
        limits_);
    return runtime;
  } catch (...) {
    return {};
  }
}

} // namespace omarchy::plugin_runtime::channel
