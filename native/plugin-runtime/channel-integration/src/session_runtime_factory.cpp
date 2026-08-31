#include "session_runtime_factory.hpp"

#include "audit_store.hpp"
#include "omarchy/plugin_runtime/providers/private_storage_backend.hpp"
#include "permission_projection.hpp"
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

bool runtime_service_available(
    const RuntimeServices &services,
    const permissions::CapabilityKey &capability) noexcept {
  if (capability.version != 1)
    return false;
  if (capability.id.view() == "storage.private")
    return true;
  if (capability.id.view() == "notifications.send")
    return services.notification_send != nullptr;
  if (capability.id.view() == "audio.play-cue")
    return services.audio_play != nullptr;
  return false;
}

bool runtime_service_available(
    const definitions::TrustedDefinitionRegistry &definitions,
    const RuntimeServices &services,
    const definitions::CapabilityReference &definition) noexcept {
  try {
    const auto resolved = definitions.resolve(definition);
    if (!resolved)
      return false;
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
    if (!services.provider_catalog)
      return std::ranges::count(services.dynamic_services,
                                resolved->definition->adapter,
                                &TrustedDynamicService::binding) == 1 &&
             std::ranges::any_of(
                 services.dynamic_services, [&](const auto &service) {
                   return service.binding == resolved->definition->adapter &&
                          service.dispatch != nullptr;
                 });
#endif
    return services.provider_catalog &&
           services.provider_catalog->available(resolved->definition->adapter);
  } catch (...) {
    return false;
  }
}

namespace {

definitions::DynamicScopeRelation
exact_scope(const definitions::CapabilityDefinition &,
            std::string_view candidate, std::string_view baseline,
            void *) noexcept {
  return candidate == baseline
             ? definitions::DynamicScopeRelation::equal
             : definitions::DynamicScopeRelation::incomparable;
}

} // namespace

definitions::DynamicScopeValidator
runtime_scope_validator(const RuntimeServices &services) noexcept {
  return {.compare =
              services.compare_scope ? services.compare_scope : exact_scope,
          .context = services.context.get()};
}

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
  std::shared_ptr<provider_host::ProviderActivation> provider_activation;
  std::vector<std::shared_ptr<provider_host::ProviderRoute>> provider_routes;
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
    const RuntimeServices &services,
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

class ComposedSessionRuntime final : public AuthenticatedSessionRuntime {
public:
  ComposedSessionRuntime(
      std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
      const RuntimeServices &services,
      const policy::GrantSnapshot &grants,
      PreparedRuntime prepared, int state_directory_fd,
      std::uint64_t session_nonce,
      std::shared_ptr<session::LiveGenerationState> live,
      const Limits &limits)
      : definitions_(std::move(definitions)), context_(services.context),
        provider_activation_(std::move(prepared.provider_activation)),
        provider_routes_(std::move(prepared.provider_routes)),
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
  std::shared_ptr<provider_host::ProviderActivation> provider_activation_;
  std::vector<std::shared_ptr<provider_host::ProviderRoute>> provider_routes_;
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
    const RuntimeServices &services,
    const Limits &limits) {
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
      const auto request =
          std::ranges::find(grants.requests.values(), grant.capability,
                            &permissions::CapabilityRequest::capability);
      if (request == grants.requests.values().end())
        return std::nullopt;
      if (!runtime_service_available(services, grant.capability) &&
          request->required)
        return std::nullopt;
    } else if (grant.capability == kAudio) {
      const auto request =
          std::ranges::find(grants.requests.values(), grant.capability,
                            &permissions::CapabilityRequest::capability);
      if (request == grants.requests.values().end())
        return std::nullopt;
      if (!runtime_service_available(services, grant.capability) &&
          request->required)
        return std::nullopt;
    } else {
      return std::nullopt;
    }
  }

  const auto validator = runtime_scope_validator(services);
  for (const auto &grant : grants.dynamic_grants) {
    if (grant.grant.state != permissions::GrantState::granted)
      continue;
    if (grant.binding != grants.binding ||
        !definitions::review_dynamic_grant(registry, grant, validator))
      return std::nullopt;
    if (!runtime_service_available(registry, services,
                                   grant.request.definition)) {
      if (grant.request.required)
        return std::nullopt;
      continue;
    }
    const auto resolved = registry.resolve(grant.request.definition);
    if (!resolved)
      return std::nullopt;
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
    if (!services.provider_catalog) {
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
      continue;
    }
#endif
    if (!prepared.provider_activation)
      prepared.provider_activation = provider_host::ProviderActivation::create(
          services.provider_catalog, grants.binding);
    if (!prepared.provider_activation)
      return std::nullopt;
    auto provider_route = prepared.provider_activation->route(
        resolved->definition->adapter);
    if (!provider_route)
      return std::nullopt;
    prepared.dynamic_routes.push_back({
        .grant = grant,
        .adapter = {.binding = provider_route->binding(),
                    .dispatch = provider_host::ProviderRoute::dispatch,
                    .context = provider_route.get()},
        .scope_validator = validator});
    prepared.provider_routes.push_back(std::move(provider_route));
  }
  return prepared;
}

} // namespace

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
SessionRuntimeFactory::SessionRuntimeFactory(
    definitions::TrustedDefinitionRegistry definitions,
    RuntimeServices services, Limits limits)
    : SessionRuntimeFactory(
          std::make_shared<const definitions::TrustedDefinitionRegistry>(
              std::move(definitions)),
          std::make_shared<const RuntimeServices>(
              std::move(services)),
          limits) {}
#endif

SessionRuntimeFactory::SessionRuntimeFactory(
    std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
    std::shared_ptr<const RuntimeServices> services,
    Limits limits)
    : definitions_(std::move(definitions)), services_(std::move(services)),
      limits_(limits) {
  if (!definitions_ || !services_ || limits_.maximum_audit_records == 0 ||
      limits_.maximum_audit_records > audit::kHardMaximumRecords ||
      limits_.maximum_storage_item_bytes == 0 ||
      limits_.maximum_storage_item_bytes > limits_.maximum_storage_bytes)
    throw std::invalid_argument("invalid runtime configuration");
}

const definitions::TrustedDefinitionRegistry &
SessionRuntimeFactory::definitions() const noexcept {
  return *definitions_;
}

definitions::DynamicScopeValidator
SessionRuntimeFactory::scope_validator() const noexcept {
  return runtime_scope_validator(*services_);
}

std::optional<plugin::wire::permission_snapshot::PermissionSnapshot>
SessionRuntimeFactory::project_permissions(
    const plugins::manifest::ManifestV2 &manifest,
    const session::policy::GrantSnapshot &grants) const {
  auto projected = session::project_permission_snapshot(manifest, grants);
  if (!projected)
    return std::nullopt;
  const auto ordered =
      plugins::manifest::canonical_capability_requests(manifest.requests);
  if (ordered.size() != projected->permissions.size())
    return std::nullopt;
  for (std::size_t index = 0; index < ordered.size(); ++index) {
    const auto &request = ordered[index];
    auto &row = projected->permissions[index];
    if (row.state != plugin::wire::permission_snapshot::GrantState::granted)
      continue;
    bool available = false;
    if (request.definition_generation == 0) {
      try {
        available = runtime_service_available(
            *services_, {.id = permissions::CapabilityId(request.capability),
                         .version = 1});
      } catch (...) {
        return std::nullopt;
      }
    } else {
      try {
        available = runtime_service_available(
            *definitions_, *services_,
            {.canonical_name = definitions::Name(request.capability),
             .definition_generation = request.definition_generation,
             .definition_digest =
                 definitions::Digest(request.definition_digest)});
      } catch (...) {
        return std::nullopt;
      }
    }
    if (available)
      continue;
    if (request.required)
      return std::nullopt;
    row.operation_mask = 0;
  }
  return projected;
}

std::unique_ptr<AuthenticatedSessionRuntime>
SessionRuntimeFactory::create(
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
  auto prepared = prepare_runtime(grants, *definitions_, *services_, limits_);
  if (!prepared)
    return {};
  try {
    auto runtime = std::make_unique<ComposedSessionRuntime>(
        definitions_, *services_, grants, std::move(*prepared),
        private_state_directory_fd, session_nonce, std::move(live_generation),
        limits_);
    return runtime;
  } catch (...) {
    return {};
  }
}

} // namespace omarchy::plugin_runtime::channel
