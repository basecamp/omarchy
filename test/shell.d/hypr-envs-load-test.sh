#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

entry="$ROOT/config/hypr/hyprland.lua"
grep -F 'require_optional.module("hypr.envs")' "$entry" >/dev/null ||
  fail "hyprland.lua loads personal hypr.envs"
pass "hyprland.lua loads personal hypr.envs"

# Personal envs must come after package defaults (default.hypr.omarchy pulls
# default.hypr.envs) so user hl.env overrides win.
defaults_line=$(grep -n 'require("default.hypr.omarchy")' "$entry" | head -n1 | cut -d: -f1)
envs_line=$(grep -n 'require_optional.module("hypr.envs")' "$entry" | head -n1 | cut -d: -f1)
(( defaults_line < envs_line )) ||
  fail "personal hypr.envs loads after package defaults" "defaults=$defaults_line envs=$envs_line"
pass "personal hypr.envs loads after package defaults"

[[ -f $ROOT/config/hypr/envs.lua ]] || fail "shipped template includes config/hypr/envs.lua"
pass "shipped template includes config/hypr/envs.lua"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/config/hypr"

cat >"$test_tmp/config/hypr/envs.lua" <<'LUA'
_G.OMARCHY_TEST_ENVS_LOADED = true
hl.env("OMARCHY_TEST_LIBVA", "iHD")
LUA

HOME="$test_tmp" XDG_CONFIG_HOME="$test_tmp/config" OMARCHY_PATH="$ROOT" \
  lua <<'LUA' >"$test_tmp/out" 2>"$test_tmp/err"
package.path = os.getenv("XDG_CONFIG_HOME") .. "/?.lua;"
  .. os.getenv("OMARCHY_PATH") .. "/?.lua;"
  .. package.path

local envs = {}
hl = {
  env = function(k, v) envs[k] = v end,
  config = function() end,
  dsp = setmetatable({}, { __index = function() return function() end end }),
  bind = function() end,
  monitor = function() end,
  window_rule = function() end,
  workspace_rule = function() end,
  layer_rule = function() end,
  gesture = function() end,
  animation = function() end,
  curve = function() end,
}

package.preload["default.hypr.omarchy"] = function() end
package.preload["default.hypr.toggles"] = function() end
for _, name in ipairs({
  "hypr.monitors", "hypr.input", "hypr.bindings", "hypr.looknfeel", "hypr.autostart",
}) do
  package.preload[name] = function() end
end

local real_dofile = dofile
function dofile(path)
  if type(path) == "string" and path:find("bootstrap%.lua") then return end
  return real_dofile(path)
end

assert(pcall(dofile, os.getenv("OMARCHY_PATH") .. "/config/hypr/hyprland.lua"))
assert(_G.OMARCHY_TEST_ENVS_LOADED == true, "hypr.envs module did not run")
assert(envs.OMARCHY_TEST_LIBVA == "iHD", "hypr.envs did not apply hl.env")
print("loaded")
LUA

grep -Fx loaded "$test_tmp/out" >/dev/null ||
  fail "hyprland.lua evaluates personal hypr.envs" "$(cat "$test_tmp/err"; cat "$test_tmp/out")"
pass "hyprland.lua evaluates personal hypr.envs"

migration="$ROOT/migrations/1788439000.sh"
[[ -f $migration ]] || fail "migration 1788439000.sh exists"
mkdir -p "$test_tmp/home/.config/hypr"
cat >"$test_tmp/home/.config/hypr/hyprland.lua" <<'LUA'
require("default.hypr.omarchy")
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")
require("default.hypr.toggles")
LUA

HOME="$test_tmp/home" bash -euo pipefail "$migration"
grep -F 'require_optional.module("hypr.envs")' "$test_tmp/home/.config/hypr/hyprland.lua" >/dev/null ||
  fail "migration inserts hypr.envs require" "$(cat "$test_tmp/home/.config/hypr/hyprland.lua")"
pass "migration inserts hypr.envs require into older hyprland.lua"

HOME="$test_tmp/home" bash -euo pipefail "$migration"
count=$(grep -c 'require_optional.module("hypr.envs")' "$test_tmp/home/.config/hypr/hyprland.lua" || true)
(( count == 1 )) || fail "migration is idempotent" "count=$count"
pass "migration is idempotent"
