#pragma once

#include "authenticated_channel.hpp"
#include "broker_runtime.hpp"
#include "lifecycle.hpp"
#include "supervisor_health.hpp"

#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <string_view>

namespace omarchy::plugin_runtime::transition {

namespace channel = omarchy::plugin_runtime::channel;
namespace grant = omarchy::plugins::grants;
namespace health = omarchy::plugin_runtime::health;
namespace lifecycle = omarchy::plugins::lifecycle;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace permissions = omarchy::plugins::permissions;
namespace runtime = omarchy::plugin_runtime::runtime;

enum class Status : std::uint8_t {
  accepted,
  denied,
  stale,
  lifecycle_failed,
  health_failed,
  runtime_failed,
  rollback_failed,
};

struct Result {
  Status status = Status::denied;
  std::string detail;
  [[nodiscard]] bool ok() const { return status == Status::accepted; }
};

class AuthenticatedChannelWorker final : public health::WorkerControl {
public:
  explicit AuthenticatedChannelWorker(
      std::unique_ptr<channel::AuthenticatedBrokerChannel> channel);
  [[nodiscard]] const launcher::LaunchIdentity &identity() const override;
  [[nodiscard]] bool alive() const override;
  [[nodiscard]] bool terminate() override;

private:
  std::unique_ptr<channel::AuthenticatedBrokerChannel> channel_;
};

class UpdateTransition {
public:
  UpdateTransition(lifecycle::LifecycleManager &lifecycle,
                   health::HealthSupervisor &health,
                   permissions::PluginId plugin);

  [[nodiscard]] Result
  bind_active(std::unique_ptr<health::WorkerControl> worker,
              std::shared_ptr<runtime::AuditedBrokerRuntime> broker,
              std::uint64_t now_seconds);
  [[nodiscard]] lifecycle::StageOutcome
  stage(const std::filesystem::path &source_root, std::string_view directory,
        std::string_view pinned_tree_sha256,
        omarchy::plugins::store::FaultPoint fault =
            omarchy::plugins::store::FaultPoint::none);
  [[nodiscard]] Result
  decide_candidate(const permissions::CapabilityKey &capability,
                   const std::optional<permissions::Scope> &scope,
                   permissions::UserDecision decision,
                   std::uint64_t wall_seconds);
  [[nodiscard]] Result
  prepare_candidate(std::unique_ptr<health::WorkerControl> worker,
                    std::shared_ptr<runtime::AuditedBrokerRuntime> broker,
                    std::uint64_t now_seconds);
  [[nodiscard]] Result candidate_ready(std::uint64_t now_seconds);
  [[nodiscard]] Result activate(omarchy::plugins::store::FaultPoint fault =
                                    omarchy::plugins::store::FaultPoint::none);
  [[nodiscard]] Result abort_candidate();
  [[nodiscard]] runtime::RevocationResult
  revoke(const permissions::CapabilityKey &capability);

  [[nodiscard]] std::shared_ptr<runtime::AuditedBrokerRuntime>
  active_runtime() const {
    return active_runtime_;
  }
  [[nodiscard]] const std::optional<permissions::ActivationBinding> &
  active_binding() const {
    return active_binding_;
  }
  [[nodiscard]] const std::optional<permissions::ActivationBinding> &
  candidate_binding() const {
    return candidate_binding_;
  }

private:
  [[nodiscard]] const grant::PluginGrants *
  plugin_state(const grant::StoreState &state) const;
  [[nodiscard]] bool candidate_review_complete() const;
  [[nodiscard]] bool candidate_runtime_current() const;
  void clear_candidate();

  lifecycle::LifecycleManager &lifecycle_;
  health::HealthSupervisor &health_;
  permissions::PluginId plugin_;
  std::optional<permissions::ActivationBinding> active_binding_;
  std::optional<permissions::ActivationBinding> candidate_binding_;
  permissions::DeltaSet candidate_delta_;
  std::shared_ptr<runtime::AuditedBrokerRuntime> active_runtime_;
  std::shared_ptr<runtime::AuditedBrokerRuntime> candidate_runtime_;
  bool candidate_attached_ = false;
  bool candidate_is_ready_ = false;
};

} // namespace omarchy::plugin_runtime::transition
