#pragma once

#include "authenticated_channel.hpp"
#include "supervisor_health.hpp"

#include <chrono>
#include <cstdint>
#include <memory>
#include <string>

namespace omarchy::plugin_runtime::headless {

namespace channel = omarchy::plugin_runtime::channel;
namespace health = omarchy::plugin_runtime::health;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace permissions = omarchy::plugins::permissions;

enum class StartFailure {
  none,
  invalid_binding,
  launch,
  health_admission,
  negotiation,
  readiness,
};

class Session;

struct StartResult {
  std::unique_ptr<Session> session;
  StartFailure failure = StartFailure::none;
  std::string detail;

  [[nodiscard]] explicit operator bool() const {
    return session != nullptr && failure == StartFailure::none;
  }
};

class Session final {
public:
  [[nodiscard]] static StartResult
  start(launcher::Supervisor &launcher,
        const launcher::TrustedLaunchRequest &request,
        permissions::ActivationBinding binding,
        health::HealthSupervisor &health_supervisor,
        std::shared_ptr<channel::BrokerDispatcher> no_authority_dispatcher,
        std::shared_ptr<const channel::GenerationAuthority> authority,
        std::uint64_t now_seconds,
        std::chrono::milliseconds negotiation_timeout);

  ~Session();
  Session(const Session &) = delete;
  Session &operator=(const Session &) = delete;

  [[nodiscard]] channel::DispatchStatus
  dispatch_one(std::uint64_t now_seconds, std::chrono::milliseconds timeout);
  [[nodiscard]] health::Status observe_resources(health::ResourceSample sample,
                                                 std::uint64_t now_seconds);
  [[nodiscard]] health::Status stop();
  [[nodiscard]] bool active() const;
  [[nodiscard]] const permissions::ActivationBinding &binding() const;

private:
  class HealthDispatcher;

  Session(permissions::ActivationBinding binding,
          health::HealthSupervisor &health_supervisor,
          std::shared_ptr<channel::AuthenticatedBrokerChannel> channel,
          std::shared_ptr<HealthDispatcher> dispatcher);

  permissions::ActivationBinding binding_;
  health::HealthSupervisor &health_;
  std::shared_ptr<channel::AuthenticatedBrokerChannel> channel_;
  std::shared_ptr<HealthDispatcher> dispatcher_;
  bool active_ = true;
};

} // namespace omarchy::plugin_runtime::headless
