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
