#include "TrustedInputAuthority.h"

#include <algorithm>
#include <limits>
#include <type_traits>
#include <utility>

namespace omarchy::plugin_runtime::bridge {

std::optional<TrustedInputAuthority::Admission>
TrustedInputAuthority::admit(const surface::TrustedAllocation &allocation,
                             HostInputEvent input, bool active) {
  if (sequence_ == std::numeric_limits<std::uint64_t>::max()) {
    clear_all_state();
    return std::nullopt;
  }
  std::optional<surface::TouchFrame> normalized_touch;
  surface::InputPayload payload;
  if (const auto *touch = std::get_if<HostTouchFrame>(&input.payload)) {
    if (input.device == 0)
      return std::nullopt;
    if (touch_surface_.id != 0 &&
        (touch_surface_ != allocation.surface ||
         touch_device_ != input.device))
      return std::nullopt;
    normalized_touch = normalize_touch(*touch, input.device);
    if (!normalized_touch)
      return std::nullopt;
    payload = *normalized_touch;
  } else {
    auto semantic = std::visit(
        [](auto value) -> std::optional<surface::InputPayload> {
          using Value = std::decay_t<decltype(value)>;
          if constexpr (std::is_same_v<Value, HostTouchFrame>)
            return std::nullopt;
          else
            return surface::InputPayload(std::move(value));
        },
        std::move(input.payload));
    if (!semantic)
      return std::nullopt;
    payload = std::move(*semantic);
  }
  if (std::holds_alternative<surface::PointerButton>(payload) ||
      std::holds_alternative<surface::PointerMotion>(payload)) {
    if (captured_buttons_ != 0 &&
        (pointer_surface_ != allocation.surface ||
         pointer_device_ != input.device))
      return std::nullopt;
  } else if (const auto *wheel = std::get_if<surface::Wheel>(&payload)) {
    if (wheel->phase != surface::WheelPhase::discrete &&
        wheel->phase != surface::WheelPhase::begin &&
        (wheel_surface_ != allocation.surface || wheel_device_ == 0 ||
         wheel_device_ != input.device))
      return std::nullopt;
    if (wheel->phase == surface::WheelPhase::begin &&
        (input.device == 0 || wheel_surface_.id != 0))
      return std::nullopt;
  } else if (const auto *touch = std::get_if<surface::TouchFrame>(&payload)) {
    if ((touch->phase == surface::TouchFramePhase::begin &&
         touch_surface_.id != 0) ||
        (touch->phase != surface::TouchFramePhase::begin &&
         (touch_surface_ != allocation.surface || touch_device_ == 0 ||
          touch_device_ != input.device)))
      return std::nullopt;
  }
  surface::InputEvent event{.surface = allocation.surface,
                            .sequence = sequence_ + 1,
                            .payload = std::move(payload)};
  const bool activation =
      (std::holds_alternative<surface::PointerButton>(event.payload) &&
       std::get<surface::PointerButton>(event.payload).state ==
           surface::ButtonState::pressed) ||
      (std::holds_alternative<surface::TouchFrame>(event.payload) &&
       std::get<surface::TouchFrame>(event.payload).phase ==
           surface::TouchFramePhase::begin) ||
      (std::holds_alternative<surface::Key>(event.payload) &&
       std::get<surface::Key>(event.payload).state ==
           surface::ButtonState::pressed &&
       !std::get<surface::Key>(event.payload).auto_repeat);
  if (activation && input.device == 0)
    return std::nullopt;
  if (mirror_.accept(event, allocation, active) !=
      surface::InputValidation::accepted)
    return std::nullopt;
  if (const auto *button = std::get_if<surface::PointerButton>(&event.payload)) {
    if (button->state == surface::ButtonState::pressed) {
      pointer_surface_ = allocation.surface;
      pointer_device_ = input.device;
      captured_buttons_ |= button->button;
      if (input.trusted_physical)
        trusted_buttons_ |= button->button;
    } else if (button->state == surface::ButtonState::released &&
               pointer_surface_ == allocation.surface &&
               pointer_device_ == input.device) {
      captured_buttons_ &= ~button->button;
      trusted_buttons_ &= ~button->button;
      if (captured_buttons_ == 0) {
        pointer_surface_ = {};
        pointer_device_ = 0;
      }
    }
  } else if (const auto *wheel = std::get_if<surface::Wheel>(&event.payload)) {
    if (wheel->phase == surface::WheelPhase::begin) {
      wheel_surface_ = allocation.surface;
      wheel_device_ = input.device;
    } else if (wheel->phase == surface::WheelPhase::end) {
      wheel_surface_ = {};
      wheel_device_ = 0;
    }
  } else if (const auto *touch =
                 std::get_if<surface::TouchFrame>(&event.payload)) {
    if (touch->phase == surface::TouchFramePhase::begin) {
      touch_surface_ = allocation.surface;
      touch_device_ = input.device;
      trusted_touch_ = input.trusted_physical;
    } else if (touch->phase == surface::TouchFramePhase::end ||
               touch->phase == surface::TouchFramePhase::cancel) {
      touch_surface_ = {};
      touch_device_ = 0;
      trusted_touch_ = false;
    }
    if (normalized_touch)
      commit_touch(std::get<HostTouchFrame>(input.payload), *normalized_touch);
  } else if (const auto *focus =
                 std::get_if<surface::FocusChanged>(&event.payload);
             focus != nullptr && !focus->focused) {
    clear_surface_state(allocation.surface);
  }
  ++sequence_;
  return Admission{.event = std::move(event),
                   .trusted_gesture = input.trusted_physical && activation};
}

std::optional<surface::InputEvent> TrustedInputAuthority::cancel(
    const surface::TrustedAllocation &allocation) noexcept {
  if (sequence_ == std::numeric_limits<std::uint64_t>::max()) {
    clear_all_state();
    return std::nullopt;
  }
  surface::InputEvent event{.surface = allocation.surface,
                            .sequence = sequence_ + 1,
                            .payload = surface::Cancel{}};
  if (mirror_.accept(event, allocation, false) !=
      surface::InputValidation::accepted) {
    mirror_.release(allocation.surface);
    clear_surface_state(allocation.surface);
    return std::nullopt;
  }
  ++sequence_;
  clear_surface_state(allocation.surface);
  return event;
}

void TrustedInputAuthority::release(surface::SurfaceKey surface) noexcept {
  mirror_.release(surface);
  clear_surface_state(surface);
}

void TrustedInputAuthority::clear_surface_state(
    surface::SurfaceKey surface) noexcept {
  if (pointer_surface_ == surface) {
    pointer_surface_ = {};
    pointer_device_ = 0;
    captured_buttons_ = 0;
    trusted_buttons_ = 0;
  }
  if (touch_surface_ == surface) {
    touch_surface_ = {};
    touch_device_ = 0;
    trusted_touch_ = false;
    contacts_.fill({});
  }
  if (wheel_surface_ == surface) {
    wheel_surface_ = {};
    wheel_device_ = 0;
  }
}

void TrustedInputAuthority::clear_all_state() noexcept {
  mirror_ = surface::InputMirror{};
  pointer_surface_ = {};
  pointer_device_ = 0;
  captured_buttons_ = 0;
  trusted_buttons_ = 0;
  touch_surface_ = {};
  touch_device_ = 0;
  trusted_touch_ = false;
  wheel_surface_ = {};
  wheel_device_ = 0;
  contacts_.fill({});
}

std::optional<surface::SurfaceKey>
TrustedInputAuthority::focused_surface() const noexcept {
  return mirror_.focused_surface();
}

bool TrustedInputAuthority::pointer_captured(
    surface::SurfaceKey surface, std::uint64_t device) const noexcept {
  return captured_buttons_ != 0 && pointer_surface_ == surface &&
         pointer_device_ == device;
}

bool TrustedInputAuthority::touch_captured(
    surface::SurfaceKey surface, std::uint64_t device) const noexcept {
  return touch_device_ != 0 && touch_surface_ == surface &&
         touch_device_ == device;
}

bool TrustedInputAuthority::wheel_captured(
    surface::SurfaceKey surface, std::uint64_t device) const noexcept {
  return wheel_device_ != 0 && wheel_surface_ == surface &&
         wheel_device_ == device;
}

bool TrustedInputAuthority::surface_has_physical_activation(
    surface::SurfaceKey surface) const noexcept {
  return (pointer_surface_ == surface && trusted_buttons_ != 0) ||
         (touch_surface_ == surface && trusted_touch_);
}

std::optional<surface::TouchFrame> TrustedInputAuthority::normalize_touch(
  const HostTouchFrame &frame, std::uint64_t device) const {
  if (frame.count > frame.points.size() ||
      (touch_device_ != 0 && touch_device_ != device))
    return std::nullopt;
  const auto existing_contacts = contacts_;
  auto contacts = existing_contacts;
  surface::TouchFrame output{.phase = frame.phase,
                             .count = frame.count,
                             .modifiers = frame.modifiers};
  for (std::size_t index = 0; index < frame.count; ++index) {
    const auto &source = frame.points[index];
    auto found = std::find_if(contacts.begin(), contacts.end(),
                              [&](const Contact &contact) {
                                return contact.active &&
                                       contact.raw_id == source.id;
                              });
    if (source.state == surface::TouchPointState::pressed) {
      if (found != contacts.end())
        return std::nullopt;
      found = std::find_if(contacts.begin(), contacts.end(),
                           [](const Contact &contact) {
                             return !contact.active;
                           });
      if (found == contacts.end())
        return std::nullopt;
      found->raw_id = source.id;
      found->active = true;
    } else if (found == contacts.end()) {
      return std::nullopt;
    }
    output.points[index] = {
        .id = static_cast<std::uint32_t>(found - contacts.begin()),
        .state = source.state,
        .position = source.position};
    if (source.state == surface::TouchPointState::released)
      found->active = false;
  }
  if (frame.phase != surface::TouchFramePhase::cancel) {
    for (const auto &contact : existing_contacts) {
      if (!contact.active)
        continue;
      const bool present = std::ranges::any_of(
          frame.points.begin(), frame.points.begin() + frame.count,
          [&](const HostTouchPoint &point) {
            return point.id == contact.raw_id;
          });
      if (!present)
        return std::nullopt;
    }
  }
  return output;
}

void TrustedInputAuthority::commit_touch(
    const HostTouchFrame &frame,
    const surface::TouchFrame &normalized) noexcept {
  if (frame.phase == surface::TouchFramePhase::cancel) {
    contacts_.fill({});
    return;
  }
  for (std::size_t index = 0; index < frame.count; ++index) {
    const auto slot = normalized.points[index].id;
    contacts_[slot] = {
        .raw_id = frame.points[index].id,
        .active = frame.points[index].state !=
                  surface::TouchPointState::released};
  }
  if (!std::ranges::any_of(contacts_, [](const Contact &contact) {
        return contact.active;
      }))
    contacts_.fill({});
}

} // namespace omarchy::plugin_runtime::bridge
