#include "test.hpp"

#include "omarchy/plugin_runtime/surface/surface_state.hpp"

using namespace omarchy::plugin_runtime::surface;

int main() {
  const auto allocation =
      make_allocation({.id = 4, .generation = 1}, 20, 10, 20, 10, 1, 1, 4096);
  require(allocation.has_value(), "fixture allocation failed");
  auto state = SurfaceState::create(*allocation);
  require(state.has_value(), "surface state construction failed");
  auto inconsistent = *allocation;
  ++inconsistent.stride;
  require(!SurfaceState::create(inconsistent),
          "inconsistent surface allocation accepted");
  require(!state->accepts_frame(allocation->surface),
          "allocated surface accepted a frame");
  require(state->apply(SurfaceTransition::activate), "activation failed");
  require(state->accepts_frame(allocation->surface),
          "active surface rejected a frame");
  require(!state->accepts_frame({.id = 4, .generation = 2}),
          "stale generation accepted");
  require(!state->accepts_input(allocation->surface, false),
          "unfocused input accepted");
  require(state->apply(SurfaceTransition::suspend), "suspend failed");
  require(!state->accepts_frame(allocation->surface),
          "suspended surface accepted a frame");
  require(state->apply(SurfaceTransition::resume), "resume failed");
  require(state->apply(SurfaceTransition::begin_destroy),
          "destroy start failed");
  require(!state->apply(SurfaceTransition::resume),
          "destroying surface resumed");
  require(state->apply(SurfaceTransition::finish_destroy),
          "destroy finish failed");
  require(!state->apply(SurfaceTransition::activate),
          "destroyed surface reactivated");
}
