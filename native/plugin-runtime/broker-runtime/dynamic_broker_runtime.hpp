#pragma once

#include "audit_store.hpp"
#include "dynamic_activation.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <vector>

namespace omarchy::plugin_runtime::runtime {

namespace definitions = omarchy::plugins::definitions;
namespace wire = omarchy::plugin::wire;

struct DynamicRoute {
  definitions::DynamicRevisionGrant grant;
  definitions::DynamicAdapter adapter;
  definitions::DynamicScopeValidator scope_validator;
};

struct DynamicBrokerResult {
  definitions::DynamicDispatchResult outcome =
      definitions::DynamicDispatchResult::denied;
  definitions::DynamicDecision decision = definitions::DynamicDecision::denied;
  std::size_t response_bytes = 0;
};

enum class DynamicRevocationStatus : std::uint8_t {
  accepted,
  binding_mismatch,
  audit_failed,
  failed,
};

struct DynamicRevocationResult {
  DynamicRevocationStatus status = DynamicRevocationStatus::failed;
  bool restart_worker = false;
};

class DynamicGestureAuthority {
public:
  virtual ~DynamicGestureAuthority() = default;
  [[nodiscard]] virtual bool
  consume(const omarchy::plugins::permissions::ActivationBinding &binding,
          const definitions::DynamicInvocation::GestureClaim &claim) = 0;
};

class DynamicGestureClock {
public:
  virtual ~DynamicGestureClock() = default;
  [[nodiscard]] virtual std::uint64_t now_nanoseconds() const = 0;
};

class DynamicGestureLatch final : public DynamicGestureAuthority {
public:
  explicit DynamicGestureLatch(DynamicGestureClock &clock) : clock_(clock) {}
  [[nodiscard]] bool
  arm(const omarchy::plugins::permissions::ActivationBinding &binding,
      const definitions::DynamicInvocation::GestureClaim &claim);
  [[nodiscard]] bool
  consume(const omarchy::plugins::permissions::ActivationBinding &binding,
          const definitions::DynamicInvocation::GestureClaim &claim) override;
  void clear() noexcept;

private:
  DynamicGestureClock &clock_;
  omarchy::plugins::permissions::ActivationBinding binding_{};
  definitions::DynamicInvocation::GestureClaim claim_{};
  std::uint64_t deadline_nanoseconds_ = 0;
  bool armed_ = false;
};

class DynamicBrokerRuntime {
public:
  DynamicBrokerRuntime(const definitions::TrustedDefinitionRegistry &registry,
                       std::vector<DynamicRoute> reconstructed_routes,
                       omarchy::plugins::audit::AuditSink &audit_sink);

  [[nodiscard]] DynamicBrokerResult dispatch(
      const wire::PacketView &packet,
      const omarchy::plugins::permissions::ActivationBinding &channel_binding,
      std::span<std::byte> response,
      DynamicGestureAuthority *gesture_authority = nullptr);

  [[nodiscard]] bool accepts_binding(
      const omarchy::plugins::permissions::ActivationBinding &binding)
      const noexcept;
  [[nodiscard]] bool empty() const noexcept { return routes_.empty(); }

  // Accepts only the next persisted epoch for the exact same request and
  // definition. The caller remains responsible for cancelling an asynchronous
  // provider before publishing the permission snapshot.
  [[nodiscard]] DynamicRevocationResult apply_reconstructed_revocation(
      const definitions::DynamicRevisionGrant &updated);
  // Temporary compatibility wrapper for the N4 composition seam.
  [[nodiscard]] bool
  apply_reconstructed_update(const definitions::DynamicRevisionGrant &updated) {
    return apply_reconstructed_revocation(updated).status ==
           DynamicRevocationStatus::accepted;
  }
  [[nodiscard]] bool failed() const noexcept { return failed_; }

private:
  const definitions::TrustedDefinitionRegistry &registry_;
  std::vector<DynamicRoute> routes_;
  std::optional<omarchy::plugins::permissions::ActivationBinding> binding_;
  omarchy::plugins::audit::AuditSink &audit_;
  std::uint64_t last_correlation_ = 0;
  bool failed_ = false;
};

} // namespace omarchy::plugin_runtime::runtime
