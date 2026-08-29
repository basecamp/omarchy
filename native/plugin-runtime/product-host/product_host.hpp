#pragma once

#include "discovery.hpp"
#include "grant_store.hpp"
#include "headless_slice.hpp"
#include "surface_host.hpp"

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
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
  struct SurfaceEntrypoint {
    std::string surface;
    std::string qml;

    bool operator==(const SurfaceEntrypoint &) const = default;
  };

  struct PermissionAvailability {
    std::string capability;
    std::string operation;
    bool granted = false;
  };
  PreparedPlugin(discovery::VerifiedPlugin verified,
                 permissions::ActivationBinding activation,
                 std::vector<surface_host::NamedSurfacePolicy> policies,
                 std::vector<SurfaceEntrypoint> surface_entrypoints,
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
  std::vector<SurfaceEntrypoint> surface_entrypoints;
  std::vector<PermissionAvailability> permission_availability;
  int revision_directory_fd = -1;
};

enum class SurfaceIntentAction { toggle, focus, dismiss };

struct SurfaceCommand {
  std::string target_surface;
  SurfaceIntentAction action = SurfaceIntentAction::toggle;

  bool operator==(const SurfaceCommand &) const = default;
};

// One trusted activation owns every declared surface. A shell adapter registers
// each authenticated worker/session with an unguessable host nonce and routes
// only these bounded commands; plugin-provided shell text never crosses the
// boundary. All registrations share the PreparedPlugin binding and permission
// snapshot, so update/revocation generation changes invalidate the whole set.
class MultiSurfaceActivation final {
public:
  explicit MultiSurfaceActivation(const PreparedPlugin &prepared);

  [[nodiscard]] bool register_surface(
      std::string_view surface, std::uint64_t authenticated_session_nonce,
      const permissions::ActivationBinding &binding);
  [[nodiscard]] std::optional<SurfaceCommand> route_intent(
      std::string_view source_surface,
      std::uint64_t authenticated_session_nonce,
      const permissions::ActivationBinding &binding,
      std::string_view target_surface, SurfaceIntentAction action,
      bool trusted_user_gesture) const;
  [[nodiscard]] std::optional<std::string_view>
  qml_entry(std::string_view surface) const;

private:
  struct RegisteredSurface {
    std::string surface;
    std::uint64_t nonce = 0;
  };

  const PreparedPlugin &prepared_;
  std::vector<RegisteredSurface> registered_;
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

// Starts one declared entry under the same verified activation/broker snapshot.
// The selected name is sent only over the authenticated control channel; the
// worker resolves it against the content-identified manifest.
[[nodiscard]] headless::StartResult launch_surface_with_broker_for_lab(
    launcher::Supervisor &supervisor, const PreparedPlugin &prepared,
    std::string_view surface, int private_state_directory_fd,
    health::HealthSupervisor &health,
    std::shared_ptr<channel::BrokerDispatcher> dispatcher,
    std::shared_ptr<const channel::GenerationAuthority> authority,
    std::uint64_t now_seconds,
    std::chrono::milliseconds negotiation_timeout);

// Sends a complete replacement snapshot over the authenticated control
// channel. Revocation/update callers rebuild it from the current grant store.
[[nodiscard]] bool update_permission_availability(
    headless::Session &session, const PreparedPlugin &prepared);
[[nodiscard]] bool bind_surface_session(
    headless::Session &session, const PreparedPlugin &prepared,
    std::string_view surface, std::uint64_t surface_id,
    std::uint64_t surface_generation);

} // namespace omarchy::plugin_runtime::product_host
