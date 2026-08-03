#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
call_log="$test_tmp/calls"
leds="$test_tmp/leds/tpacpi::kbd_backlight"
mkdir -p "$mock_bin" "$leds"

# brightnessctl keeps one save slot per device: blanking twice without an
# intervening restore would make `restore` restore darkness.
cat >"$mock_bin/brightnessctl" <<'SH'
#!/bin/bash
printf 'brightnessctl %s\n' "$*" >>"$CALL_LOG"
if [[ $* == *" get"* ]]; then printf '%s\n' "${KBD_BRIGHTNESS:-0}"; fi
exit 0
SH
chmod +x "$mock_bin/brightnessctl"

run_kbd() {
  CALL_LOG="$call_log" OMARCHY_LEDS_DIR="$test_tmp/leds" PATH="$mock_bin:$PATH" \
    "$ROOT/bin/omarchy-brightness-keyboard" "$@"
}

KBD_BRIGHTNESS=500 run_kbd off
grep -q -- '-sd' "$call_log" || fail "a lit keyboard backlight is saved before being turned off"

: >"$call_log"
KBD_BRIGHTNESS=0 run_kbd off
if grep -q -- '-sd' "$call_log"; then
  fail "an already-off keyboard backlight is not saved again"
fi
pass "keyboard backlight off is idempotent and never overwrites the saved state"
