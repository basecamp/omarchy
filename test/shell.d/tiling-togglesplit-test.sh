#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tiling="$ROOT/default/hypr/bindings/tiling.lua"
[[ -f $tiling ]] || fail "tiling bindings are present"

# Must not bare-bind togglesplit — that errors on scrolling layouts (#9726).
if grep -E 'o\.bind\("SUPER \+ J".*hl\.dsp\.layout\("togglesplit"\)' "$tiling" >/dev/null; then
  fail "SUPER+J must not bare-dispatch togglesplit"
fi

grep -F 'get_active_workspace' "$tiling" >/dev/null ||
  fail "tiling guards dwindle-only binds on active workspace layout"
grep -F 'tiled_layout == "dwindle"' "$tiling" >/dev/null ||
  fail "tiling only dispatches togglesplit on dwindle"
grep -F 'layout("togglesplit")' "$tiling" >/dev/null ||
  fail "tiling still offers togglesplit on dwindle"
pass "SUPER+J togglesplit is guarded for dwindle-only layouts"

if grep -E 'o\.bind\("SUPER \+ P".*hl\.dsp\.window\.pseudo\(\)' "$tiling" >/dev/null; then
  fail "SUPER+P must not bare-dispatch window.pseudo"
fi
grep -F 'window.pseudo()' "$tiling" >/dev/null ||
  fail "tiling still offers pseudo on dwindle"
pass "SUPER+P pseudo is guarded for dwindle-only layouts"

require_command lua
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

HOME="$test_tmp" OMARCHY_PATH="$ROOT" lua <<'LUA' >"$test_tmp/out" 2>"$test_tmp/err"
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

local dispatched = { dwindle = 0, scrolling = 0 }
local current = "scrolling"
local guards = {}

hl = {
  bind = function(keys, dispatcher, opts)
    if keys == "SUPER + J" or keys == "SUPER + P" then
      guards[keys] = dispatcher
    end
  end,
  get_active_workspace = function()
    return { tiled_layout = current }
  end,
  dispatch = function(msg)
    dispatched[current] = (dispatched[current] or 0) + 1
  end,
  dsp = proxy(),
}

require("default.hypr.helpers")
dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bindings/tiling.lua")

assert(type(guards["SUPER + J"]) == "function", "SUPER + J binds a function")
assert(type(guards["SUPER + P"]) == "function", "SUPER + P binds a function")

for _, keys in ipairs({ "SUPER + J", "SUPER + P" }) do
  current = "scrolling"
  local before_s = dispatched.scrolling
  guards[keys]()
  assert(dispatched.scrolling == before_s, keys .. " must no-op on scrolling")

  current = "dwindle"
  local before_d = dispatched.dwindle
  guards[keys]()
  assert(dispatched.dwindle == before_d + 1, keys .. " must dispatch on dwindle")
end

print("ok")
LUA

grep -Fx ok "$test_tmp/out" >/dev/null ||
  fail "tiling guards no-op on scrolling and dispatch on dwindle" "$(cat "$test_tmp/err"; cat "$test_tmp/out")"
pass "tiling guards no-op on scrolling and dispatch on dwindle"
