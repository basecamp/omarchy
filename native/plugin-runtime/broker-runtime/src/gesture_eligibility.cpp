#include "gesture_eligibility.hpp"

#include <limits>

namespace omarchy::plugin_runtime::runtime {

namespace {
constexpr std::uint64_t kEligibilityLifetimeNanoseconds = 5'000'000'000ULL;
}

bool ConsumedGestureEligibility::current() const noexcept {
  return clock != nullptr && expires_monotonic_ns != 0 &&
         clock->now_nanoseconds() < expires_monotonic_ns;
}

bool GestureEligibilityLatch::arm(
    const permissions::ActivationBinding &binding,
    const definitions::DynamicInvocation::GestureClaim &claim) {
  const std::lock_guard lock(mutex_);
  if (clock_ == nullptr)
    return false;
  const auto now = clock_->now_nanoseconds();
  if (binding.generation == 0 || claim.surface_id == 0 ||
      claim.surface_generation != binding.generation ||
      claim.input_sequence == 0 ||
      now > std::numeric_limits<std::uint64_t>::max() -
                kEligibilityLifetimeNanoseconds ||
      (armed_ && binding == binding_ && claim.surface_id == claim_.surface_id &&
       claim.surface_generation == claim_.surface_generation &&
       claim.input_sequence <= claim_.input_sequence)) {
    reset_unlocked();
    return false;
  }
  binding_ = binding;
  claim_ = claim;
  deadline_nanoseconds_ = now + kEligibilityLifetimeNanoseconds;
  armed_ = true;
  return true;
}

std::optional<ConsumedGestureEligibility> GestureEligibilityLatch::consume(
    const permissions::ActivationBinding &binding,
    const definitions::DynamicInvocation::GestureClaim &claim) {
  const std::lock_guard lock(mutex_);
  if (!armed_ || clock_ == nullptr)
    return std::nullopt;
  const bool current = clock_->now_nanoseconds() < deadline_nanoseconds_;
  const bool matches = current && binding == binding_ && claim == claim_;
  const auto proof = matches
                         ? std::optional(ConsumedGestureEligibility{
                               .expires_monotonic_ns = deadline_nanoseconds_,
                               .clock = clock_})
                         : std::nullopt;
  reset_unlocked();
  return proof;
}

void GestureEligibilityLatch::clear_surface(
    const permissions::ActivationBinding &binding, std::uint64_t surface_id,
    std::uint64_t surface_generation) noexcept {
  const std::lock_guard lock(mutex_);
  if (armed_ && binding == binding_ && claim_.surface_id == surface_id &&
      claim_.surface_generation == surface_generation)
    reset_unlocked();
}

void GestureEligibilityLatch::clear() noexcept {
  const std::lock_guard lock(mutex_);
  reset_unlocked();
}

void GestureEligibilityLatch::reset_unlocked() noexcept {
  armed_ = false;
  deadline_nanoseconds_ = 0;
  binding_ = {};
  claim_ = {};
}

} // namespace omarchy::plugin_runtime::runtime
