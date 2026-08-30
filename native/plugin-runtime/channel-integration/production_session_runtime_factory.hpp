#pragma once

#include "plugin_session.hpp"
#include "dynamic_activation.hpp"
#include "omarchy/plugin_runtime/providers/provider_set.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

namespace omarchy::plugin_runtime::channel {

namespace definitions = omarchy::plugins::definitions;
namespace providers = omarchy::plugin_runtime::providers;

class ProductionPluginRuntimeRoot;

struct TrustedDynamicService final {
  definitions::AdapterBinding binding;
  definitions::DynamicAdapterDispatch dispatch = nullptr;
};

// All callbacks are trusted, synchronous host services. They must finish every
// effect before returning, must not invoke permission/session lifecycle APIs,
// and must not retain requests, payloads, or authority for later work. The
// shared context is retained for every runtime using it.
struct ProductionRuntimeServices final {
  std::shared_ptr<void> context;
  providers::NotificationSend notification_send = nullptr;
  providers::AudioPlay audio_play = nullptr;
  definitions::DynamicScopeCompare compare_scope = nullptr;
  std::vector<TrustedDynamicService> dynamic_services;
};

struct ProductionRuntimeLimits final {
  std::size_t maximum_audit_records = 1024;
  std::uint64_t maximum_storage_bytes = 64 * 1024 * 1024;
  std::uint64_t maximum_storage_item_bytes = 1024 * 1024;
};

// Sole concrete factory for the production authenticated-session path. Plugin
// data supplies no callback, provider pointer, definition, quota, or path.
class ProductionSessionRuntimeFactory final
    : public AuthenticatedSessionRuntimeFactory {
public:
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  // Test-only value seam. Production composition shares one frozen registry
  // and service context from ProductionPluginBootstrap.
  ProductionSessionRuntimeFactory(
      definitions::TrustedDefinitionRegistry definitions,
      ProductionRuntimeServices services, ProductionRuntimeLimits limits = {});
#endif
  [[nodiscard]] const definitions::TrustedDefinitionRegistry &
  definitions() const noexcept;
  [[nodiscard]] definitions::DynamicScopeValidator
  scope_validator() const noexcept;

  [[nodiscard]] std::unique_ptr<AuthenticatedSessionRuntime>
  create(const plugins::manifest::ManifestV2 &manifest,
         const session::policy::GrantSnapshot &grants,
         int revision_directory_fd, int private_state_directory_fd,
         std::uint64_t session_nonce,
         std::shared_ptr<session::LiveGenerationState> live_generation,
         std::shared_ptr<runtime::GestureEligibilityLatch>
             gesture_eligibility) override;

private:
  ProductionSessionRuntimeFactory(
      std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
      std::shared_ptr<const ProductionRuntimeServices> services,
      ProductionRuntimeLimits limits = {});

  std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions_;
  std::shared_ptr<const ProductionRuntimeServices> services_;
  ProductionRuntimeLimits limits_;

  friend class ProductionPluginRuntimeRoot;
};

} // namespace omarchy::plugin_runtime::channel
