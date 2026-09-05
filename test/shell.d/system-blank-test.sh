#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
call_log="$test_tmp/calls"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-brightness-keyboard" <<'SH'
#!/bin/bash
printf 'keyboard %s\n' "$*" >>"$CALL_LOG"
SH
cat >"$mock_bin/omarchy-brightness-display" <<'SH'
#!/bin/bash
printf 'display %s\n' "$*" >>"$CALL_LOG"
SH
chmod +x "$mock_bin"/*

CALL_LOG="$call_log" PATH="$mock_bin:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-system-blank"
[[ $(sed -n 1p "$call_log") == "keyboard off" ]] || fail "blank turns the keyboard backlight off first"
[[ $(sed -n 2p "$call_log") == "display off" ]] || fail "blank turns the displays off"
pass "omarchy-system-blank is the inverse of omarchy-system-wake"

# Machines without a keyboard backlight fail the first step -- the display is
# the part that has to happen either way, and the script has no set -e to
# stop it from getting there.
: >"$call_log"
cat >"$mock_bin/omarchy-brightness-keyboard" <<'SH'
#!/bin/bash
printf 'keyboard %s\n' "$*" >>"$CALL_LOG"
exit 1
SH
chmod +x "$mock_bin/omarchy-brightness-keyboard"

CALL_LOG="$call_log" PATH="$mock_bin:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-system-blank" || true
[[ $(sed -n 1p "$call_log") == "keyboard off" ]] || fail "blank still tries the keyboard backlight first"
[[ $(sed -n 2p "$call_log") == "display off" ]] || fail "blank still turns the displays off when the keyboard backlight step fails"
pass "omarchy-system-blank blanks the displays even on a machine without a keyboard backlight"
