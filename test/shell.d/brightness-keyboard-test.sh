#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin" "$test_tmp/leds/dell::kbd_backlight"
calls="$test_tmp/calls"

cat >"$test_tmp/bin/brightnessctl" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$BRIGHTNESS_CALLS"

if [[ $* == *" get" ]]; then
  printf '%s\n' "$CURRENT_BRIGHTNESS"
fi
SH

cat >"$test_tmp/bin/omarchy-osd" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$test_tmp/bin/brightnessctl" "$test_tmp/bin/omarchy-osd"

run_keyboard() {
  CURRENT_BRIGHTNESS="$1" BRIGHTNESS_CALLS="$calls" \
    OMARCHY_LEDS_PATH="$test_tmp/leds" PATH="$test_tmp/bin:$PATH" \
    "$ROOT/bin/omarchy-brightness-keyboard" "${@:2}"
}

: >"$calls"
run_keyboard 2 off
grep -Fqx -- '-d dell::kbd_backlight get' "$calls" ||
  fail "keyboard off reads the current brightness"
grep -Fqx -- '-sd dell::kbd_backlight set 0' "$calls" ||
  fail "keyboard off saves a lit backlight before turning it off"
pass "keyboard off preserves a lit backlight for restore"

: >"$calls"
run_keyboard 0 off
grep -Fqx -- '-d dell::kbd_backlight get' "$calls" ||
  fail "keyboard off checks a timed-out backlight"
if grep -Fq -- '-sd dell::kbd_backlight set 0' "$calls"; then
  fail "keyboard off replaces the saved level after a hardware timeout"
fi
pass "keyboard off keeps the saved level after a hardware timeout"

: >"$calls"
run_keyboard 0 restore
grep -Fqx -- '-rd dell::kbd_backlight' "$calls" ||
  fail "keyboard restore delegates to brightnessctl restore"
pass "keyboard restore reapplies the saved level"
