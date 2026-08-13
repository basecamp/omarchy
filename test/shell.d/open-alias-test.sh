#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/xdg-open" <<'SH'
#!/bin/bash
echo "launcher output"
echo "no handler for $1" >&2
touch "$OPEN_FINISHED"
SH
chmod +x "$stub_bin/xdg-open"

export PATH="$stub_bin:$PATH"
export OPEN_FINISHED="$test_tmp/finished"
TERM=dumb source "$ROOT/default/bash/aliases"

open "unknown:target" >"$test_tmp/out" 2>"$test_tmp/err"

# open is deliberately detached, so wait for the stub rather than accidentally
# turning this into a test that requires the helper to block.
for _ in {1..100}; do
  [[ -e $test_tmp/finished ]] && break
  sleep 0.01
done

[[ -e $test_tmp/finished ]] || fail "open waits forever or never starts xdg-open"
[[ ! -s $test_tmp/out ]] || fail "open leaks xdg-open progress to the terminal"
grep -Fxq 'no handler for unknown:target' "$test_tmp/err" ||
  fail "open hides the reason xdg-open could not launch a target"
pass "open stays quiet but shows launcher errors"
