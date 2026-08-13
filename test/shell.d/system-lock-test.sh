#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
call_log="$tmpdir/calls"
mkdir -p "$mock_bin"

for command in omarchy-shell hyprctl pkill timeout; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done

cat >"$mock_bin/pgrep" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin"/*

PATH="$mock_bin:$PATH" CALL_LOG="$call_log" "$ROOT/bin/omarchy-system-lock"
mapfile -t shutdown < <(rg '^(pkill|timeout) ' "$call_log")

[[ ${shutdown[0]} == "pkill -x omarchy-saver" ]] ||
  fail "system lock stops the screensaver supervisors" "calls: ${shutdown[*]}"
[[ ${shutdown[1]} == "timeout 2s pidwait -x omarchy-saver" ]] ||
  fail "system lock waits for the screensaver supervisors" "calls: ${shutdown[*]}"
(( ${#shutdown[@]} == 2 )) ||
  fail "system lock does not kill ttfx or its terminal directly" "calls: ${shutdown[*]}"
pass "system lock lets screensaver supervisors close their terminals"
