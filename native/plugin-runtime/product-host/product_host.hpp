#pragma once

#include "discovery.hpp"
#include "grant_store.hpp"
#include "headless_slice.hpp"
#include "surface_host.hpp"

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace omarchy::plugin_runtime::product_host {

namespace channel = omarchy::plugin_runtime::channel;
namespace health = omarchy::plugin_runtime::health;
namespace headless = omarchy::plugin_runtime::headless;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace surface_host = omarchy::plugin_runtime::surface_host;
namespace discovery = omarchy::plugins::discovery;
namespace grants = omarchy::plugins::grants;
namespace permissions = omarchy::plugins::permissions;

enum class PrepareFailure {
  none,
  feature_disabled,
  discovery_rejected,
  grant_binding_missing,
  grant_binding_mismatch,
  required_grant_missing,
  surface_invalid,
};

struct PreparedPlugin {
  struct PermissionAvailability {
    std::string capability;
    std::string operation;
    bool granted = false;
  };
  PreparedPlugin(discovery::VerifiedPlugin verified,
                 permissions::ActivationBinding activation,
                 std::vector<surface_host::NamedSurfacePolicy> policies,
                 std::vector<PermissionAvailability> permission_availability,
                 int revision_fd);
  ~PreparedPlugin();
  PreparedPlugin(const PreparedPlugin &) = delete;
  PreparedPlugin &operator=(const PreparedPlugin &) = delete;
  PreparedPlugin(PreparedPlugin &&other) noexcept;
  PreparedPlugin &operator=(PreparedPlugin &&other) noexcept;

  discovery::VerifiedPlugin plugin;
  permissions::ActivationBinding binding;
  std::vector<surface_host::NamedSurfacePolicy> surfaces;
  std::vector<PermissionAvailability> permission_availability;
  int revision_directory_fd = -1;
};

struct PrepareResult {
  std::unique_ptr<PreparedPlugin> prepared;
  PrepareFailure failure = PrepareFailure::none;
  std::string detail;

  [[nodiscard]] explicit operator bool() const { return prepared != nullptr; }
};

// This is trusted host configuration, not a plugin-controlled environment
// lookup. Product rollout must set it only after explicit user review.
struct Configuration {
  bool schema_v2_enabled = false;
};

[[nodiscard]] PrepareResult prepare(
    const std::filesystem::path &plugin_root,
    const discovery::IdentityPin &identity_pin,
    const grants::RevisionGrants &active_grants,
    Configuration configuration);

class DenyAllBroker final : public channel::BrokerDispatcher {
public:
  explicit DenyAllBroker(permissions::ActivationBinding binding);
  [[nodiscard]] bool
  accepts(const launcher::LaunchIdentity &identity) const noexcept override;
  [[nodiscard]] bool
  dispatch(const omarchy::plugin::wire::PacketView &packet) override;

private:
  permissions::ActivationBinding binding_;
};

// Launches the verified arbitrary-QML entry point through the production
// Bubblewrap worker and authenticated three-channel handshake. The returned
// surface policies remain host-owned; a shell adapter decides placement and
// instantiates RemotePluginSurface items from them.
[[nodiscard]] headless::StartResult launch(
    launcher::Supervisor &supervisor, const PreparedPlugin &prepared,
    int private_state_directory_fd, health::HealthSupervisor &health,
    std::shared_ptr<const channel::GenerationAuthority> authority,
    std::uint64_t now_seconds,
    std::chrono::milliseconds negotiation_timeout);

// Lab-only composition point. The caller must construct the dispatcher from
// the exact PreparedPlugin grants and trusted provider registry. Product code
// intentionally uses the deny-all overload above unless an explicit lab mode
// selects this function.
[[nodiscard]] headless::StartResult launch_with_broker_for_lab(
    launcher::Supervisor &supervisor, const PreparedPlugin &prepared,
    int private_state_directory_fd, health::HealthSupervisor &health,
    std::shared_ptr<channel::BrokerDispatcher> dispatcher,
    std::shared_ptr<const channel::GenerationAuthority> authority,
    std::uint64_t now_seconds,
    std::chrono::milliseconds negotiation_timeout);

// Sends a complete replacement snapshot over the authenticated control
// channel. Revocation/update callers rebuild it from the current grant store.
[[nodiscard]] bool update_permission_availability(
    headless::Session &session, const PreparedPlugin &prepared);

} // namespace omarchy::plugin_runtime::product_host
