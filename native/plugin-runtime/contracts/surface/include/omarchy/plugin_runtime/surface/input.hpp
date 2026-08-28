#pragma once

#include "omarchy/plugin_runtime/surface/shared_layout.hpp"

#include <cstdint>
#include <optional>

namespace omarchy::plugin_runtime::surface {

inline constexpr std::uint32_t kQ16FractionBits = 16;
inline constexpr std::uint32_t kMaximumTouchPoints = 10;

enum class InputKind { pointer_motion, pointer_button, scroll, key, touch };
enum class ButtonState : std::uint32_t { pressed = 1, released = 2 };

struct InputEvent {
  SurfaceKey surface;
  std::uint64_t sequence;
  InputKind kind;
  std::uint32_t x_q16;
  std::uint32_t y_q16;
  std::int32_t delta_x_q16;
  std::int32_t delta_y_q16;
  std::uint32_t code;
  std::uint32_t state;
  std::uint32_t active_touch_points;
};

struct FocusEvent {
  SurfaceKey surface;
  std::uint64_t sequence;
  bool focused;
};

enum class InputValidation {
  accepted,
  invalid_kind,
  stale_surface,
  not_active,
  not_focused,
  zero_sequence,
  replayed_sequence,
  coordinate_out_of_bounds,
  delta_out_of_bounds,
  invalid_code,
  too_many_touch_points,
};

[[nodiscard]] InputValidation
validate_input(const InputEvent &event, const TrustedAllocation &allocation,
               bool active, bool focused);

class InputGate {
public:
  [[nodiscard]] static std::optional<InputGate>
  create(const TrustedAllocation &allocation);
  [[nodiscard]] InputValidation accept(const InputEvent &event, bool active,
                                       bool focused);

private:
  explicit InputGate(TrustedAllocation allocation);

  TrustedAllocation allocation_;
  std::uint64_t last_sequence_ = 0;
};

class FocusGate {
public:
  [[nodiscard]] static std::optional<FocusGate>
  create(const TrustedAllocation &allocation);
  [[nodiscard]] InputValidation accept(const FocusEvent &event, bool active);

private:
  explicit FocusGate(TrustedAllocation allocation);

  TrustedAllocation allocation_;
  std::uint64_t last_sequence_ = 0;
};

} // namespace omarchy::plugin_runtime::surface
