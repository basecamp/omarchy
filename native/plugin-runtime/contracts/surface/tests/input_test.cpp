#include "test.hpp"

#include "omarchy/plugin_runtime/surface/input.hpp"

#include <cstdint>
#include <limits>

using namespace omarchy::plugin_runtime::surface;

int main() {
  const auto allocation = make_allocation({.id = 8, .generation = 2}, 100, 50,
                                          200, 100, 2, 1, 4096);
  require(allocation.has_value(), "fixture allocation failed");
  auto gate = InputGate::create(*allocation);
  require(gate.has_value(), "input gate construction failed");
  InputEvent event{.surface = allocation->surface,
                   .sequence = 1,
                   .kind = InputKind::pointer_motion,
                   .x_q16 = 50U << 16,
                   .y_q16 = 25U << 16,
                   .delta_x_q16 = 1 << 16,
                   .delta_y_q16 = -(1 << 16),
                   .code = 0,
                   .state = 0,
                   .active_touch_points = 0};
  require(validate_input(event, *allocation, true, false) ==
              InputValidation::accepted,
          "bounded pointer motion rejected");
  require(gate->accept(event, true, false) == InputValidation::accepted,
          "first monotonic input rejected");
  require(gate->accept(event, true, false) ==
              InputValidation::replayed_sequence,
          "replayed input sequence accepted");
  event.sequence = 2;
  require(gate->accept(event, true, false) == InputValidation::accepted,
          "increasing input sequence rejected");
  event.kind = static_cast<InputKind>(99);
  require(validate_input(event, *allocation, true, true) ==
              InputValidation::invalid_kind,
          "unknown input kind accepted");
  event.kind = InputKind::pointer_motion;
  event.x_q16 = 100U << 16;
  require(validate_input(event, *allocation, true, false) ==
              InputValidation::coordinate_out_of_bounds,
          "edge-outside coordinate accepted");
  event.x_q16 = 0;
  event.delta_x_q16 = std::numeric_limits<std::int32_t>::min();
  require(validate_input(event, *allocation, true, false) ==
              InputValidation::delta_out_of_bounds,
          "overflowing negative delta accepted");
  event.delta_x_q16 = 0;
  event.kind = InputKind::key;
  event.y_q16 = 0;
  event.delta_y_q16 = 0;
  event.code = 30;
  event.state = static_cast<std::uint32_t>(ButtonState::pressed);
  require(validate_input(event, *allocation, true, false) ==
              InputValidation::not_focused,
          "unfocused key accepted");
  require(validate_input(event, *allocation, true, true) ==
              InputValidation::accepted,
          "focused bounded key rejected");
  event.kind = InputKind::touch;
  event.active_touch_points = 11;
  require(validate_input(event, *allocation, true, true) ==
              InputValidation::too_many_touch_points,
          "excess touch points accepted");
  event.surface.generation = 1;
  require(validate_input(event, *allocation, true, true) ==
              InputValidation::stale_surface,
          "stale input generation accepted");

  auto focus_gate = FocusGate::create(*allocation);
  require(focus_gate.has_value(), "focus gate construction failed");
  const FocusEvent focus{
      .surface = allocation->surface, .sequence = 1, .focused = true};
  require(focus_gate->accept(focus, true) == InputValidation::accepted,
          "first focus transition rejected");
  require(focus_gate->accept(focus, true) == InputValidation::replayed_sequence,
          "focus replay accepted");
}
