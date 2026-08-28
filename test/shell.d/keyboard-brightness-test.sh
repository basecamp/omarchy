#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# omarchy-brightness-keyboard discovers its device straight from /sys rather than
# through a hw-* helper, so there is no mock to isolate that lookup. Skip every
# assertion on machines that have no keyboard backlight at all (e.g. a bare
# desktop CI box); on machines that do, brightnessctl is mocked, so nothing real
# is ever written.
device=""
for candidate in /sys/class/leds/*kbd_backlight*; do
  if [[ -e $candidate ]]; then
    device=$(basename "$candidate")
    break
  fi
done

if [[ -z $device ]]; then
  pass "no keyboard backlight device; skipping omarchy-brightness-keyboard"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
call_log="$test_tmp/calls"
mkdir -p "$mock_bin"

cat >"$mock_bin/brightnessctl" <<'SH'
#!/bin/bash
printf 'brightnessctl %s\n' "$*" >>"$CALL_LOG"
current=${KBD_CURRENT:-20}
max=${KBD_MAX:-200}
if [[ $* == *" -m"* ]]; then
  printf 'kbd_backlight,leds,%d,%d%%,%d\n' "$current" "$((current * 100 / max))" "$max"
elif [[ $* == *" max" ]]; then
  printf '%d\n' "$max"
elif [[ $* == *" get" ]]; then
  printf '%d\n' "$current"
fi
SH

cat >"$mock_bin/omarchy-osd" <<'SH'
#!/bin/bash
printf 'omarchy-osd %s\n' "$*" >>"$CALL_LOG"
SH

chmod +x "$mock_bin"/*

run_keyboard() {
  CALL_LOG="$call_log" KBD_CURRENT="${KBD_CURRENT:-20}" KBD_MAX="${KBD_MAX:-200}" \
    PATH="$mock_bin:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-brightness-keyboard" "$@"
}

brightness=$(run_keyboard get)
[[ $brightness == "10" ]] || fail "keyboard get reports the current percent" "actual: $brightness"
grep -F 'brightnessctl -d kbd_backlight -m' "$call_log" >/dev/null ||
  fail "keyboard get queries brightnessctl -m"
pass "keyboard get reports the current percent"

run_keyboard --no-osd 50%
grep -F 'brightnessctl -d kbd_backlight set 100' "$call_log" >/dev/null ||
  fail "keyboard absolute percent converts to the hardware range"
pass "keyboard absolute percent converts to the hardware range"

osd_count=$(grep -c '^omarchy-osd ' "$call_log" || true)
run_keyboard 75%
grep -F 'brightnessctl -d kbd_backlight set 150' "$call_log" >/dev/null ||
  fail "keyboard absolute percent sets the scaled value"
(( $(grep -c '^omarchy-osd ' "$call_log") == osd_count + 1 )) ||
  fail "keyboard absolute percent summons the OSD"
grep -F 'omarchy-osd -i keyboard -p 75' "$call_log" >/dev/null ||
  fail "keyboard OSD reports the new percent"
pass "keyboard absolute percent summons the keyboard OSD"

osd_count=$(grep -c '^omarchy-osd ' "$call_log" || true)
run_keyboard --no-osd up
(( $(grep -c '^omarchy-osd ' "$call_log") == osd_count )) ||
  fail "keyboard --no-osd suppresses the OSD"
grep -F 'brightnessctl -d kbd_backlight set 40' "$call_log" >/dev/null ||
  fail "keyboard up steps by 10% of the range"
pass "keyboard up steps by 10% of the range"

KBD_CURRENT=5 run_keyboard --no-osd down
grep -F 'brightnessctl -d kbd_backlight set 0' "$call_log" >/dev/null ||
  fail "keyboard down clamps at zero"
pass "keyboard down clamps at zero"

KBD_CURRENT=190 run_keyboard --no-osd cycle
grep -F 'brightnessctl -d kbd_backlight set 0' "$call_log" >/dev/null ||
  fail "keyboard cycle wraps past maximum to zero"
pass "keyboard cycle wraps past maximum to zero"

run_keyboard off
grep -F 'brightnessctl -sd kbd_backlight set 0' "$call_log" >/dev/null ||
  fail "keyboard off saves and clears the backlight"
pass "keyboard off saves and clears the backlight"

run_keyboard restore
grep -F 'brightnessctl -rd kbd_backlight' "$call_log" >/dev/null ||
  fail "keyboard restore re-applies the saved backlight"
pass "keyboard restore re-applies the saved backlight"

KBD_MAX=3 KBD_CURRENT=1 run_keyboard --no-osd up
grep -F 'brightnessctl -d kbd_backlight set 2' "$call_log" >/dev/null ||
  fail "keyboards with few levels fall back to a one-percent step"
pass "keyboards with few levels fall back to a one-percent step"

if PATH="$mock_bin:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-brightness-keyboard" junk >/dev/null 2>&1; then
  fail "keyboard rejects a bare word as the direction"
fi
pass "keyboard rejects a bare word as the direction"