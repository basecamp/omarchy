#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

# Load the tiling bindings through the real o.bind, grab the function bound to
# Super + Alt + F, and run it against stubbed compositor state. Each case prints
# the dispatcher it reached for and the argument it carried.
full_width_dispatches() {
  OMARCHY_PATH="$ROOT" lua <<'LUA'
local root = os.getenv("OMARCHY_PATH")

local dispatched = {}

-- hl.dsp.window.fullscreen({ ... }) and hl.dsp.layout("...") both record the
-- path they were reached through, so a dispatcher compares as a plain string.
local function dispatcher_proxy(path)
  return setmetatable({}, {
    __index = function(_, key)
      return dispatcher_proxy(path == "" and key or (path .. "." .. key))
    end,
    __call = function(_, argument)
      return { name = path, argument = argument }
    end,
  })
end

local active = {}

hl = {
  dsp = dispatcher_proxy(""),
  bind = function(keys, dispatcher, opts)
    if keys == "SUPER + ALT + F" then
      _G.full_width = dispatcher
    end
  end,
  dispatch = function(dispatcher)
    table.insert(dispatched, dispatcher)
  end,
  get_config = function(key)
    return active.config and active.config[key]
  end,
  get_active_window = function()
    return active.window
  end,
  get_active_workspace = function()
    return active.workspace
  end,
  get_active_special_workspace = function()
    return active.special_workspace
  end,
}

dofile(root .. "/default/hypr/helpers.lua")
dofile(root .. "/default/hypr/bindings/tiling.lua")

assert(type(_G.full_width) == "function", "Super + Alt + F binds a function")

local function scrolling_monitor(overrides)
  local monitor = { width = 1920, height = 1200, scale = 1.6, transform = 0 }
  for key, value in pairs(overrides or {}) do
    monitor[key] = value
  end
  return monitor
end

local function case(name, state)
  active = state
  dispatched = {}
  _G.full_width()

  assert(#dispatched == 1, name .. " dispatches exactly once")

  local dispatcher = dispatched[1]
  local argument = dispatcher.argument
  if type(argument) == "table" then
    argument = argument.mode
  end

  print(name .. "\t" .. dispatcher.name .. "\t" .. tostring(argument))
end

local scrolling = { tiled_layout = "scrolling" }
local dwindle = { tiled_layout = "dwindle" }
local config = { ["scrolling.column_width"] = 0.49 }

case("narrow-column", {
  workspace = scrolling,
  window = { floating = false, fullscreen = 0, size = { x = 564 }, monitor = scrolling_monitor() },
  config = config,
})

case("full-column", {
  workspace = scrolling,
  window = { floating = false, fullscreen = 0, size = { x = 1166 }, monitor = scrolling_monitor() },
  config = config,
})

case("unset-column-width", {
  workspace = scrolling,
  window = { floating = false, fullscreen = 0, size = { x = 1166 }, monitor = scrolling_monitor() },
  config = {},
})

-- Transform 1 turns the monitor on its side, so its height is the logical
-- width. Reading width here would call a full 1150 px column narrow.
case("rotated-monitor", {
  workspace = scrolling,
  window = {
    floating = false,
    fullscreen = 0,
    size = { x = 1150 },
    monitor = scrolling_monitor({ scale = 1, transform = 1 }),
  },
  config = config,
})

case("dwindle-workspace", {
  workspace = dwindle,
  window = { floating = false, fullscreen = 0, size = { x = 564 }, monitor = scrolling_monitor() },
  config = config,
})

case("floating-window", {
  workspace = scrolling,
  window = { floating = true, fullscreen = 0, size = { x = 564 }, monitor = scrolling_monitor() },
  config = config,
})

case("fullscreen-window", {
  workspace = scrolling,
  window = { floating = false, fullscreen = 2, size = { x = 564 }, monitor = scrolling_monitor() },
  config = config,
})

-- A special workspace has its own layout and wins over the one underneath it.
case("special-workspace", {
  workspace = dwindle,
  special_workspace = scrolling,
  window = { floating = false, fullscreen = 0, size = { x = 564 }, monitor = scrolling_monitor() },
  config = config,
})
LUA
}

dispatches=$(full_width_dispatches) || fail "Super + Alt + F runs against stubbed compositor state"

assert_dispatch() {
  local name="$1" expected="$2"
  local actual

  actual=$(awk -F'\t' -v name="$name" '$1 == name { print $2 "\t" $3 }' <<<"$dispatches")
  [[ $actual == "$expected" ]] ||
    fail "$name dispatches $(tr '\t' ' ' <<<"$expected")" "got: $(tr '\t' ' ' <<<"$actual")"
}

assert_dispatch narrow-column $'layout\tcolresize 1.0'
assert_dispatch full-column $'layout\tcolresize 0.49'
pass "full width toggles the column between the monitor and the configured width"

assert_dispatch unset-column-width $'layout\tcolresize 0.5'
pass "full width falls back to half a column when none is configured"

assert_dispatch rotated-monitor $'layout\tcolresize 0.49'
pass "full width measures a rotated monitor across its logical width"

assert_dispatch special-workspace $'layout\tcolresize 1.0'
pass "full width follows the layout of the active special workspace"

assert_dispatch dwindle-workspace $'window.fullscreen\tmaximized'
assert_dispatch floating-window $'window.fullscreen\tmaximized'
assert_dispatch fullscreen-window $'window.fullscreen\tmaximized'
pass "full width still maximizes outside a tiled scrolling column"
