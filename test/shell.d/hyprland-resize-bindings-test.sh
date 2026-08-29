#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

OMARCHY_PATH="$ROOT" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local function proxy()
  return setmetatable({}, {
    __index = function(self, key)
      local value = proxy()
      rawset(self, key, value)
      return value
    end,
    __call = function()
      return {}
    end,
  })
end

local bindings = {}
local dispatched = {}
local workspace = { tiled_layout = "scrolling" }
local special_workspace
local configured_direction

local window_dispatchers = proxy()
window_dispatchers.resize = function(args)
  return { kind = "window", args = args }
end

local dispatchers = proxy()
dispatchers.window = window_dispatchers
dispatchers.layout = function(message)
  return { kind = "layout", message = message }
end

hl = {
  dsp = dispatchers,
  bind = function() end,
  dispatch = function(dispatcher)
    table.insert(dispatched, dispatcher)
  end,
  get_active_workspace = function()
    return workspace
  end,
  get_active_special_workspace = function()
    return special_workspace
  end,
  get_config = function(key)
    if key == "scrolling.direction" then
      return configured_direction
    end
  end,
}

o = {
  bind = function(keys, _, dispatcher)
    bindings[keys] = dispatcher
  end,
}

require("default.hypr.bindings.tiling")

local cases = {
  { "SUPER + code:20", -100, "colresize -0.05" },
  { "SUPER + code:21", 100, "colresize +0.05" },
  { "SUPER + ALT + code:20", -25, "colresize -0.0125" },
  { "SUPER + ALT + code:21", 25, "colresize +0.0125" },
  { "SUPER + CTRL + code:20", -300, "colresize -0.15" },
  { "SUPER + CTRL + code:21", 300, "colresize +0.15" },
}

local function run_binding(keys)
  dispatched = {}
  assert(type(bindings[keys]) == "function", "missing layout-aware binding: " .. keys)
  bindings[keys]()
  assert(#dispatched == 1, "binding did not dispatch exactly once: " .. keys)
  return dispatched[1]
end

for _, case in ipairs(cases) do
  local dispatcher = run_binding(case[1])
  assert(dispatcher.kind == "layout", "scrolling resize did not use a layout message: " .. case[1])
  assert(dispatcher.message == case[3], "unexpected scrolling resize delta: " .. case[1])
end

workspace.tiled_layout = "dwindle"
for _, case in ipairs(cases) do
  local dispatcher = run_binding(case[1])
  assert(dispatcher.kind == "window", "dwindle resize did not use the window dispatcher: " .. case[1])
  assert(dispatcher.args.x == case[2], "unexpected dwindle resize delta: " .. case[1])
  assert(dispatcher.args.y == 0 and dispatcher.args.relative == true, "dwindle resize lost its existing options: " .. case[1])
end

workspace.tiled_layout = "scrolling"
special_workspace = { tiled_layout = "dwindle" }
assert(run_binding("SUPER + code:21").kind == "window", "active special workspace layout takes precedence")

special_workspace = nil
configured_direction = "left"
assert(run_binding("SUPER + code:21").kind == "layout", "leftward scrolling still uses colresize")

configured_direction = "up"
assert(run_binding("SUPER + code:21").kind == "window", "upward scrolling keeps window.resize")

configured_direction = "down"
assert(run_binding("SUPER + code:21").kind == "window", "downward scrolling keeps window.resize")

configured_direction = "right"
workspace.layout_opts = { direction = "down" }
assert(run_binding("SUPER + code:21").kind == "window", "workspace direction override takes precedence")

workspace.layout_opts = { direction = "left" }
configured_direction = "up"
assert(run_binding("SUPER + code:21").kind == "layout", "horizontal workspace override uses colresize")

workspace = nil
special_workspace = nil
dispatched = {}
bindings["SUPER + code:21"]()
assert(#dispatched == 0, "resize dispatches without an active workspace")
LUA

pass "horizontal resize bindings follow the active workspace layout"
