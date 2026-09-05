#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

# #9721: a broken personal monitors/input module must not prevent hypr.bindings
# from loading. require_optional.safe pcall-wraps user overrides; hyprland.lua
# loads bindings first.

entry="$ROOT/config/hypr/hyprland.lua"
grep -F 'require_optional.safe("hypr.bindings")' "$entry" >/dev/null ||
  fail "hyprland.lua loads personal bindings through require_optional.safe"
grep -F 'require_optional.safe("hypr.monitors")' "$entry" >/dev/null ||
  fail "hyprland.lua loads monitors through require_optional.safe"
grep -F 'require_optional.safe("hypr.input")' "$entry" >/dev/null ||
  fail "hyprland.lua loads input through require_optional.safe"

# Bindings must appear before monitors so a monitors failure cannot strand the
# session without Super shortcuts even if safe() were bypassed.
bindings_line=$(grep -n 'require_optional.safe("hypr.bindings")' "$entry" | head -n1 | cut -d: -f1)
monitors_line=$(grep -n 'require_optional.safe("hypr.monitors")' "$entry" | head -n1 | cut -d: -f1)
(( bindings_line < monitors_line )) ||
  fail "hyprland.lua loads bindings before monitors" "bindings=$bindings_line monitors=$monitors_line"
pass "hyprland.lua loads personal overrides safely with bindings first"

if grep -E '^\s*require\("hypr\.(monitors|input|bindings|looknfeel|autostart)"\)' "$entry" >/dev/null; then
  fail "hyprland.lua must not bare-require personal override modules"
fi
pass "hyprland.lua does not bare-require personal override modules"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/config/hypr"

# Broken monitors module: syntax/runtime error on load.
cat >"$test_tmp/config/hypr/monitors.lua" <<'LUA'
error("broken monitors fixture")
LUA

# Bindings module records that it ran.
cat >"$test_tmp/config/hypr/bindings.lua" <<LUA
local f = assert(io.open("$test_tmp/bindings-loaded", "w"))
f:write("yes\n")
f:close()
LUA

# Empty optional peers so searchpath finds them without erroring.
: >"$test_tmp/config/hypr/input.lua"
: >"$test_tmp/config/hypr/looknfeel.lua"
: >"$test_tmp/config/hypr/autostart.lua"

HOME="$test_tmp" XDG_CONFIG_HOME="$test_tmp/config" OMARCHY_PATH="$ROOT" \
  lua <<'LUA' >"$test_tmp/lua.out" 2>"$test_tmp/lua.err"
package.path = os.getenv("XDG_CONFIG_HOME") .. "/?.lua;"
  .. os.getenv("XDG_CONFIG_HOME") .. "/?/init.lua;"
  .. os.getenv("OMARCHY_PATH") .. "/?.lua;"
  .. os.getenv("OMARCHY_PATH") .. "/?/init.lua;"
  .. package.path

-- Stub the heavy defaults package so we only exercise the personal require path.
package.preload["default.hypr.omarchy"] = function() end
package.preload["default.hypr.toggles"] = function() end
package.preload["default.hypr.bootstrap"] = function() end

-- bootstrap is dofile()'d from the absolute path; provide a no-op file load
-- by intercepting dofile for the bootstrap path only.
local real_dofile = dofile
function dofile(path)
  if type(path) == "string" and path:find("bootstrap%.lua") then
    return
  end
  return real_dofile(path)
end

local ok, err = pcall(dofile, os.getenv("OMARCHY_PATH") .. "/config/hypr/hyprland.lua")
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end
LUA

[[ -f $test_tmp/bindings-loaded ]] ||
  fail "bindings still load when monitors.lua errors" "$(cat "$test_tmp/lua.err"; cat "$test_tmp/lua.out")"
grep -F 'Failed to load hypr.monitors' "$test_tmp/lua.out" >/dev/null ||
  grep -F 'Failed to load hypr.monitors' "$test_tmp/lua.err" >/dev/null ||
  fail "safe_require reports the failed monitors module" "$(cat "$test_tmp/lua.out"; cat "$test_tmp/lua.err")"
pass "broken hypr.monitors does not prevent hypr.bindings from loading"

# require_optional.safe itself: missing module is a no-op; present broken module logs.
HOME="$test_tmp" OMARCHY_PATH="$ROOT" lua <<'LUA' >"$test_tmp/safe.out" 2>"$test_tmp/safe.err"
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path
local require_optional = require("default.hypr.require_optional")
require_optional.safe("definitely.missing.module")
package.path = os.getenv("HOME") .. "/config/?.lua;" .. package.path
require_optional.safe("hypr.monitors")
LUA
grep -F 'Failed to load hypr.monitors' "$test_tmp/safe.out" >/dev/null ||
  grep -F 'Failed to load hypr.monitors' "$test_tmp/safe.err" >/dev/null ||
  fail "require_optional.safe logs module errors" "$(cat "$test_tmp/safe.out"; cat "$test_tmp/safe.err")"
pass "require_optional.safe logs errors and ignores missing modules"
