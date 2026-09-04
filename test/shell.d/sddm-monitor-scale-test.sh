#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home_dir="$test_tmp/home"
scale_file="$test_tmp/omarchy-monitor-scale"
monitor_lua="$home_dir/.config/hypr/monitors.lua"
sudoers_file="$ROOT/etc/sudoers.d/omarchy-sddm-monitor-scale"
helper="$ROOT/bin/omarchy-sddm-set-monitor-scale"
greeter="$ROOT/default/sddm/hyprland.lua"
migration="$ROOT/migrations/1786961462.sh"

mkdir -p "$home_dir/.config/hypr"

load_greeter() {
  local scale_path="$1"

  OMARCHY_SDDM_MONITOR_SCALE="$scale_path" ROOT="$ROOT" lua <<'LUA'
hl = {
  config = function() end,
  monitor = function(spec)
    local scale = spec.scale
    if type(scale) == "number" then
      io.write(string.format("number %g\n", scale))
    else
      io.write(string.format("string %s\n", tostring(scale)))
    end
  end,
}
dofile(os.getenv("ROOT") .. "/default/sddm/hyprland.lua")
LUA
}

run_helper() {
  HOME="$home_dir" \
    OMARCHY_SDDM_MONITOR_SCALE="$scale_file" \
    "$helper" "$@"
}

write_monitor_config() {
  cat >"$monitor_lua" <<LUA
local omarchy_gdk_scale = 2
local omarchy_monitor_scale = $1
LUA
}

grep -F 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })' "$greeter" >/dev/null ||
  fail "greeter config applies a catch-all monitor scale"
pass "greeter config applies a catch-all monitor scale"

result=$(load_greeter "$test_tmp/missing-scale")
[[ $result == "string auto" ]] || fail "greeter defaults to auto without a drop-in" "actual: $result"
pass "greeter defaults to auto without a drop-in"

printf '1.6\n' >"$scale_file"
result=$(load_greeter "$scale_file")
[[ $result == "number 1.6" ]] || fail "greeter uses a numeric drop-in scale" "actual: $result"
pass "greeter uses a numeric drop-in scale"

printf 'auto\n' >"$scale_file"
result=$(load_greeter "$scale_file")
[[ $result == "string auto" ]] || fail "greeter uses an auto drop-in scale" "actual: $result"
pass "greeter uses an auto drop-in scale"

printf 'nope\n' >"$scale_file"
result=$(load_greeter "$scale_file")
[[ $result == "string auto" ]] || fail "greeter ignores a garbage drop-in" "actual: $result"
pass "greeter ignores a garbage drop-in"

printf '0.5\n' >"$scale_file"
result=$(load_greeter "$scale_file")
[[ $result == "string auto" ]] || fail "greeter ignores a drop-in below 1x" "actual: $result"
pass "greeter ignores a drop-in below 1x"

printf '5\n' >"$scale_file"
result=$(load_greeter "$scale_file")
[[ $result == "string auto" ]] || fail "greeter ignores a drop-in above 4x" "actual: $result"
pass "greeter ignores a drop-in above 4x"

rm -f "$scale_file"
run_helper 1.25
grep -Fx '1.25' "$scale_file" >/dev/null || fail "helper writes an explicit scale" "$(cat "$scale_file" 2>/dev/null || true)"
pass "helper writes an explicit scale"

write_monitor_config 1.6
rm -f "$scale_file"
run_helper
grep -Fx '1.6' "$scale_file" >/dev/null || fail "helper reads omarchy_monitor_scale from monitors.lua" "$(cat "$scale_file" 2>/dev/null || true)"
pass "helper reads omarchy_monitor_scale from monitors.lua"

write_monitor_config '"auto"'
rm -f "$scale_file"
run_helper
grep -Fx 'auto' "$scale_file" >/dev/null || fail "helper writes quoted auto from monitors.lua" "$(cat "$scale_file" 2>/dev/null || true)"
pass "helper writes quoted auto from monitors.lua"

cat >"$monitor_lua" <<'LUA'
local omarchy_monitor_scale = 1.25 -- HiDPI panel
LUA
rm -f "$scale_file"
run_helper
grep -Fx '1.25' "$scale_file" >/dev/null || fail "helper ignores a trailing comment on omarchy_monitor_scale" "$(cat "$scale_file" 2>/dev/null || true)"
pass "helper ignores a trailing comment on omarchy_monitor_scale"

cat >"$monitor_lua" <<'LUA'
local omarchy_monitor_scale = 3 / 2
LUA
rm -f "$scale_file"
run_helper
[[ ! -e $scale_file ]] || fail "helper leaves expressions unresolved" "$(cat "$scale_file")"
pass "helper leaves expressions unresolved"

rm -f "$scale_file"
status=0
run_helper 0.5 || status=$?
(( status != 0 )) || fail "helper rejects an explicit scale below 1x"
[[ ! -e $scale_file ]] || fail "helper does not write an invalid explicit scale"
pass "helper rejects an explicit scale below 1x"

grep -F '%wheel ALL=(root) NOPASSWD: /usr/bin/mkdir -p /etc/sddm' "$sudoers_file" >/dev/null ||
  fail "sddm scale sudoers allows passwordless mkdir"
grep -F '%wheel ALL=(root) NOPASSWD: /usr/bin/tee /etc/sddm/omarchy-monitor-scale' "$sudoers_file" >/dev/null ||
  fail "sddm scale sudoers allows passwordless tee"
if command -v visudo >/dev/null; then
  visudo -cf "$sudoers_file" >/dev/null || fail "sddm scale sudoers is valid"
fi
pass "sddm scale sudoers allows passwordless writes"

grep -F 'sudo mkdir -p "$dest_dir"' "$helper" >/dev/null ||
  fail "helper uses the passwordless mkdir sudoers rule"
grep -F 'sudo tee "$SCALE_FILE"' "$helper" >/dev/null ||
  fail "helper uses the passwordless tee sudoers rule"
! grep -F 'pkexec' "$helper" >/dev/null || fail "helper does not wrap the write in pkexec"
pass "helper uses the passwordless sudoers rules"

grep -F 'omarchy-sddm-set-monitor-scale || true' "$ROOT/bin/omarchy-system-logout" >/dev/null ||
  fail "logout persists the greeter monitor scale"
pass "logout persists the greeter monitor scale"

write_monitor_config 1.6
rm -f "$scale_file"
HOME="$home_dir" \
  PATH="$ROOT/bin:$PATH" \
  OMARCHY_SDDM_MONITOR_SCALE="$scale_file" \
  bash -euo pipefail "$migration" >/dev/null
grep -Fx '1.6' "$scale_file" >/dev/null || fail "migration seeds the greeter scale from monitors.lua" "$(cat "$scale_file" 2>/dev/null || true)"
pass "migration seeds the greeter scale from monitors.lua"
