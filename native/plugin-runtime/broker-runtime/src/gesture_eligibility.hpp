#pragma once

#include "dynamic_activation.hpp"

#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>

namespace omarchy::plugin_runtime::runtime {

namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

class GestureEligibilityClock {
public:
  virtual ~GestureEligibilityClock() = default;
  [[nodiscard]] virtual std::uint64_t now_nanoseconds() const = 0;
};

struct ConsumedGestureEligibility {
  std::uint64_t expires_monotonic_ns = 0;
  std::shared_ptr<const GestureEligibilityClock> clock;

  [[nodiscard]] bool current() const noexcept;
};

class GestureEligibilityAuthority {
public:
  virtual ~GestureEligibilityAuthority() = default;
  [[nodiscard]] virtual std::optional<ConsumedGestureEligibility>
  consume(const permissions::ActivationBinding &binding,
          const definitions::DynamicInvocation::GestureClaim &claim) = 0;
};

// One accepted physical input may authorize one effect request. A structurally
// valid consume attempt spends the seed even when its claimed identity is
// wrong, so a sandbox cannot probe an eligibility token and retain it. The
// latch is shared by UI input and broker-settlement threads; each transition
// is serialized so those paths still have exactly one winner.
class GestureEligibilityLatch final : public GestureEligibilityAuthority {
public:
  explicit GestureEligibilityLatch(
      std::shared_ptr<GestureEligibilityClock> clock)
      : clock_(std::move(clock)) {}

  [[nodiscard]] bool
  arm(const permissions::ActivationBinding &binding,
      const definitions::DynamicInvocation::GestureClaim &claim);
  [[nodiscard]] std::optional<ConsumedGestureEligibility>
  consume(const permissions::ActivationBinding &binding,
          const definitions::DynamicInvocation::GestureClaim &claim) override;
  // A surface-local teardown must not erase a newer gesture from a sibling
  // surface in the same plugin session.
  void clear_surface(const permissions::ActivationBinding &binding,
                     std::uint64_t surface_id,
                     std::uint64_t surface_generation) noexcept;
  void clear() noexcept;

private:
  void reset_unlocked() noexcept;

  std::mutex mutex_;
  std::shared_ptr<GestureEligibilityClock> clock_;
  permissions::ActivationBinding binding_{};
  definitions::DynamicInvocation::GestureClaim claim_{};
  std::uint64_t deadline_nanoseconds_ = 0;
  bool armed_ = false;
};

} // namespace omarchy::plugin_runtime::runtime
