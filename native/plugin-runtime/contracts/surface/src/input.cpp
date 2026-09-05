#include "omarchy/plugin_runtime/surface/input.hpp"

#include <algorithm>
#include <limits>
#include <type_traits>

namespace omarchy::plugin_runtime::surface {
namespace {

std::uint64_t q16_limit(std::uint32_t logical_dimension) {
  return static_cast<std::uint64_t>(logical_dimension) << kQ16FractionBits;
}

bool point_within(const InputPoint &point,
                  const TrustedAllocation &allocation) {
  return point.x_q16 < q16_limit(allocation.logical_width) &&
         point.y_q16 < q16_limit(allocation.logical_height);
}

bool delta_within(std::int32_t delta, std::uint32_t logical_dimension) {
  const auto magnitude =
      delta == std::numeric_limits<std::int32_t>::min()
          ? std::uint64_t{1} << 31
          : static_cast<std::uint64_t>(delta < 0 ? -delta : delta);
  return magnitude <= q16_limit(logical_dimension);
}

bool valid_button_state(ButtonState state) {
  return state == ButtonState::pressed || state == ButtonState::released;
}

bool valid_input_masks(std::uint32_t buttons, std::uint32_t modifiers) {
  return (buttons & ~kSupportedPointerButtonsMask) == 0 &&
         (modifiers & ~kKeyboardModifiersMask) == 0;
}

bool valid_utf8(std::string_view value) {
  std::size_t index = 0;
  while (index < value.size()) {
    const auto first = static_cast<unsigned char>(value[index]);
    std::size_t count = 0;
    std::uint32_t codepoint = 0;
    if (first <= 0x7f) {
      count = 1;
      codepoint = first;
    } else if ((first & 0xe0) == 0xc0) {
      count = 2;
      codepoint = first & 0x1f;
    } else if ((first & 0xf0) == 0xe0) {
      count = 3;
      codepoint = first & 0x0f;
    } else if ((first & 0xf8) == 0xf0) {
      count = 4;
      codepoint = first & 0x07;
    } else {
      return false;
    }
    if (index + count > value.size())
      return false;
    for (std::size_t offset = 1; offset < count; ++offset) {
      const auto continuation =
          static_cast<unsigned char>(value[index + offset]);
      if ((continuation & 0xc0) != 0x80)
        return false;
      codepoint = (codepoint << 6) | (continuation & 0x3f);
    }
    if ((count == 2 && codepoint < 0x80) ||
        (count == 3 && codepoint < 0x800) ||
        (count == 4 && codepoint < 0x10000) ||
        (codepoint >= 0xd800 && codepoint <= 0xdfff) || codepoint > 0x10ffff)
      return false;
    index += count;
  }
  return true;
}

} // namespace

InputValidation validate_input_shape(const InputPayload &payload) {
  return std::visit(
      [](const auto &event) -> InputValidation {
        using Event = std::decay_t<decltype(event)>;
        if constexpr (std::is_same_v<Event, PointerMotion>) {
          return valid_input_masks(event.buttons, event.modifiers)
                     ? InputValidation::accepted
                     : InputValidation::invalid_code;
        } else if constexpr (std::is_same_v<Event, PointerButton>) {
          return event.button != 0 &&
                         (event.button & (event.button - 1)) == 0 &&
                         (event.button & ~kSupportedPointerButtonsMask) == 0 &&
                         valid_button_state(event.state) &&
                         valid_input_masks(event.buttons, event.modifiers)
                     ? InputValidation::accepted
                     : InputValidation::invalid_code;
        } else if constexpr (std::is_same_v<Event, Wheel>) {
          if (!valid_input_masks(event.buttons, event.modifiers) ||
              event.angle_delta_x < -kMaximumWheelAngleDelta ||
              event.angle_delta_x > kMaximumWheelAngleDelta ||
              event.angle_delta_y < -kMaximumWheelAngleDelta ||
              event.angle_delta_y > kMaximumWheelAngleDelta)
            return InputValidation::invalid_code;
          return event.phase == WheelPhase::discrete ||
                         event.phase == WheelPhase::begin ||
                         event.phase == WheelPhase::update ||
                         event.phase == WheelPhase::momentum ||
                         event.phase == WheelPhase::end
                     ? InputValidation::accepted
                     : InputValidation::invalid_code;
        } else if constexpr (std::is_same_v<Event, Key>) {
          if (event.key == 0 || event.key > kMaximumQtKey ||
              event.native_scan_code > kMaximumNativeScanCode ||
              (event.modifiers & ~kKeyboardModifiersMask) != 0 ||
              !valid_button_state(event.state))
            return InputValidation::invalid_code;
          return event.text.size() <= kMaximumInputTextBytes &&
                         valid_utf8(event.text)
                     ? InputValidation::accepted
                     : InputValidation::invalid_text;
        } else if constexpr (std::is_same_v<Event, TextCommit>) {
          if (event.replacement_start < -kMaximumTextReplacementOffset ||
              event.replacement_start > kMaximumTextReplacementOffset ||
              event.replacement_length >
                  static_cast<std::uint32_t>(kMaximumTextReplacementOffset))
            return InputValidation::invalid_code;
          return event.text.size() <= kMaximumInputTextBytes &&
                         valid_utf8(event.text)
                     ? InputValidation::accepted
                     : InputValidation::invalid_text;
        } else if constexpr (std::is_same_v<Event, TouchFrame>) {
          if ((event.modifiers & ~kKeyboardModifiersMask) != 0)
            return InputValidation::invalid_code;
          if (event.count > kMaximumTouchPoints)
            return InputValidation::too_many_touch_points;
          if ((event.phase == TouchFramePhase::cancel && event.count != 0) ||
              (event.phase != TouchFramePhase::cancel && event.count == 0) ||
              (event.phase != TouchFramePhase::begin &&
               event.phase != TouchFramePhase::update &&
               event.phase != TouchFramePhase::end &&
               event.phase != TouchFramePhase::cancel))
            return InputValidation::invalid_code;
          for (std::size_t index = 0; index < event.count; ++index) {
            const auto &point = event.points[index];
            if (point.id >= kMaximumTouchPoints)
              return InputValidation::invalid_code;
            if (point.state != TouchPointState::pressed &&
                point.state != TouchPointState::updated &&
                point.state != TouchPointState::stationary &&
                point.state != TouchPointState::released)
              return InputValidation::invalid_code;
            for (std::size_t prior = 0; prior < index; ++prior)
              if (event.points[prior].id == point.id)
                return InputValidation::invalid_code;
          }
          return InputValidation::accepted;
        } else {
          return InputValidation::accepted;
        }
      },
      payload);
}

namespace {

InputValidation validate_payload_bounds(const InputPayload &payload,
                                        const TrustedAllocation &allocation,
                                        bool focused) {
  return std::visit(
      [&](const auto &event) -> InputValidation {
        using Event = std::decay_t<decltype(event)>;
        if constexpr (std::is_same_v<Event, PointerMotion> ||
                      std::is_same_v<Event, PointerButton> ||
                      std::is_same_v<Event, Wheel>) {
          if (!point_within(event.position, allocation))
            return InputValidation::coordinate_out_of_bounds;
          if constexpr (std::is_same_v<Event, Wheel>) {
            if (!delta_within(event.pixel_delta_x_q16,
                              allocation.logical_width) ||
                !delta_within(event.pixel_delta_y_q16,
                              allocation.logical_height))
              return InputValidation::delta_out_of_bounds;
          }
        } else if constexpr (std::is_same_v<Event, Key> ||
                             std::is_same_v<Event, TextCommit>) {
          if (!focused)
            return InputValidation::not_focused;
        } else if constexpr (std::is_same_v<Event, TouchFrame>) {
          for (std::size_t index = 0; index < event.count; ++index)
            if (!point_within(event.points[index].position, allocation))
              return InputValidation::coordinate_out_of_bounds;
        }
        return InputValidation::accepted;
      },
      payload);
}

} // namespace

InputValidation validate_input(const InputEvent &event,
                               const TrustedAllocation &allocation, bool active,
                               bool focused) {
  if (event.surface != allocation.surface)
    return InputValidation::stale_surface;
  if (!active && !std::holds_alternative<Cancel>(event.payload))
    return InputValidation::not_active;
  if (event.sequence == 0)
    return InputValidation::zero_sequence;
  const auto shape = validate_input_shape(event.payload);
  return shape == InputValidation::accepted
             ? validate_payload_bounds(event.payload, allocation, focused)
             : shape;
}

InputValidation InputMirror::accept(const InputEvent &event,
                                    const TrustedAllocation &allocation,
                                    bool active) {
  const bool focused = focused_surface_ && *focused_surface_ == event.surface;
  const auto validation = validate_input(event, allocation, active, focused);
  if (validation != InputValidation::accepted)
    return validation;
  if (event.sequence <= last_sequence_)
    return InputValidation::replayed_sequence;
  const bool state_existed = std::ranges::any_of(
      surfaces_.begin(), surfaces_.begin() + surface_count_,
      [&](const SurfaceState &state) { return state.surface == event.surface; });
  auto *state = state_for(event.surface);
  if (state == nullptr)
    return InputValidation::invalid_transition;
  const auto clear_state = [&] {
    state->buttons = 0;
    state->contacts.fill(false);
    state->pressed_keys.fill(PressedKey{});
    state->pressed_key_count = 0;
    state->wheel_active = false;
  };

  const auto transition = std::visit(
      [&](const auto &payload) -> InputValidation {
        using Event = std::decay_t<decltype(payload)>;
        if constexpr (std::is_same_v<Event, PointerMotion>) {
          return payload.buttons == state->buttons
                     ? InputValidation::accepted
                     : InputValidation::invalid_transition;
        } else if constexpr (std::is_same_v<Event, Wheel>) {
          if (payload.buttons != state->buttons)
            return InputValidation::invalid_transition;
          if (payload.phase == WheelPhase::discrete) {
            if (state->wheel_active)
              return InputValidation::invalid_transition;
          } else if (payload.phase == WheelPhase::begin) {
            if (state->wheel_active)
              return InputValidation::invalid_transition;
            state->wheel_active = true;
          } else if (payload.phase == WheelPhase::end) {
            if (!state->wheel_active)
              return InputValidation::invalid_transition;
            state->wheel_active = false;
          } else if (!state->wheel_active) {
            return InputValidation::invalid_transition;
          }
        } else if constexpr (std::is_same_v<Event, PointerButton>) {
          const std::uint32_t bit = payload.button;
          const bool pressed = (state->buttons & bit) != 0;
          if ((payload.state == ButtonState::pressed) == pressed)
            return InputValidation::invalid_transition;
          const auto expected = payload.state == ButtonState::pressed
                                    ? state->buttons | bit
                                    : state->buttons & ~bit;
          if (payload.buttons != expected)
            return InputValidation::invalid_transition;
          state->buttons = expected;
        } else if constexpr (std::is_same_v<Event, Key>) {
          auto begin = state->pressed_keys.begin();
          auto end = begin + state->pressed_key_count;
          const auto found = std::find_if(begin, end, [&](const PressedKey &key) {
            return payload.native_scan_code != 0
                       ? key.native_scan_code == payload.native_scan_code
                       : key.native_scan_code == 0 && key.key == payload.key;
          });
          if (payload.state == ButtonState::pressed) {
            if (found != end) {
              if (!payload.auto_repeat)
                return InputValidation::invalid_transition;
            } else {
              if (payload.auto_repeat ||
                  state->pressed_key_count == state->pressed_keys.size())
                return InputValidation::invalid_transition;
              state->pressed_keys[state->pressed_key_count++] = {
                  .key = payload.key,
                  .native_scan_code = payload.native_scan_code};
            }
          } else {
            if (payload.auto_repeat || found == end)
              return InputValidation::invalid_transition;
            *found = state->pressed_keys[state->pressed_key_count - 1];
            state->pressed_keys[--state->pressed_key_count] = {};
          }
        } else if constexpr (std::is_same_v<Event, TouchFrame>) {
          auto contacts = state->contacts;
          std::array<bool, kMaximumTouchPoints> seen{};
          const bool had_contacts =
              std::ranges::any_of(contacts, [](bool value) { return value; });
          if ((payload.phase == TouchFramePhase::begin && had_contacts) ||
              ((payload.phase == TouchFramePhase::update ||
                payload.phase == TouchFramePhase::end) &&
               !had_contacts))
            return InputValidation::invalid_transition;
          for (std::size_t index = 0; index < payload.count; ++index) {
            const auto &point = payload.points[index];
            seen[point.id] = true;
            const bool active_contact = contacts[point.id];
            if (point.state == TouchPointState::pressed) {
              if (active_contact)
                return InputValidation::invalid_transition;
              contacts[point.id] = true;
            } else if (point.state == TouchPointState::released) {
              if (!active_contact)
                return InputValidation::invalid_transition;
              contacts[point.id] = false;
            } else if (!active_contact) {
              return InputValidation::invalid_transition;
            }
          }
          if (payload.phase != TouchFramePhase::cancel) {
            for (std::size_t id = 0; id < state->contacts.size(); ++id)
              if (state->contacts[id] && !seen[id])
                return InputValidation::invalid_transition;
          }
          const bool any = std::ranges::any_of(contacts, [](bool value) {
            return value;
          });
          if ((payload.phase == TouchFramePhase::begin && !any) ||
              (payload.phase == TouchFramePhase::update && !any) ||
              (payload.phase == TouchFramePhase::end && any))
            return InputValidation::invalid_transition;
          if (payload.phase == TouchFramePhase::cancel)
            state->contacts.fill(false);
          else
            state->contacts = contacts;
        } else if constexpr (std::is_same_v<Event, FocusChanged>) {
          if (payload.focused) {
            if (focused_surface_)
              return InputValidation::invalid_transition;
            focused_surface_ = event.surface;
          } else {
            if (!focused)
              return InputValidation::invalid_transition;
            focused_surface_.reset();
            clear_state();
          }
        } else if constexpr (std::is_same_v<Event, Cancel>) {
          clear_state();
          if (focused)
            focused_surface_.reset();
        }
        return InputValidation::accepted;
      },
      event.payload);
  if (transition == InputValidation::accepted) {
    last_sequence_ = event.sequence;
  } else if (!state_existed) {
    release(event.surface);
  }
  return transition;
}

void InputMirror::release(SurfaceKey surface) noexcept {
  if (focused_surface_ && *focused_surface_ == surface)
    focused_surface_.reset();
  const auto found = std::ranges::find_if(
      surfaces_.begin(), surfaces_.begin() + surface_count_,
      [surface](const SurfaceState &state) { return state.surface == surface; });
  if (found == surfaces_.begin() + surface_count_)
    return;
  *found = surfaces_[surface_count_ - 1];
  surfaces_[surface_count_ - 1] = {};
  --surface_count_;
}

std::optional<SurfaceKey> InputMirror::focused_surface() const noexcept {
  return focused_surface_;
}

bool InputMirror::touch_active(SurfaceKey surface) const noexcept {
  const auto found = std::ranges::find_if(
      surfaces_.begin(), surfaces_.begin() + surface_count_,
      [surface](const SurfaceState &state) { return state.surface == surface; });
  return found != surfaces_.begin() + surface_count_ &&
         std::ranges::any_of(found->contacts, [](bool value) { return value; });
}

InputMirror::SurfaceState *
InputMirror::state_for(SurfaceKey surface) noexcept {
  const auto found = std::ranges::find_if(
      surfaces_.begin(), surfaces_.begin() + surface_count_,
      [surface](const SurfaceState &state) { return state.surface == surface; });
  if (found != surfaces_.begin() + surface_count_)
    return &*found;
  if (surface_count_ == surfaces_.size())
    return nullptr;
  surfaces_[surface_count_] = {.surface = surface};
  return &surfaces_[surface_count_++];
}

} // namespace omarchy::plugin_runtime::surface
