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

rm -f "$runtime"
if CALL_LOG="$call_log" "$launcher" 2>/dev/null; then
  fail "screensaver launcher fails when the native implementation is missing"
fi

pass "screensaver launcher delegates to the packaged native implementation"
