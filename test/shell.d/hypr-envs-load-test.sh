#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

defaults="$ROOT/default/hypr/envs.lua"
entry="$ROOT/config/hypr/hyprland.lua"

grep -F 'require_optional.module("hypr.envs")' "$defaults" >/dev/null ||
  fail "default.hypr.envs loads personal hypr.envs"
pass "default.hypr.envs loads personal hypr.envs"

nvidia_line=$(grep -n 'require("default.hypr.nvidia")' "$defaults" | head -n1 | cut -d: -f1)
envs_line=$(grep -n 'require_optional.module("hypr.envs")' "$defaults" | head -n1 | cut -d: -f1)
(( nvidia_line < envs_line )) ||
  fail "personal hypr.envs loads after nvidia.lua" "nvidia=$nvidia_line envs=$envs_line"
pass "personal hypr.envs loads after nvidia.lua"

grep -F 'require("hypr.envs")' "$entry" >/dev/null &&
  fail "hyprland.lua must not bare-require hypr.envs (missing file aborts the config)"
pass "hyprland.lua does not bare-require hypr.envs"

[[ -f $ROOT/config/hypr/envs.lua ]] || fail "shipped template includes config/hypr/envs.lua"
pass "shipped template includes config/hypr/envs.lua"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/config/hypr" "$test_tmp/omarchy/default/hypr"

cp "$ROOT/default/hypr/require_optional.lua" "$test_tmp/omarchy/default/hypr/require_optional.lua"
cp "$ROOT/default/hypr/envs.lua" "$test_tmp/omarchy/default/hypr/envs.lua"

cat >"$test_tmp/omarchy/default/hypr/paths.lua" <<'LUA'
return { home = "/tmp", omarchy_path = "/tmp/omarchy" }
LUA

cat >"$test_tmp/omarchy/default/hypr/nvidia.lua" <<'LUA'
_G.OMARCHY_TEST_NVIDIA_LOADED = true
hl.env("LIBVA_DRIVER_NAME", "nvidia")
LUA

run_envs() {
  local config_home=$1
  HOME="$test_tmp" XDG_CONFIG_HOME="$config_home" OMARCHY_PATH="$test_tmp/omarchy" \
    lua <<'LUA' >"$test_tmp/out" 2>"$test_tmp/err"
package.path = os.getenv("XDG_CONFIG_HOME") .. "/?.lua;"
  .. os.getenv("OMARCHY_PATH") .. "/?.lua;"
  .. package.path

local envs = {}
hl = {
  env = function(k, v) envs[k] = v end,
  config = function() end,
}

local ok, err = pcall(require, "default.hypr.envs")
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end

print("nvidia=" .. tostring(_G.OMARCHY_TEST_NVIDIA_LOADED))
print("personal=" .. tostring(_G.OMARCHY_TEST_ENVS_LOADED))
print("libva=" .. tostring(envs.LIBVA_DRIVER_NAME))
LUA
}

# Absent personal file: package defaults still load.
mkdir -p "$test_tmp/empty-config"
run_envs "$test_tmp/empty-config"
grep -Fx 'nvidia=true' "$test_tmp/out" >/dev/null ||
  fail "absent hypr.envs still loads nvidia.lua" "$(cat "$test_tmp/err"; cat "$test_tmp/out")"
grep -Fx 'personal=nil' "$test_tmp/out" >/dev/null ||
  fail "absent hypr.envs is skipped" "$(cat "$test_tmp/err"; cat "$test_tmp/out")"
grep -Fx 'libva=nvidia' "$test_tmp/out" >/dev/null ||
  fail "absent hypr.envs leaves package LIBVA" "$(cat "$test_tmp/err"; cat "$test_tmp/out")"
pass "absent hypr.envs does not abort default.hypr.envs"

cat >"$test_tmp/config/hypr/envs.lua" <<'LUA'
_G.OMARCHY_TEST_ENVS_LOADED = true
hl.env("LIBVA_DRIVER_NAME", "iHD")
LUA

run_envs "$test_tmp/config"
grep -Fx 'nvidia=true' "$test_tmp/out" >/dev/null ||
  fail "present hypr.envs still loads nvidia.lua" "$(cat "$test_tmp/err"; cat "$test_tmp/out")"
grep -Fx 'personal=true' "$test_tmp/out" >/dev/null ||
  fail "present hypr.envs module ran" "$(cat "$test_tmp/err"; cat "$test_tmp/out")"
grep -Fx 'libva=iHD' "$test_tmp/out" >/dev/null ||
  fail "present hypr.envs overrides LIBVA" "$(cat "$test_tmp/err"; cat "$test_tmp/out")"
pass "present hypr.envs overrides package hl.env"
