#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mock_bin="$tmp/bin"
call_log="$tmp/calls"
mkdir -p "$mock_bin" "$tmp/leds/chromeos::kbd_backlight"
: >"$call_log"

state="$tmp/brightness"
saved="$tmp/saved"
printf '40\n' >"$state"
# Distinct from the lit level so a no-op off that never saves still fails.
printf '7\n' >"$saved"

cat >"$mock_bin/brightnessctl" <<'SH'
#!/bin/bash
printf 'brightnessctl %s\n' "$*" >>"$CALL_LOG"

state="${BRIGHTNESS_STATE:?}"
saved="${BRIGHTNESS_SAVED:?}"

if [[ $1 == -d && $3 == get ]]; then
  cat "$state"
  exit 0
fi

if [[ $1 == -d && $3 == max ]]; then
  printf '100\n'
  exit 0
fi

if [[ $1 == -sd && $3 == set ]]; then
  cat "$state" >"$saved"
  printf '%s\n' "$4" >"$state"
  exit 0
fi

if [[ $1 == -d && $3 == set ]]; then
  printf '%s\n' "$4" >"$state"
  exit 0
fi

if [[ $1 == -rd ]]; then
  cat "$saved" >"$state"
  exit 0
fi

exit 1
SH
chmod +x "$mock_bin/brightnessctl"

run_kb() {
  CALL_LOG="$call_log" BRIGHTNESS_STATE="$state" BRIGHTNESS_SAVED="$saved" \
    OMARCHY_LEDS_PATH="$tmp/leds" PATH="$mock_bin:$ROOT/bin:$PATH" \
    omarchy-brightness-keyboard "$@"
}

[[ $(<"$saved") == 7 ]] || fail "saved sentinel starts distinct from lit level"

run_kb off
[[ $(<"$state") == 0 ]] || fail "first off blanks the backlight"
[[ $(<"$saved") == 40 ]] || fail "first off saves the prior level"
pass "first off saves the lit level"

run_kb off
[[ $(<"$state") == 0 ]] || fail "second off stays blank"
[[ $(<"$saved") == 40 ]] || fail "second off must not overwrite the saved level with 0"
pass "second off preserves the saved level"

run_kb restore
[[ $(<"$state") == 40 ]] || fail "restore returns the original level"
pass "restore returns the level saved before blanking"

grep -Fq 'brightnessctl -d chromeos::kbd_backlight set 0' "$call_log" ||
  fail "second off uses brightnessctl without -s"
pass "second off skips brightnessctl -s"
