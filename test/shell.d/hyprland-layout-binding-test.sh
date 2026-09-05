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
local dsp = proxy()

dsp.layout = function(message)
  return "layout:" .. message
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

local binding = assert(bindings["SUPER + J"], "SUPER + J binding is missing")
assert(binding.description == "Toggle window split / consume or expel", "SUPER + J description changed")
assert(type(binding.dispatcher) == "function", "SUPER + J dispatcher is not layout-aware")

local function assert_dispatch(regular_layout, special_layout, expected)
  workspace = regular_layout and { tiled_layout = regular_layout } or nil
  special_workspace = special_layout and { tiled_layout = special_layout } or nil

  local count = #dispatched
  binding.dispatcher()

  if expected then
    assert(#dispatched == count + 1, "expected a dispatcher for " .. (special_layout or regular_layout))
    assert(dispatched[#dispatched] == expected, "dispatched the wrong layout action")
  else
    assert(#dispatched == count, "unexpectedly dispatched for an unsupported workspace")
  end
end

assert_dispatch("dwindle", nil, "layout:togglesplit")
assert_dispatch("scrolling", nil, "layout:consume_or_expel prev")
assert_dispatch("dwindle", "scrolling", "layout:consume_or_expel prev")
assert_dispatch("scrolling", "dwindle", "layout:togglesplit")
assert_dispatch("master", nil, nil)
assert_dispatch(nil, nil, nil)
LUA
); then
  fail "layout-aware binding assertions failed" "$output"
fi

[[ -z $output ]] || fail "layout-aware binding produces no output" "$output"
pass "Super+J dispatches the native action for Dwindle and Scrolling layouts"
