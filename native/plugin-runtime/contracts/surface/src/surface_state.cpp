#include "omarchy/plugin_runtime/surface/surface_state.hpp"

namespace omarchy::plugin_runtime::surface {

SurfaceState::SurfaceState(TrustedAllocation allocation)
    : allocation_(allocation) {}

std::optional<SurfaceState>
SurfaceState::create(const TrustedAllocation &allocation) {
  if (!allocation_is_consistent(allocation)) {
    return std::nullopt;
  }
  return SurfaceState(allocation);
}

bool SurfaceState::apply(SurfaceTransition transition) {
  switch (transition) {
  case SurfaceTransition::activate:
    if (phase_ != SurfacePhase::allocated) {
      return false;
    }
    phase_ = SurfacePhase::active;
    return true;
  case SurfaceTransition::suspend:
    if (phase_ != SurfacePhase::active) {
      return false;
    }
    phase_ = SurfacePhase::suspended;
    return true;
  case SurfaceTransition::resume:
    if (phase_ != SurfacePhase::suspended) {
      return false;
    }
    phase_ = SurfacePhase::active;
    return true;
  case SurfaceTransition::begin_destroy:
    if (phase_ == SurfacePhase::destroyed ||
        phase_ == SurfacePhase::destroying) {
      return false;
    }
    phase_ = SurfacePhase::destroying;
    return true;
  case SurfaceTransition::finish_destroy:
    if (phase_ != SurfacePhase::destroying) {
      return false;
    }
    phase_ = SurfacePhase::destroyed;
    return true;
  }
  return false;
}

bool SurfaceState::accepts_frame(SurfaceKey key) const {
  return phase_ == SurfacePhase::active && key == allocation_.surface;
}

bool SurfaceState::accepts_input(SurfaceKey key, bool focused) const {
  return accepts_frame(key) && focused;
}

SurfacePhase SurfaceState::phase() const { return phase_; }

const TrustedAllocation &SurfaceState::allocation() const {
  return allocation_;
}

} // namespace omarchy::plugin_runtime::surface
