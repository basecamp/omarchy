#pragma once

#include "plugin_permission_controller.hpp"
#include "production_session_runtime_factory.hpp"

#include <cstdint>
#include <functional>
#include <limits>
#include <memory>
#include <mutex>
#include <optional>
#include <span>
#include <string>

namespace omarchy::plugin_runtime::channel {

// Trusted, non-owning product integration hook. It must outlive the root and
// be constructed by the host, never from plugin or QML data. Callbacks return
// promptly and queue lifecycle or permission work to the next host-loop turn;
// they must not synchronously reenter this root while a session callback is on
// the stack. Queued work referencing the root must be canceled or drained
// before root destruction.
class ProductionPluginRuntimeHooks : public PluginSessionEvents,
                                     public SurfaceIntentSink {
public:
  ~ProductionPluginRuntimeHooks() override = default;
};

struct ProductionPluginRuntimeConfiguration final {
  int activation_root_fd = -1;
  int revision_root_fd = -1;
  int state_root_fd = -1;
  int authority_root_fd = -1;
  permissions::PluginId plugin;
  std::uint32_t trusted_uid = std::numeric_limits<std::uint32_t>::max();
  std::string activation_record;
  definitions::TrustedDefinitionRegistry definitions;
  // This retained provider context must not contain a root, controller,
  // session or hook reference; provider callbacks cannot reenter lifecycle.
  ProductionRuntimeServices services;
  ProductionRuntimeLimits runtime_limits;
  session::SessionLimits session_limits;
  ProductionPluginRuntimeHooks *hooks = nullptr;
};

// Sole production composition for one secure plugin. Every authority-bearing
// input is fixed by the trusted host before this root exists. Plugin QML,
// sidecars and IPC can neither replace these inputs nor reach the objects that
// own grants, providers, session bindings or lifecycle.
class ProductionPluginRuntimeRoot final {
public:
  [[nodiscard]] static std::unique_ptr<ProductionPluginRuntimeRoot>
  open(ProductionPluginRuntimeConfiguration &&configuration);

  ~ProductionPluginRuntimeRoot() noexcept;
  ProductionPluginRuntimeRoot(const ProductionPluginRuntimeRoot &) = delete;
  ProductionPluginRuntimeRoot &
  operator=(const ProductionPluginRuntimeRoot &) = delete;

  [[nodiscard]] std::optional<host_session::AuthorityView> list() const;
  [[nodiscard]] std::shared_ptr<const host_session::ConsentReview>
  prepare_review();
  [[nodiscard]] ReviewedPermissionApplyResult apply_review(
      const host_session::ConsentConfirmation &confirmation,
      std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
      std::span<const host_session::DynamicConsentDecision> dynamic_decisions);
  [[nodiscard]] PermissionRevokeApplyResult
  revoke(const permissions::CapabilityKey &capability,
         std::uint64_t expected_sequence);
  [[nodiscard]] PermissionRevokeApplyResult
  revoke(const definitions::CapabilityReference &definition,
         std::uint64_t expected_sequence);

  [[nodiscard]] PluginActivationResult activate();
  void stop();
  [[nodiscard]] std::optional<permissions::ActivationBinding>
  session_binding() const;

private:
  ProductionPluginRuntimeRoot(
      ProductionPluginRuntimeConfiguration &configuration,
      std::unique_ptr<host_session::AuthorityStore> authority);

  ProductionSessionRuntimeFactory runtime_factory_;
  std::unique_ptr<host_session::AuthorityStore> authority_;
  const std::string activation_record_;
  PluginActivationCoordinator coordinator_;
  PluginPermissionController controller_;
  mutable std::mutex mutex_;

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  friend class ProductionPluginRuntimeRootTestAccess;
#endif
};

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
class ProductionPluginRuntimeRootTestAccess final {
public:
  static void set_supervisor_factory(
      ProductionPluginRuntimeRoot &root,
      std::function<launcher::Supervisor()> factory);
  [[nodiscard]] static std::shared_ptr<session::LiveGenerationState>
  live_generation(const ProductionPluginRuntimeRoot &root) noexcept;
};
#endif

} // namespace omarchy::plugin_runtime::channel
