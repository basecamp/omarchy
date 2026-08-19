#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home_dir="$test_tmp/home"
state_dir="$home_dir/.local/state/omarchy/toggles/hypr"
eval_log="$test_tmp/hyprctl-eval.log"

mkdir -p "$stub_bin" "$home_dir"

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "monitors" && $2 == "all" && $3 == "-j" ]]; then
  printf '[{"name":"eDP-1","focused":true,"transform":%s},{"name":"DP-2","focused":false,"transform":0}]' \
    "${OMARCHY_TEST_TRANSFORM:-0}"
elif [[ $1 == "devices" && $2 == "-j" ]]; then
  printf '{"touch":[{"name":"%s"}],"tablets":[]}' "${OMARCHY_TEST_TOUCH_DEVICE:-}"
elif [[ $1 == "eval" ]]; then
  printf '%s\n' "$2" >>"$OMARCHY_TEST_HYPRCTL_EVAL_LOG"
else
  exit 1
fi
SH

cat >"$stub_bin/omarchy-hyprland-monitor-focused" <<'SH'
#!/bin/bash
echo eDP-1
SH

cat >"$stub_bin/omarchy-hyprland-monitor-laptop" <<'SH'
#!/bin/bash
echo eDP-1
SH

chmod +x "$stub_bin"/*

orientation() {
  : >"$eval_log"

  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    OMARCHY_TEST_HYPRCTL_EVAL_LOG="$eval_log" \
    PATH="$stub_bin:$PATH" \
    bash "$ROOT/bin/omarchy-display-orientation" "$@"
}

assert_eval_contains() {
  local description="$1" expected="$2"

  grep -qF -- "$expected" "$eval_log" ||
    fail "$description" "expected in hyprctl eval log: $expected"$'\n'"actual:"$'\n'"$(cat "$eval_log")"
  pass "$description"
}

assert_eval_missing() {
  local description="$1" unexpected="$2"

  if grep -qF -- "$unexpected" "$eval_log"; then
    fail "$description" "unexpected in hyprctl eval log: $unexpected"
  fi
  pass "$description"
}

# ---- reading ----

[[ $(OMARCHY_TEST_TRANSFORM=0 orientation) == "normal" ]] ||
  fail "orientation names an unrotated display"
pass "orientation names an unrotated display"

[[ $(OMARCHY_TEST_TRANSFORM=3 orientation) == "270" ]] ||
  fail "orientation names a rotated display"
pass "orientation names a rotated display"

[[ $(OMARCHY_TEST_TRANSFORM=6 orientation) == "flipped-180" ]] ||
  fail "orientation names a flipped display"
pass "orientation names a flipped display"

# ---- setting ----

output=$(OMARCHY_TEST_TRANSFORM=0 orientation 90)
[[ $output == "90" ]] || fail "orientation echoes the rotation it applied" "actual: $output"
assert_eval_contains "orientation rotates the focused display" \
  'hl.monitor({ output = "eDP-1", transform = 1 })'
[[ -f $state_dir/monitor-eDP-1-transform.lua ]] ||
  fail "orientation persists the rotation for the next login"
grep -qF 'hl.monitor({ output = "eDP-1", transform = 1 })' "$state_dir/monitor-eDP-1-transform.lua" ||
  fail "orientation persists the rotation it applied"
pass "orientation persists the rotation for the next login"

# left/right are what wlr-randr and sway users already type.
OMARCHY_TEST_TRANSFORM=0 orientation right >/dev/null
assert_eval_contains "orientation accepts the sway rotation names" \
  'hl.monitor({ output = "eDP-1", transform = 3 })'

# Back to normal drops the override entirely, so monitors.lua speaks again.
OMARCHY_TEST_TRANSFORM=1 orientation normal >/dev/null
[[ ! -f $state_dir/monitor-eDP-1-transform.lua ]] ||
  fail "orientation drops the override when the display returns to normal"
pass "orientation drops the override when the display returns to normal"

# ---- cycling ----

[[ $(OMARCHY_TEST_TRANSFORM=0 orientation next) == "90" ]] || fail "orientation steps forward"
[[ $(OMARCHY_TEST_TRANSFORM=3 orientation next) == "normal" ]] || fail "orientation wraps forward"
[[ $(OMARCHY_TEST_TRANSFORM=0 orientation previous) == "270" ]] || fail "orientation wraps backward"
# A display parked on a flipped transform is off the cycle; stepping puts it back on it.
[[ $(OMARCHY_TEST_TRANSFORM=5 orientation next) == "90" ]] ||
  fail "orientation steps a flipped display back onto the cycle"
pass "orientation steps through the plain rotations"

# ---- touch input ----

OMARCHY_TEST_TRANSFORM=0 OMARCHY_TEST_TOUCH_DEVICE="elan-touchscreen" orientation 90 >/dev/null
assert_eval_contains "orientation rotates the built-in touchscreen with the panel" \
  'hl.device({ name = "elan-touchscreen", transform = 1, output = "eDP-1" })'
grep -qF 'hl.device({ name = "elan-touchscreen", transform = 1, output = "eDP-1" })' \
  "$state_dir/monitor-eDP-1-transform.lua" ||
  fail "orientation persists the touchscreen rotation"
pass "orientation persists the touchscreen rotation"

# An external monitor's touchscreen is a different device on a different output;
# rotating it along with the panel would rotate the wrong one.
OMARCHY_TEST_TRANSFORM=0 OMARCHY_TEST_TOUCH_DEVICE="elan-touchscreen" \
  orientation 90 --monitor DP-2 >/dev/null
assert_eval_missing "orientation leaves touch input alone on external displays" 'hl.device('

# ---- transient ----

rm -f "$state_dir/monitor-eDP-1-transform.lua"
OMARCHY_TEST_TRANSFORM=0 orientation 180 --transient >/dev/null
assert_eval_contains "orientation applies a transient rotation" \
  'hl.monitor({ output = "eDP-1", transform = 2 })'
[[ ! -f $state_dir/monitor-eDP-1-transform.lua ]] ||
  fail "orientation does not persist a transient rotation"
pass "orientation does not persist a transient rotation"

# ---- no-op ----

OMARCHY_TEST_TRANSFORM=2 orientation 180 >/dev/null
assert_eval_missing "orientation skips the modeset when nothing moves" 'hl.monitor('

# ---- rejection ----

if OMARCHY_TEST_TRANSFORM=0 orientation sideways >/dev/null 2>&1; then
  fail "orientation rejects an unknown rotation"
fi
pass "orientation rejects an unknown rotation"
