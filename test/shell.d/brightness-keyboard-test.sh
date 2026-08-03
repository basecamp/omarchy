#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

stub_bin="$TMPDIR/bin"
mkdir -p "$stub_bin"

# Emulate a keyboard backlight device. The max and current values are injected
# per case; every `set` writes the requested raw level to SET_LOG.
cat >"$stub_bin/brightnessctl" <<'STUB'
#!/bin/bash
if [[ $* == *" max" ]]; then
  printf '%s\n' "${KBD_MAX:-102}"
elif [[ $* == *" get" ]]; then
  printf '%s\n' "${KBD_CURRENT:-0}"
elif [[ $* == *" set"* ]]; then
  printf '%s\n' "${*: -1}" >>"${SET_LOG:?}"
fi
exit 0
STUB

cat >"$stub_bin/omarchy-osd" <<'STUB'
#!/bin/bash
while [[ $# -gt 0 ]]; do
  if [[ $1 == "-p" ]]; then printf '%s\n' "$2" >>"${OSD_LOG:?}"; fi
  shift
done
exit 0
STUB

chmod +x "$stub_bin"/*

# A fixture leds class so device detection succeeds without real hardware.
leds="$TMPDIR/leds"
mkdir -p "$leds/input::kbd_backlight"

set_log="$TMPDIR/set.log"
osd_log="$TMPDIR/osd.log"

run_kbd() {
  : >"$set_log"
  : >"$osd_log"
  KBD_MAX="$max" KBD_CURRENT="$current" SET_LOG="$set_log" OSD_LOG="$osd_log" \
    OMARCHY_LEDS_CLASS="$leds" PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-brightness-keyboard" "$@" >/dev/null ||
    fail "brightness-keyboard $* exits clean"
}

last_set() { tail -n 1 "$set_log"; }
last_osd() { tail -n 1 "$osd_log"; }

# A laptop with 102 raw levels (e.g. a MacBook) used to climb 0,9,19,29,... on
# the way up but 100,90,80,...,1 on the way down. Both directions must now walk
# the same fixed rungs.
max=102

current=0 run_kbd up
[[ $(last_set) == "10" && $(last_osd) == "10" ]] ||
  fail "up from off lands on the first rung" "set=$(last_set) osd=$(last_osd)"
pass "up from off lands on the first rung"

current=10 run_kbd up
[[ $(last_set) == "20" && $(last_osd) == "20" ]] ||
  fail "up climbs one fixed rung" "set=$(last_set) osd=$(last_osd)"
pass "up climbs one fixed rung"

current=92 run_kbd up
[[ $(last_set) == "102" && $(last_osd) == "100" ]] ||
  fail "up reaches full brightness at the top rung" "set=$(last_set) osd=$(last_osd)"
pass "up reaches full brightness at the top rung"

current=102 run_kbd down
[[ $(last_set) == "92" && $(last_osd) == "90" ]] ||
  fail "down from full lands on the rung below" "set=$(last_set) osd=$(last_osd)"
pass "down from full lands on the rung below"

current=92 run_kbd down
[[ $(last_set) == "82" && $(last_osd) == "80" ]] ||
  fail "down descends the same rungs as up" "set=$(last_set) osd=$(last_osd)"
pass "down descends the same rungs as up"

current=10 run_kbd down
[[ $(last_set) == "0" && $(last_osd) == "0" ]] ||
  fail "down reaches off at the bottom rung" "set=$(last_set) osd=$(last_osd)"
pass "down reaches off at the bottom rung"

# Up and down are inverses: a step up followed by a step down returns to the
# starting level.
current=51 run_kbd up
up_level=$(last_set)
current=$up_level run_kbd down
[[ $(last_set) == "51" ]] ||
  fail "up then down returns to the starting level" "up=$up_level down=$(last_set)"
pass "up then down returns to the starting level"

# Cycle wraps from full back to off, and from off up to the first rung.
current=102 run_kbd cycle
[[ $(last_set) == "0" && $(last_osd) == "0" ]] ||
  fail "cycle wraps from full to off" "set=$(last_set) osd=$(last_osd)"
pass "cycle wraps from full to off"

current=0 run_kbd cycle
[[ $(last_set) == "10" && $(last_osd) == "10" ]] ||
  fail "cycle advances from off to the first rung" "set=$(last_set) osd=$(last_osd)"
pass "cycle advances from off to the first rung"

# A coarse keyboard with only 3 levels falls back to one step per level instead
# of rounding everything away.
max=3

current=0 run_kbd up
[[ $(last_set) == "1" && $(last_osd) == "33" ]] ||
  fail "coarse keyboard steps one level at a time" "set=$(last_set) osd=$(last_osd)"
pass "coarse keyboard steps one level at a time"

current=3 run_kbd down
[[ $(last_set) == "2" && $(last_osd) == "66" ]] ||
  fail "coarse keyboard descends one level at a time" "set=$(last_set) osd=$(last_osd)"
pass "coarse keyboard descends one level at a time"
