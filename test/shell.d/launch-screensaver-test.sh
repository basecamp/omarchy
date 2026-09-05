#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

runtime="$tmpdir/usr/lib/omarchy-screensaver/omarchy-screensaver"
call_log="$tmpdir/calls"
mkdir -p "${runtime%/*}"

cat >"$runtime" <<'SH'
#!/bin/bash
for arg in "$@"; do
  printf '%s\n' "$arg"
done >"$CALL_LOG"
SH
chmod +x "$runtime"

launcher="$tmpdir/omarchy-launch-screensaver"
sed "s|/usr/lib/omarchy-screensaver/omarchy-screensaver|$runtime|" \
  "$ROOT/bin/omarchy-launch-screensaver" >"$launcher"
chmod +x "$launcher"

CALL_LOG="$call_log" "$launcher" force --effect decrypt --seed 1
mapfile -t args <"$call_log"
[[ ${args[*]} == "force --effect decrypt --seed 1" ]] ||
  fail "screensaver launcher preserves arguments" "args: ${args[*]}"

CALL_LOG="$call_log" "$launcher"
[[ ! -s $call_log ]] || fail "screensaver launcher accepts an empty argument list"

mock_bin="$tmpdir/bin"
fallback_log="$tmpdir/fallback"
mkdir -p "$mock_bin"
cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$FALLBACK_LOG"
exit 0
SH
chmod +x "$mock_bin/omarchy-cmd-missing"

rm -f "$runtime"
if PATH="$mock_bin:$PATH" FALLBACK_LOG="$fallback_log" "$launcher" 2>/dev/null; then
  fail "terminal fallback stops when ttfx is unavailable"
fi
[[ $(<"$fallback_log") == "ttfx" ]] ||
  fail "screensaver launcher checks the terminal fallback dependencies"

pass "screensaver launcher prefers native and retains terminal fallback"
