#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

if ! output=$(OMARCHY_PATH="$ROOT" lua 2>&1 <<'LUA'
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
local workspace
local special_workspace
local window
local dsp = proxy()

dsp.layout = function(message)
  return "layout:" .. message
end

dsp.window.resize = function(options)
  if not options then
    return { kind = "resize", interactive = true }
  end

  return {
    kind = "resize",
    x = options.x,
    y = options.y,
    relative = options.relative,
  }
end

local function describe(dispatcher)
  if type(dispatcher) == "table" and dispatcher.kind == "resize" then
    if dispatcher.interactive then
      return "resize:interactive"
    end

    return string.format("resize:%s:%s:%s", dispatcher.x, dispatcher.y, tostring(dispatcher.relative))
  end

  return dispatcher
end

hl = setmetatable({
  dsp = dsp,
  bind = function(keys, dispatcher, opts)
    bindings[keys] = {
      dispatcher = dispatcher,
      description = opts and opts.description,
    }
  end,
  dispatch = function(dispatcher)
    table.insert(dispatched, describe(dispatcher))
  end,
  get_active_workspace = function()
    return workspace
  end,
  get_active_special_workspace = function()
    return special_workspace
  end,
  get_active_window = function()
    return window
  end,
}, {
  __index = function()
    return function() end
  end,
})

require("default.hypr.helpers")
require("default.hypr.bindings.tiling")

local horizontal_bindings = {
  {
    keys = "SUPER + code:20",
    description = "Shrink window horizontally",
    column = "layout:colresize -0.05",
    window = "resize:-100:0:true",
  },
  {
    keys = "SUPER + code:21",
    description = "Grow window horizontally",
    column = "layout:colresize +0.05",
    window = "resize:100:0:true",
  },
  {
    keys = "SUPER + ALT + code:20",
    description = "Shrink window horizontally a little",
    column = "layout:colresize -0.0125",
    window = "resize:-25:0:true",
  },
  {
    keys = "SUPER + ALT + code:21",
    description = "Grow window horizontally a little",
    column = "layout:colresize +0.0125",
    window = "resize:25:0:true",
  },
  {
    keys = "SUPER + CTRL + code:20",
    description = "Shrink window horizontally a lot",
    column = "layout:colresize -0.15",
    window = "resize:-300:0:true",
  },
  {
    keys = "SUPER + CTRL + code:21",
    description = "Grow window horizontally a lot",
    column = "layout:colresize +0.15",
    window = "resize:300:0:true",
  },
}

local function assert_dispatch(binding, regular_layout, special_layout, active_window, expected)
  workspace = regular_layout and { tiled_layout = regular_layout } or nil
  special_workspace = special_layout and { tiled_layout = special_layout } or nil
  window = active_window

  local count = #dispatched
  binding.dispatcher()

  assert(#dispatched == count + 1, "resize binding did not dispatch")
  assert(dispatched[#dispatched] == expected, "resize binding dispatched " .. tostring(dispatched[#dispatched]) .. " instead of " .. expected)
end

for _, expected in ipairs(horizontal_bindings) do
  local binding = assert(bindings[expected.keys], expected.keys .. " binding is missing")
  assert(binding.description == expected.description, expected.keys .. " description changed")
  assert(type(binding.dispatcher) == "function", expected.keys .. " is not layout-aware")

  local tiled = { floating = false, fullscreen = 0 }
  assert_dispatch(binding, "scrolling", nil, tiled, expected.column)
  assert_dispatch(binding, "dwindle", nil, tiled, expected.window)
  assert_dispatch(binding, "master", nil, tiled, expected.window)
  assert_dispatch(binding, "monocle", nil, tiled, expected.window)
  assert_dispatch(binding, "dwindle", "scrolling", tiled, expected.column)
  assert_dispatch(binding, "scrolling", "dwindle", tiled, expected.window)
  assert_dispatch(binding, "scrolling", nil, { floating = true, fullscreen = 0 }, expected.window)
  assert_dispatch(binding, "scrolling", nil, { floating = false, fullscreen = 1 }, expected.window)
  assert_dispatch(binding, "scrolling", nil, nil, expected.window)
  assert_dispatch(binding, nil, nil, tiled, expected.window)
end

local vertical_bindings = {
  ["SUPER + SHIFT + code:20"] = "resize:0:-100:true",
  ["SUPER + SHIFT + code:21"] = "resize:0:100:true",
  ["SUPER + SHIFT + ALT + code:20"] = "resize:0:-25:true",
  ["SUPER + SHIFT + ALT + code:21"] = "resize:0:25:true",
  ["SUPER + CTRL + SHIFT + code:20"] = "resize:0:-300:true",
  ["SUPER + CTRL + SHIFT + code:21"] = "resize:0:300:true",
}

for keys, expected in pairs(vertical_bindings) do
  local binding = assert(bindings[keys], keys .. " binding is missing")
  assert(type(binding.dispatcher) ~= "function", keys .. " unexpectedly became layout-aware")
  assert(describe(binding.dispatcher) == expected, keys .. " vertical resize changed to " .. tostring(describe(binding.dispatcher)))
end
LUA
); then
  fail "layout-aware resize binding assertions failed" "$output"
fi

[[ -z $output ]] || fail "layout-aware resize bindings produce no output" "$output"
pass "horizontal resize bindings use native scrolling columns with safe fallbacks"

grep -Fq '| `Super + Minus` | Shrink window horizontally |' "$ROOT/manual/07-hotkeys.md" || fail "manual documents horizontal shrinking on Super + Minus"
grep -Fq '| `Super + Equal` | Grow window horizontally |' "$ROOT/manual/07-hotkeys.md" || fail "manual documents horizontal growth on Super + Equal"
pass "manual documents the horizontal resize directions"
