#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
eval_out="$test_tmp/hyprctl-eval"
home_dir="$test_tmp/home"
monitor_lua="$home_dir/.config/hypr/monitors.lua"

mkdir -p "$stub_bin" "$home_dir/.config/hypr"

# 5120x1440 offers four rates; the 3840x1080 modes belong to another
# resolution and must not show up in the list.
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "monitors" && $2 == "-j" ]]; then
  cat <<'JSON'
[
  {
    "name": "DP-1",
    "focused": true,
    "scale": 1.25,
    "x": 0,
    "y": 0,
    "width": 5120,
    "height": 1440,
    "refreshRate": 143.979,
    "availableModes": [
      "5120x1440@143.98Hz",
      "5120x1440@85.00Hz",
      "3840x1080@119.97Hz",
      "5120x1440@100.00Hz",
      "5120x1440@71.98Hz"
    ]
  }
]
JSON
elif [[ $1 == "eval" ]]; then
  printf '%s\n' "$2" >"$OMARCHY_TEST_HYPRCTL_EVAL_OUT"
else
  exit 1
fi
SH
chmod +x "$stub_bin/hyprctl"

write_default_config() {
  cat >"$monitor_lua" <<'LUA'
local omarchy_monitor_scale = "auto"
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })
LUA
}

write_explicit_config() {
  cat >"$monitor_lua" <<'LUA'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.25 })
hl.monitor({ output = "DP-1", mode = "5120x1440@72", position = "0x0", scale = 1.25, transform = 0 })
LUA
}

run_refresh() {
  HOME="$home_dir" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_HYPRCTL_EVAL_OUT="$eval_out" \
    "$ROOT/bin/omarchy-hyprland-monitor-refresh" "$@"
}

rate=$(run_refresh)
[[ $rate == "144" ]] || fail "monitor refresh reports the rate the mode names" "actual: $rate"
pass "monitor refresh rounds the reported rate to the one the mode names"

rates=$(run_refresh --list | paste -sd' ')
[[ $rates == "144 100 85 72" ]] || fail "monitor refresh lists the rates of the current resolution" "actual: $rates"
pass "monitor refresh lists the rates of the current resolution, highest first"

# A rate belonging to another resolution is not on offer here.
write_default_config
if run_refresh 120 2>/dev/null; then
  fail "monitor refresh refuses a rate the current resolution has no mode for"
fi
if grep -F '120' "$monitor_lua" >/dev/null; then
  fail "monitor refresh leaves the config alone when it refuses a rate"
fi
pass "monitor refresh refuses a rate the current resolution has no mode for"

# The eval keeps the monitor where it is: the resolution is not changing, so
# there is nothing for "auto" to re-derive.
write_default_config
run_refresh 100
grep -Fx 'hl.monitor({ output = "DP-1", mode = "5120x1440@100", position = "0x0", scale = 1.25 })' "$eval_out" >/dev/null ||
  fail "monitor refresh applies the rate in place" "actual: $(cat "$eval_out")"
pass "monitor refresh applies the rate without moving the monitor"

# With only the catch-all in the file, the output gets a rule of its own. It
# inherits omarchy_monitor_scale so monitor scaling keeps reaching this output.
grep -Fx 'hl.monitor({ output = "DP-1", mode = "5120x1440@100", position = "auto", scale = omarchy_monitor_scale })' "$monitor_lua" >/dev/null ||
  fail "monitor refresh persists a rule for the output" "actual:"$'\n'"$(cat "$monitor_lua")"
grep -Fx 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })' "$monitor_lua" >/dev/null ||
  fail "monitor refresh leaves the catch-all in place"
pass "monitor refresh persists a rule that still follows the catch-all's scale"

# Setting a second rate rewrites that rule rather than stacking another one.
run_refresh 85
(( $(grep -c '^hl\.monitor({ output = "DP-1"' "$monitor_lua") == 1 )) ||
  fail "monitor refresh keeps one rule per output" "actual:"$'\n'"$(cat "$monitor_lua")"
grep -F 'mode = "5120x1440@85"' "$monitor_lua" >/dev/null || fail "monitor refresh rewrites the rate it already wrote"
pass "monitor refresh rewrites its own rule instead of stacking another"

# The commented example in the shipped config is not a rule to rewrite.
grep -Fx -e '-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })' "$monitor_lua" >/dev/null ||
  fail "monitor refresh leaves commented examples alone"
pass "monitor refresh leaves commented examples alone"

# A rule the user wrote keeps its position, scale and transform.
write_explicit_config
run_refresh 144
grep -Fx 'hl.monitor({ output = "DP-1", mode = "5120x1440@144", position = "0x0", scale = 1.25, transform = 0 })' "$monitor_lua" >/dev/null ||
  fail "monitor refresh rewrites only the mode of an existing rule" "actual:"$'\n'"$(cat "$monitor_lua")"
pass "monitor refresh rewrites only the mode of a rule the user wrote"
