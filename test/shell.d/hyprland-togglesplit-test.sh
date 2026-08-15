#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

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
local workspace = { tiled_layout = "scrolling" }
local special_workspace = nil
local dsp = proxy()
dsp.layout = function(message)
  return "layout:" .. message
end

hl = setmetatable({
  dsp = dsp,
  bind = function(keys, dispatcher)
    bindings[keys] = dispatcher
  end,
  dispatch = function(dispatcher)
    table.insert(dispatched, dispatcher)
  end,
  get_active_workspace = function()
    return workspace
  end,
  get_active_special_workspace = function()
    return special_workspace
  end,
}, {
  __index = function()
    return function() end
  end,
})

require("default.hypr.helpers")
require("default.hypr.bindings.tiling")

local toggle_split = bindings["SUPER + J"]
assert(type(toggle_split) == "function")

toggle_split()
assert(#dispatched == 0)

workspace = { tiled_layout = "dwindle" }
toggle_split()
assert(#dispatched == 1)
assert(dispatched[1] == "layout:togglesplit")

special_workspace = { tiled_layout = "scrolling" }
toggle_split()
assert(#dispatched == 1)

special_workspace = { tiled_layout = "dwindle" }
toggle_split()
assert(#dispatched == 2)
assert(dispatched[2] == "layout:togglesplit")
LUA
); then
  fail "toggle split binding assertions failed" "$output"
fi

[[ -z $output ]] || fail "toggle split binding produces no output" "$output"
pass "toggle split only dispatches in a Dwindle workspace"
