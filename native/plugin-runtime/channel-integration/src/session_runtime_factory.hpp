#pragma once

#include "plugin_session.hpp"
#include "dynamic_activation.hpp"
#include "omarchy/plugin_runtime/providers/provider_set.hpp"
#include "omarchy/plugin_runtime/provider_host/provider_host.hpp"

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

namespace omarchy::plugin_runtime::channel {

namespace definitions = omarchy::plugins::definitions;
namespace providers = omarchy::plugin_runtime::providers;
namespace provider_host = omarchy::plugin_runtime::provider_host;

class PluginRuntimeRoot;
class RuntimeBootstrapTestAccess;

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
struct TrustedDynamicService final {
  definitions::AdapterBinding binding;
  definitions::DynamicAdapterDispatch dispatch = nullptr;
};
#endif

// All callbacks are trusted, synchronous host services. They must finish every
// effect before returning, must not invoke permission/session lifecycle APIs,
// and must not retain requests, payloads, or authority for later work. The
// shared context is retained for every runtime using it.
struct RuntimeServices final {
  std::shared_ptr<void> context;
  providers::NotificationSend notification_send = nullptr;
  providers::AudioPlay audio_play = nullptr;
  definitions::DynamicScopeCompare compare_scope = nullptr;
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  std::vector<TrustedDynamicService> dynamic_services;
#endif
  std::shared_ptr<const provider_host::ProviderCatalog> provider_catalog;
};

// Trusted availability is derived from the frozen service table and exact
// definition identity. It never returns a callback or selects a provider by a
// plugin-supplied alias.
[[nodiscard]] bool runtime_service_available(
    const RuntimeServices &services,
    const plugins::permissions::CapabilityKey &capability) noexcept;
[[nodiscard]] bool runtime_service_available(
    const definitions::TrustedDefinitionRegistry &definitions,
    const RuntimeServices &services,
    const definitions::CapabilityReference &definition) noexcept;
// Scope equality is always available from the trusted definition contract.
// A provider may add schema-specific narrowing, but definition review never
// depends on the provider process being present.
[[nodiscard]] definitions::DynamicScopeValidator
runtime_scope_validator(const RuntimeServices &services) noexcept;

struct Limits final {
  std::size_t maximum_audit_records = 1024;
  std::uint64_t maximum_storage_bytes = 64 * 1024 * 1024;
  std::uint64_t maximum_storage_item_bytes = 1024 * 1024;
};

inline constexpr std::chrono::milliseconds kProviderSettlementMargin{250};
static_assert(provider_host::kMaximumProviderInvocationTimeout +
                  kProviderSettlementMargin <=
              session::SessionLimits::kMaximumIoTimeout);

// Provider dispatch is synchronous at the authenticated channel boundary.
// Runtime sessions therefore retain a bounded transport/scheduling margin
// after the provider's invocation contract, without changing generic sessions.
[[nodiscard]] inline session::SessionLimits
provider_backed_session_limits() noexcept {
  session::SessionLimits limits;
  limits.io_timeout =
      provider_host::kMaximumProviderInvocationTimeout +
      kProviderSettlementMargin;
  return limits;
}

// Sole concrete factory for the runtime authenticated-session path. Plugin
// data supplies no callback, provider pointer, definition, quota, or path.
class SessionRuntimeFactory final
    : public AuthenticatedSessionRuntimeFactory {
public:
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  // Test-only value seam. Runtime composition shares one frozen registry
  // and service context from RuntimeBootstrap.
  SessionRuntimeFactory(
      definitions::TrustedDefinitionRegistry definitions,
      RuntimeServices services, Limits limits = {});
#endif
  [[nodiscard]] const definitions::TrustedDefinitionRegistry &
  definitions() const noexcept;
  [[nodiscard]] definitions::DynamicScopeValidator
  scope_validator() const noexcept;
  [[nodiscard]] std::optional<
      plugin::wire::permission_snapshot::PermissionSnapshot>
  project_permissions(
      const plugins::manifest::ManifestV2 &manifest,
      const session::policy::GrantSnapshot &grants) const override;

  [[nodiscard]] std::unique_ptr<AuthenticatedSessionRuntime>
  create(const plugins::manifest::ManifestV2 &manifest,
         const session::policy::GrantSnapshot &grants,
         int revision_directory_fd, int private_state_directory_fd,
         std::uint64_t session_nonce,
         std::shared_ptr<session::LiveGenerationState> live_generation,
         std::shared_ptr<runtime::GestureEligibilityLatch>
             gesture_eligibility) override;

private:
  SessionRuntimeFactory(
      std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
      std::shared_ptr<const RuntimeServices> services,
      Limits limits = {});

  std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions_;
  std::shared_ptr<const RuntimeServices> services_;
  Limits limits_;

  friend class PluginRuntimeRoot;
  friend class RuntimeBootstrapTestAccess;
};

} // namespace omarchy::plugin_runtime::channel
