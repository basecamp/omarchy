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

[[ ${shutdown[0]} == "pkill -f [/]usr/lib/omarchy-screensaver/omarchy-screensaver" ]] ||
  fail "system lock stops the native screensaver" "calls: ${shutdown[*]}"
[[ ${shutdown[1]} == "timeout 1s pidwait -f [/]usr/lib/omarchy-screensaver/omarchy-screensaver" ]] ||
  fail "system lock waits for the native screensaver to clean up" "calls: ${shutdown[*]}"
[[ ${shutdown[2]} == "pkill -KILL -f [/]usr/lib/omarchy-screensaver/omarchy-screensaver" ]] ||
  fail "system lock force-stops a stuck native screensaver" "calls: ${shutdown[*]}"
[[ ${shutdown[3]} == "pkill -x ttfx" ]] ||
  fail "system lock stops the terminal fallback" "calls: ${shutdown[*]}"
[[ ${shutdown[4]} == "timeout 1s pidwait -x ttfx" ]] ||
  fail "system lock waits for the terminal fallback to exit" "calls: ${shutdown[*]}"
[[ ${shutdown[5]} == "pkill -f [o]rg.omarchy.screensaver" ]] ||
  fail "system lock closes the fallback terminal" "calls: ${shutdown[*]}"
pass "system lock stops native and fallback screensavers"
