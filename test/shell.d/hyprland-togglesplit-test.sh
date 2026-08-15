#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

output=$(OMARCHY_PATH="$ROOT" lua <<'LUA'
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

hl = setmetatable({
  dsp = proxy(),
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

special_workspace = { tiled_layout = "scrolling" }
toggle_split()
assert(#dispatched == 1)
LUA
)

[[ -z $output ]] || fail "toggle split binding produces no output" "$output"
pass "toggle split only dispatches in a Dwindle workspace"
