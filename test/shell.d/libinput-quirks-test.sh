#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command libinput

quirks="$ROOT/default/libinput/50-omarchy.quirks"

[[ -f $quirks ]] || fail "the shipped libinput quirks file exists"
pass "the shipped libinput quirks file exists"

# Stage the file alone: libinput validates a whole directory, so the host's own
# quirks would confound the result.
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
cp "$quirks" "$test_tmp/"

if ! validate_output=$(libinput quirks validate --data-dir "$test_tmp" 2>&1); then
  fail "the shipped quirks file parses" "$validate_output"
fi
pass "the shipped quirks file parses"

# Dropping a PID silently reintroduces the bug for that dongle.
for product in 0x2B1E 0x2EF2 0x2F06; do
  grep -q "MatchProduct=$product" "$quirks" ||
    fail "the quirks cover the known Shokz dongles" "missing $product"
done
pass "the quirks cover the known Shokz dongles"

# The volume and media keys are real; only KEY_POWER may be dropped.
if grep '^AttrEventCode=' "$quirks" | grep -qvx 'AttrEventCode=-KEY_POWER'; then
  fail "the quirks drop only the phantom power key" "$(grep '^AttrEventCode=' "$quirks")"
fi
pass "the quirks drop only the phantom power key"
