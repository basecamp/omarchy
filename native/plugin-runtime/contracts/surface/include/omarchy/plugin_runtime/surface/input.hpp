#pragma once

#include "omarchy/plugin/wire/surface_name.hpp"
#include "omarchy/plugin_runtime/surface/shared_layout.hpp"

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <variant>

namespace omarchy::plugin_runtime::surface {

inline constexpr std::uint32_t kQ16FractionBits = 16;
inline constexpr std::uint32_t kMaximumTouchPoints = 10;
inline constexpr std::size_t kMaximumInputTextBytes = 128;
inline constexpr std::uint32_t kSupportedPointerButtonsMask = 0x1f;
inline constexpr std::uint32_t kKeyboardModifiersMask = 0x7e000000;
inline constexpr std::uint32_t kMaximumQtKey = 0x01ffffff;
inline constexpr std::uint32_t kMaximumNativeScanCode = 0x2ff;
inline constexpr std::int32_t kMaximumWheelAngleDelta = 12000;
inline constexpr std::int32_t kMaximumTextReplacementOffset = 4096;

enum class ButtonState : std::uint32_t { pressed = 1, released = 2 };
enum class WheelPhase : std::uint32_t {
  discrete = 1,
  begin = 2,
  update = 3,
  momentum = 4,
  end = 5,
};
enum class TouchFramePhase : std::uint32_t {
  begin = 1,
  update = 2,
  end = 3,
  cancel = 4,
};
enum class TouchPointState : std::uint32_t {
  pressed = 1,
  updated = 2,
  stationary = 3,
  released = 4,
};

struct InputPoint {
  std::uint32_t x_q16 = 0;
  std::uint32_t y_q16 = 0;
  constexpr bool operator==(const InputPoint &) const = default;
};
struct PointerMotion {
  InputPoint position;
  std::uint32_t buttons = 0;
  std::uint32_t modifiers = 0;
  constexpr bool operator==(const PointerMotion &) const = default;
};
struct PointerButton {
  InputPoint position;
  std::uint32_t button = 0;
  ButtonState state = ButtonState::released;
  std::uint32_t buttons = 0;
  std::uint32_t modifiers = 0;
  constexpr bool operator==(const PointerButton &) const = default;
};
struct Wheel {
  InputPoint position;
  std::int32_t pixel_delta_x_q16 = 0;
  std::int32_t pixel_delta_y_q16 = 0;
  std::int32_t angle_delta_x = 0;
  std::int32_t angle_delta_y = 0;
  WheelPhase phase = WheelPhase::update;
  std::uint32_t buttons = 0;
  std::uint32_t modifiers = 0;
  bool inverted = false;
  constexpr bool operator==(const Wheel &) const = default;
};
struct Key {
  std::uint32_t key = 0;
  std::uint32_t native_scan_code = 0;
  std::uint32_t modifiers = 0;
  ButtonState state = ButtonState::released;
  bool auto_repeat = false;
  std::string text;
  bool operator==(const Key &) const = default;
};
struct TextCommit {
  std::string text;
  std::int32_t replacement_start = 0;
  std::uint32_t replacement_length = 0;
  bool operator==(const TextCommit &) const = default;
};
struct TouchPoint {
  std::uint32_t id = 0;
  TouchPointState state = TouchPointState::stationary;
  InputPoint position;
  constexpr bool operator==(const TouchPoint &) const = default;
};
struct TouchFrame {
  TouchFramePhase phase = TouchFramePhase::update;
  std::array<TouchPoint, kMaximumTouchPoints> points{};
  std::uint32_t count = 0;
  std::uint32_t modifiers = 0;
  constexpr bool operator==(const TouchFrame &) const = default;
};
struct FocusChanged {
  bool focused = false;
  constexpr bool operator==(const FocusChanged &) const = default;
};
struct Cancel {
  constexpr bool operator==(const Cancel &) const = default;
};

using InputPayload =
    std::variant<PointerMotion, PointerButton, Wheel, Key, TextCommit,
                 TouchFrame, FocusChanged, Cancel>;

struct InputEvent {
  SurfaceKey surface;
  std::uint64_t sequence = 0;
  InputPayload payload;
  bool operator==(const InputEvent &) const = default;
};

enum class InputValidation {
  accepted,
  stale_surface,
  not_active,
  not_focused,
  zero_sequence,
  replayed_sequence,
  coordinate_out_of_bounds,
  delta_out_of_bounds,
  invalid_code,
  invalid_transition,
  invalid_text,
  too_many_touch_points,
};

[[nodiscard]] InputValidation
validate_input_shape(const InputPayload &payload);
[[nodiscard]] InputValidation
validate_input(const InputEvent &event, const TrustedAllocation &allocation,
               bool active, bool focused);
// The worker-side mirror rechecks the host-authenticated global sequence and
// exact focus/button/contact transitions without deciding host hit testing.
class InputMirror {
public:
  [[nodiscard]] InputValidation accept(const InputEvent &event,
                                       const TrustedAllocation &allocation,
                                       bool active);
  void release(SurfaceKey surface) noexcept;
  [[nodiscard]] std::optional<SurfaceKey> focused_surface() const noexcept;
  [[nodiscard]] bool touch_active(SurfaceKey surface) const noexcept;

private:
  static constexpr std::size_t kMaximumPressedKeys = 32;
  struct PressedKey {
    std::uint32_t key = 0;
    std::uint32_t native_scan_code = 0;
  };
  struct SurfaceState {
    SurfaceKey surface;
    std::uint32_t buttons = 0;
    std::array<bool, kMaximumTouchPoints> contacts{};
    std::array<PressedKey, kMaximumPressedKeys> pressed_keys{};
    std::size_t pressed_key_count = 0;
    bool wheel_active = false;
  };

  [[nodiscard]] SurfaceState *state_for(SurfaceKey surface) noexcept;

  std::array<SurfaceState, plugin::wire::kMaximumPluginSurfaces> surfaces_{};
  std::size_t surface_count_ = 0;
  std::uint64_t last_sequence_ = 0;
  std::optional<SurfaceKey> focused_surface_;
};

} // namespace omarchy::plugin_runtime::surface
