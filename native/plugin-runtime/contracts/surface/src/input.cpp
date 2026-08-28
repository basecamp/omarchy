#include "omarchy/plugin_runtime/surface/input.hpp"

#include "omarchy/plugin_runtime/surface/checked_math.hpp"

#include <cstdint>
#include <limits>

namespace omarchy::plugin_runtime::surface {
namespace {

std::uint64_t q16_limit(std::uint32_t logical_dimension) {
  return static_cast<std::uint64_t>(logical_dimension) << kQ16FractionBits;
}

bool delta_within(std::int32_t delta, std::uint32_t logical_dimension) {
  const auto magnitude =
      delta == std::numeric_limits<std::int32_t>::min()
          ? std::uint64_t{1} << 31
          : static_cast<std::uint64_t>(delta < 0 ? -delta : delta);
  return magnitude <= q16_limit(logical_dimension);
}

} // namespace

InputValidation validate_input(const InputEvent &event,
                               const TrustedAllocation &allocation, bool active,
                               bool focused) {
  switch (event.kind) {
  case InputKind::pointer_motion:
  case InputKind::pointer_button:
  case InputKind::scroll:
  case InputKind::key:
  case InputKind::touch:
    break;
  default:
    return InputValidation::invalid_kind;
  }
  if (event.surface != allocation.surface) {
    return InputValidation::stale_surface;
  }
  if (!active) {
    return InputValidation::not_active;
  }
  if (event.sequence == 0) {
    return InputValidation::zero_sequence;
  }
  if ((event.kind == InputKind::key ||
       event.kind == InputKind::pointer_button ||
       event.kind == InputKind::touch) &&
      !focused) {
    return InputValidation::not_focused;
  }
  if (event.x_q16 >= q16_limit(allocation.logical_width) ||
      event.y_q16 >= q16_limit(allocation.logical_height)) {
    return InputValidation::coordinate_out_of_bounds;
  }
  if (!delta_within(event.delta_x_q16, allocation.logical_width) ||
      !delta_within(event.delta_y_q16, allocation.logical_height)) {
    return InputValidation::delta_out_of_bounds;
  }
  if (event.kind == InputKind::pointer_motion &&
      (event.code != 0 || event.state != 0 || event.active_touch_points != 0)) {
    return InputValidation::invalid_code;
  }
  if (event.kind == InputKind::pointer_button &&
      (event.code == 0 || event.code > 16 || event.active_touch_points != 0 ||
       event.delta_x_q16 != 0 || event.delta_y_q16 != 0 ||
       (event.state != static_cast<std::uint32_t>(ButtonState::pressed) &&
        event.state != static_cast<std::uint32_t>(ButtonState::released)))) {
    return InputValidation::invalid_code;
  }
  if (event.kind == InputKind::scroll &&
      (event.code > 1 || event.state > 3 || event.active_touch_points != 0)) {
    return InputValidation::invalid_code;
  }
  if (event.kind == InputKind::key &&
      (event.code == 0 || event.code > 0x2ffU ||
       (event.state != static_cast<std::uint32_t>(ButtonState::pressed) &&
        event.state != static_cast<std::uint32_t>(ButtonState::released)) ||
       event.active_touch_points != 0 || event.x_q16 != 0 || event.y_q16 != 0 ||
       event.delta_x_q16 != 0 || event.delta_y_q16 != 0)) {
    return InputValidation::invalid_code;
  }
  if (event.kind == InputKind::touch) {
    if (event.active_touch_points > kMaximumTouchPoints) {
      return InputValidation::too_many_touch_points;
    }
    if (event.code == 0 || event.code > kMaximumTouchPoints ||
        event.state == 0 || event.state > 3 || event.delta_x_q16 != 0 ||
        event.delta_y_q16 != 0) {
      return InputValidation::invalid_code;
    }
  }
  return InputValidation::accepted;
}

InputGate::InputGate(TrustedAllocation allocation) : allocation_(allocation) {}

std::optional<InputGate>
InputGate::create(const TrustedAllocation &allocation) {
  if (!allocation_is_consistent(allocation)) {
    return std::nullopt;
  }
  return InputGate(allocation);
}

InputValidation InputGate::accept(const InputEvent &event, bool active,
                                  bool focused) {
  const auto validation = validate_input(event, allocation_, active, focused);
  if (validation != InputValidation::accepted) {
    return validation;
  }
  if (event.sequence <= last_sequence_) {
    return InputValidation::replayed_sequence;
  }
  last_sequence_ = event.sequence;
  return InputValidation::accepted;
}

FocusGate::FocusGate(TrustedAllocation allocation) : allocation_(allocation) {}

std::optional<FocusGate>
FocusGate::create(const TrustedAllocation &allocation) {
  if (!allocation_is_consistent(allocation)) {
    return std::nullopt;
  }
  return FocusGate(allocation);
}

InputValidation FocusGate::accept(const FocusEvent &event, bool active) {
  if (event.surface != allocation_.surface) {
    return InputValidation::stale_surface;
  }
  if (!active) {
    return InputValidation::not_active;
  }
  if (event.sequence == 0) {
    return InputValidation::zero_sequence;
  }
  if (event.sequence <= last_sequence_) {
    return InputValidation::replayed_sequence;
  }
  last_sequence_ = event.sequence;
  return InputValidation::accepted;
}

} // namespace omarchy::plugin_runtime::surface
