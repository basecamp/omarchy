#include "test.hpp"

#include "omarchy/plugin_runtime/surface/input.hpp"

#include <limits>

using namespace omarchy::plugin_runtime::surface;

int main() {
  const auto first = make_allocation({.id = 8, .generation = 2}, 100, 50,
                                     200, 100, 2, 1, 4096);
  const auto second = make_allocation({.id = 9, .generation = 2}, 100, 50,
                                      200, 100, 2, 1, 4096);
  require(first && second, "fixture allocation failed");
  InputMirror mirror;

  InputEvent motion{
      .surface = first->surface,
      .sequence = 1,
      .payload = PointerMotion{.position = {.x_q16 = 50U << 16,
                                             .y_q16 = 25U << 16}}};
  require(mirror.accept(motion, *first, true) == InputValidation::accepted,
          "bounded pointer motion rejected");
  require(mirror.accept(motion, *first, true) ==
              InputValidation::replayed_sequence,
          "replayed global sequence accepted");
  std::get<PointerMotion>(motion.payload).position.x_q16 = 100U << 16;
  motion.sequence = 2;
  require(validate_input(motion, *first, true, false) ==
              InputValidation::coordinate_out_of_bounds,
          "edge-outside coordinate accepted");

  InputEvent focus{.surface = first->surface,
                   .sequence = 2,
                   .payload = FocusChanged{.focused = true}};
  require(mirror.accept(focus, *first, true) == InputValidation::accepted &&
              mirror.focused_surface() == first->surface,
          "first focus transition rejected");
  focus.surface = second->surface;
  focus.sequence = 3;
  require(mirror.accept(focus, *second, true) ==
              InputValidation::invalid_transition,
          "new focus was accepted before old focus cleared");
  focus.surface = first->surface;
  focus.sequence = 3;
  focus.payload = FocusChanged{.focused = false};
  require(mirror.accept(focus, *first, true) == InputValidation::accepted,
          "old focus clear rejected");
  focus.surface = second->surface;
  focus.sequence = 4;
  focus.payload = FocusChanged{.focused = true};
  require(mirror.accept(focus, *second, true) == InputValidation::accepted,
          "ordered focus switch rejected");

  InputEvent key{.surface = first->surface,
                 .sequence = 5,
                 .payload = Key{.key = 30,
                                .state = ButtonState::pressed,
                                .text = "x"}};
  require(validate_input(key, *first, true, false) ==
              InputValidation::not_focused,
          "unfocused key accepted");
  key.surface = second->surface;
  require(mirror.accept(key, *second, true) == InputValidation::accepted,
          "focused key/text rejected");
  std::get<Key>(key.payload).text = std::string("\xc0\x80", 2);
  key.sequence = 6;
  require(mirror.accept(key, *second, true) == InputValidation::invalid_text,
          "non-canonical UTF-8 accepted");

  InputEvent press{
      .surface = first->surface,
      .sequence = 6,
      .payload = PointerButton{.position = {},
                               .button = 2,
                               .state = ButtonState::pressed,
                               .buttons = 2}};
  require(mirror.accept(press, *first, true) == InputValidation::accepted,
          "exact pointer press transition rejected");
  press.sequence = 7;
  require(mirror.accept(press, *first, true) ==
              InputValidation::invalid_transition,
          "duplicate button press accepted");
  press.payload = PointerButton{.position = {},
                                .button = 2,
                                .state = ButtonState::released,
                                .buttons = 0};
  require(mirror.accept(press, *first, true) == InputValidation::accepted,
          "exact pointer release transition rejected");
  press.sequence = 8;
  press.payload = PointerButton{.position = {},
                                .button = 4,
                                .state = ButtonState::pressed,
                                .buttons = 4};
  require(mirror.accept(press, *first, true) == InputValidation::accepted,
          "Qt middle-button bitmask was not preserved");
  press.sequence = 9;
  press.payload = PointerButton{.position = {},
                                .button = 8,
                                .state = ButtonState::pressed,
                                .buttons = 8};
  require(mirror.accept(press, *first, true) ==
              InputValidation::invalid_transition,
          "mismatched aggregate button mask was accepted");
  press.payload = PointerButton{.position = {},
                                .button = 4,
                                .state = ButtonState::released,
                                .buttons = 0};
  require(mirror.accept(press, *first, true) == InputValidation::accepted,
          "Qt middle-button release was rejected");

  TouchFrame begin{.phase = TouchFramePhase::begin,
                   .points = {{{.id = 3,
                                .state = TouchPointState::pressed,
                                .position = {1U << 16, 1U << 16}}}},
                   .count = 1};
  InputEvent touch{.surface = first->surface,
                   .sequence = 10,
                   .payload = begin};
  require(mirror.accept(touch, *first, true) == InputValidation::accepted,
          "atomic touch begin rejected");
  auto duplicate = begin;
  duplicate.phase = TouchFramePhase::update;
  duplicate.count = 2;
  duplicate.points[1] = duplicate.points[0];
  touch.sequence = 11;
  touch.payload = duplicate;
  require(mirror.accept(touch, *first, true) == InputValidation::invalid_code,
          "duplicate touch IDs accepted");
  begin.phase = TouchFramePhase::end;
  begin.points[0].state = TouchPointState::released;
  touch.payload = begin;
  require(mirror.accept(touch, *first, true) == InputValidation::accepted,
          "atomic touch end rejected");

  {
    InputMirror complete_frame_mirror;
    InputEvent frame{
        .surface = first->surface,
        .sequence = 1,
        .payload = TouchFrame{
            .phase = TouchFramePhase::begin,
            .points = {{{.id = 1,
                         .state = TouchPointState::pressed,
                         .position = {1U << 16, 1U << 16}}}},
            .count = 1}};
    require(complete_frame_mirror.accept(frame, *first, true) ==
                InputValidation::accepted,
            "complete-frame fixture begin rejected");
    frame.sequence = 2;
    frame.payload = TouchFrame{
        .phase = TouchFramePhase::update,
        .points = {{{.id = 2,
                     .state = TouchPointState::pressed,
                     .position = {2U << 16, 2U << 16}}}},
        .count = 1};
    require(complete_frame_mirror.accept(frame, *first, true) ==
                InputValidation::invalid_transition,
            "touch frame omitted an already-active contact");
    frame.sequence = 3;
    frame.payload = TouchFrame{
        .phase = TouchFramePhase::update,
        .points = {{{.id = 1,
                     .state = TouchPointState::stationary,
                     .position = {1U << 16, 1U << 16}},
                    {.id = 2,
                     .state = TouchPointState::pressed,
                     .position = {2U << 16, 2U << 16}}}},
        .count = 2};
    require(complete_frame_mirror.accept(frame, *first, true) ==
                InputValidation::accepted,
            "complete touch update with a new contact rejected");
    frame.sequence = 4;
    frame.payload = TouchFrame{
        .phase = TouchFramePhase::end,
        .points = {{{.id = 1,
                     .state = TouchPointState::released,
                     .position = {1U << 16, 1U << 16}},
                    {.id = 2,
                     .state = TouchPointState::released,
                     .position = {2U << 16, 2U << 16}}}},
        .count = 2};
    require(complete_frame_mirror.accept(frame, *first, true) ==
                InputValidation::accepted,
            "complete two-contact touch end rejected");
  }

  InputEvent cancel{.surface = second->surface,
                    .sequence = 12,
                    .payload = Cancel{}};
  require(mirror.accept(cancel, *second, false) == InputValidation::accepted &&
              !mirror.focused_surface(),
          "cancel did not clear inactive focused surface");
  cancel.sequence = 13;
  cancel.surface.generation--;
  require(mirror.accept(cancel, *second, false) ==
              InputValidation::stale_surface,
          "stale cancel generation accepted");

  {
    InputMirror wheel_mirror;
    InputEvent wheel{
        .surface = first->surface,
        .sequence = 1,
        .payload = Wheel{.position = {}, .phase = WheelPhase::discrete}};
    require(wheel_mirror.accept(wheel, *first, true) ==
                InputValidation::accepted,
            "discrete wheel event rejected");
    wheel.sequence = 2;
    std::get<Wheel>(wheel.payload).phase = WheelPhase::update;
    require(wheel_mirror.accept(wheel, *first, true) ==
                InputValidation::invalid_transition,
            "wheel update without begin accepted");
    wheel.sequence = 3;
    std::get<Wheel>(wheel.payload).phase = WheelPhase::begin;
    require(wheel_mirror.accept(wheel, *first, true) ==
                InputValidation::accepted,
            "wheel begin rejected");
    wheel.sequence = 4;
    std::get<Wheel>(wheel.payload).phase = WheelPhase::discrete;
    require(wheel_mirror.accept(wheel, *first, true) ==
                InputValidation::invalid_transition,
            "discrete wheel event accepted during an active gesture");
    wheel.sequence = 5;
    std::get<Wheel>(wheel.payload).phase = WheelPhase::update;
    require(wheel_mirror.accept(wheel, *first, true) ==
                InputValidation::accepted,
            "active wheel update rejected");
    wheel.sequence = 6;
    std::get<Wheel>(wheel.payload).phase = WheelPhase::momentum;
    require(wheel_mirror.accept(wheel, *first, true) ==
                InputValidation::accepted,
            "wheel momentum rejected");
    wheel.sequence = 7;
    std::get<Wheel>(wheel.payload).phase = WheelPhase::end;
    require(wheel_mirror.accept(wheel, *first, true) ==
                InputValidation::accepted,
            "wheel end rejected");
    wheel.sequence = 8;
    require(wheel_mirror.accept(wheel, *first, true) ==
                InputValidation::invalid_transition,
            "duplicate wheel end accepted");
  }

  {
    InputMirror key_mirror;
    InputEvent key_focus{.surface = first->surface,
                         .sequence = 1,
                         .payload = FocusChanged{.focused = true}};
    require(key_mirror.accept(key_focus, *first, true) ==
                InputValidation::accepted,
            "key fixture focus rejected");
    InputEvent physical_key{
        .surface = first->surface,
        .sequence = 2,
        .payload = Key{.key = 0x01000020,
                       .native_scan_code = 42,
                       .state = ButtonState::pressed,
                       .text = {}}};
    require(key_mirror.accept(physical_key, *first, true) ==
                InputValidation::accepted,
            "left physical modifier press rejected");
    physical_key.sequence = 3;
    std::get<Key>(physical_key.payload).native_scan_code = 54;
    require(key_mirror.accept(physical_key, *first, true) ==
                InputValidation::accepted,
            "right physical modifier was conflated with the left key");
    physical_key.sequence = 4;
    std::get<Key>(physical_key.payload).native_scan_code = 42;
    require(key_mirror.accept(physical_key, *first, true) ==
                InputValidation::invalid_transition,
            "duplicate non-repeat key press accepted");
    physical_key.sequence = 5;
    std::get<Key>(physical_key.payload).auto_repeat = true;
    require(key_mirror.accept(physical_key, *first, true) ==
                InputValidation::accepted,
            "repeat press for an active key rejected");
    physical_key.sequence = 6;
    std::get<Key>(physical_key.payload).state = ButtonState::released;
    require(key_mirror.accept(physical_key, *first, true) ==
                InputValidation::invalid_transition,
            "auto-repeat release changed physical key state");
    physical_key.sequence = 7;
    std::get<Key>(physical_key.payload).auto_repeat = false;
    require(key_mirror.accept(physical_key, *first, true) ==
                InputValidation::accepted,
            "left physical modifier release rejected");
    physical_key.sequence = 8;
    std::get<Key>(physical_key.payload).native_scan_code = 54;
    require(key_mirror.accept(physical_key, *first, true) ==
                InputValidation::accepted,
            "right physical modifier release rejected");
    physical_key.sequence = 9;
    require(key_mirror.accept(physical_key, *first, true) ==
                InputValidation::invalid_transition,
            "key release without an active press accepted");
  }

  {
    InputMirror cancel_mirror;
    InputEvent active_touch{.surface = first->surface,
                            .sequence = 1,
                            .payload = TouchFrame{
                                .phase = TouchFramePhase::begin,
                                .points = {{{.id = 2,
                                             .state =
                                                 TouchPointState::pressed,
                                             .position = {}}}},
                                .count = 1}};
    require(cancel_mirror.accept(active_touch, *first, true) ==
                InputValidation::accepted,
            "active-cancel fixture touch begin rejected");
    InputEvent active_cancel{.surface = first->surface,
                             .sequence = 2,
                             .payload = Cancel{}};
    require(cancel_mirror.accept(active_cancel, *first, false) ==
                InputValidation::accepted,
            "cancel did not clear an active touch");
    active_touch.sequence = 3;
    auto &after_cancel = std::get<TouchFrame>(active_touch.payload);
    after_cancel.phase = TouchFramePhase::update;
    after_cancel.points[0].state = TouchPointState::updated;
    require(cancel_mirror.accept(active_touch, *first, true) ==
                InputValidation::invalid_transition,
            "touch continuation survived cancel");
    active_touch.sequence = 4;
    after_cancel.phase = TouchFramePhase::begin;
    after_cancel.points[0].state = TouchPointState::pressed;
    require(cancel_mirror.accept(active_touch, *first, true) ==
                InputValidation::accepted,
            "fresh touch begin after cancel rejected");
  }

  {
    InputMirror focus_loss_mirror;
    InputEvent focus_loss{.surface = first->surface,
                          .sequence = 1,
                          .payload = FocusChanged{.focused = true}};
    require(focus_loss_mirror.accept(focus_loss, *first, true) ==
                InputValidation::accepted,
            "focus-loss fixture focus rejected");
    InputEvent held_button{
        .surface = first->surface,
        .sequence = 2,
        .payload = PointerButton{.position = {},
                                 .button = 1,
                                 .state = ButtonState::pressed,
                                 .buttons = 1}};
    require(focus_loss_mirror.accept(held_button, *first, true) ==
                InputValidation::accepted,
            "focus-loss fixture button press rejected");
    InputEvent held_key{.surface = first->surface,
                        .sequence = 3,
                        .payload = Key{.key = 65,
                                       .native_scan_code = 30,
                                       .state = ButtonState::pressed,
                                       .text = {}}};
    require(focus_loss_mirror.accept(held_key, *first, true) ==
                InputValidation::accepted,
            "focus-loss fixture key press rejected");
    InputEvent held_touch{.surface = first->surface,
                          .sequence = 4,
                          .payload = TouchFrame{
                              .phase = TouchFramePhase::begin,
                              .points = {{{.id = 1,
                                           .state = TouchPointState::pressed,
                                           .position = {}}}},
                              .count = 1}};
    require(focus_loss_mirror.accept(held_touch, *first, true) ==
                InputValidation::accepted,
            "focus-loss fixture touch begin rejected");
    InputEvent held_wheel{
        .surface = first->surface,
        .sequence = 5,
        .payload = Wheel{.position = {},
                         .phase = WheelPhase::begin,
                         .buttons = 1}};
    require(focus_loss_mirror.accept(held_wheel, *first, true) ==
                InputValidation::accepted,
            "focus-loss fixture wheel begin rejected");
    focus_loss.sequence = 6;
    focus_loss.payload = FocusChanged{.focused = false};
    require(focus_loss_mirror.accept(focus_loss, *first, true) ==
                InputValidation::accepted,
            "focus loss rejected");
    focus_loss.sequence = 7;
    focus_loss.payload = FocusChanged{.focused = true};
    require(focus_loss_mirror.accept(focus_loss, *first, true) ==
                InputValidation::accepted,
            "refocus after state teardown rejected");
    InputEvent cleared_motion{.surface = first->surface,
                              .sequence = 8,
                              .payload = PointerMotion{.position = {},
                                                       .buttons = 0}};
    require(focus_loss_mirror.accept(cleared_motion, *first, true) ==
                InputValidation::accepted,
            "button state survived focus loss");
    held_key.sequence = 9;
    std::get<Key>(held_key.payload).state = ButtonState::released;
    require(focus_loss_mirror.accept(held_key, *first, true) ==
                InputValidation::invalid_transition,
            "key state survived focus loss");
    held_touch.sequence = 10;
    auto &continued_touch = std::get<TouchFrame>(held_touch.payload);
    continued_touch.phase = TouchFramePhase::update;
    continued_touch.points[0].state = TouchPointState::updated;
    require(focus_loss_mirror.accept(held_touch, *first, true) ==
                InputValidation::invalid_transition,
            "touch state survived focus loss");
    held_wheel.sequence = 11;
    std::get<Wheel>(held_wheel.payload).phase = WheelPhase::end;
    std::get<Wheel>(held_wheel.payload).buttons = 0;
    require(focus_loss_mirror.accept(held_wheel, *first, true) ==
                InputValidation::invalid_transition,
            "wheel state survived focus loss");
  }

  {
    InputMirror capacity_mirror;
    for (std::uint64_t index = 0;
         index < omarchy::plugin::wire::kMaximumPluginSurfaces; ++index) {
      const auto allocation = make_allocation(
          {.id = 100 + index, .generation = 1}, 10, 10, 10, 10, 1, 1, 4096);
      require(allocation.has_value(), "capacity fixture allocation failed");
      const InputEvent event{.surface = allocation->surface,
                             .sequence = index + 1,
                             .payload = PointerMotion{}};
      require(capacity_mirror.accept(event, *allocation, true) ==
                  InputValidation::accepted,
              "mirror rejected a surface below its fixed capacity");
    }
    const auto excess = make_allocation(
        {.id = 100 + omarchy::plugin::wire::kMaximumPluginSurfaces,
         .generation = 1},
        10, 10, 10, 10, 1, 1, 4096);
    require(excess.has_value(), "excess-capacity fixture allocation failed");
    require(capacity_mirror.accept({.surface = excess->surface,
                                    .sequence =
                                        omarchy::plugin::wire::
                                                kMaximumPluginSurfaces +
                                            1,
                                    .payload = PointerMotion{}},
                                   *excess, true) ==
                InputValidation::invalid_transition,
            "mirror accepted a surface beyond its fixed capacity");
  }

  {
    InputMirror rollback_mirror;
    const auto focused = make_allocation({.id = 200, .generation = 1}, 10, 10,
                                         10, 10, 1, 1, 4096);
    require(focused.has_value(), "rollback focus allocation failed");
    require(rollback_mirror.accept({.surface = focused->surface,
                                    .sequence = 1,
                                    .payload = FocusChanged{.focused = true}},
                                   *focused, true) == InputValidation::accepted,
            "rollback fixture focus rejected");
    for (std::uint64_t index = 0; index < 20; ++index) {
      const auto rejected = make_allocation(
          {.id = 201 + index, .generation = 1}, 10, 10, 10, 10, 1, 1, 4096);
      require(rejected.has_value(), "rollback rejected allocation failed");
      require(rollback_mirror.accept(
                  {.surface = rejected->surface,
                   .sequence = index + 2,
                   .payload = FocusChanged{.focused = true}},
                  *rejected, true) == InputValidation::invalid_transition,
              "second focused surface was accepted");
    }
    require(rollback_mirror.accept(
                {.surface = focused->surface,
                 .sequence = 22,
                 .payload = FocusChanged{.focused = false}},
                *focused, true) == InputValidation::accepted,
            "rollback fixture focus clear rejected");
    const auto after_rejections = make_allocation(
        {.id = 250, .generation = 1}, 10, 10, 10, 10, 1, 1, 4096);
    require(after_rejections.has_value(), "post-rollback allocation failed");
    require(rollback_mirror.accept(
                {.surface = after_rejections->surface,
                 .sequence = 23,
                 .payload = PointerMotion{}},
                *after_rejections, true) == InputValidation::accepted,
            "rejected transitions consumed mirror capacity");
  }
}
