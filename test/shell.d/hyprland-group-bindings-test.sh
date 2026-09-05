#!/bin/bash

set -euo pipefail

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
local active_window
local dispatched_index

hl = {
  dsp = proxy(),
  bind = function(keys, dispatcher)
    bindings[keys] = dispatcher
  end,
  dispatch = function(dispatcher)
    dispatched_index = dispatcher.index
  end,
  get_active_window = function()
    return active_window
  end,
}

hl.dsp.group.active = function(options)
  return { index = options.index }
end

require("default.hypr.helpers")
require("default.hypr.bindings.tiling")

active_window = { group = { size = 2 } }
bindings["SUPER + ALT + code:11"]()
assert(dispatched_index == 2, "an available group window is selected")

dispatched_index = nil
bindings["SUPER + ALT + code:12"]()
assert(dispatched_index == nil, "an out-of-range group window is ignored")

active_window = nil
bindings["SUPER + ALT + code:10"]()
assert(dispatched_index == nil, "a group window shortcut outside a group is ignored")
LUA

pass "group number bindings dispatch only available group windows"
