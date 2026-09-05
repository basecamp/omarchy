#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""

export PATH="$ROOT/bin:$PATH"

cleanup() {
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

TMPDIR=$(mktemp -d)
test_home="$TMPDIR/home"
flag="$test_home/.local/state/omarchy/toggles/example"
bar_flag="$test_home/.local/state/omarchy/toggles/bar-off"

HOME="$test_home" omarchy-toggle example on
[[ -f $flag ]] || fail "generic toggle enables explicit on state"
pass "generic toggle enables explicit on state"

HOME="$test_home" omarchy-toggle example on
[[ -f $flag ]] || fail "generic toggle on is idempotent"
pass "generic toggle on is idempotent"

HOME="$test_home" omarchy-toggle example off
[[ ! -f $flag ]] || fail "generic toggle disables explicit off state"
pass "generic toggle disables explicit off state"

HOME="$test_home" omarchy-toggle example
[[ -f $flag ]] || fail "generic toggle flips disabled state on"
pass "generic toggle flips disabled state on"

HOME="$test_home" omarchy-toggle example toggle
[[ ! -f $flag ]] || fail "generic toggle flips enabled state off"
pass "generic toggle flips enabled state off"

HOME="$test_home" omarchy-toggle-bar off
[[ -f $bar_flag ]] || fail "bar off hides the bar (sets bar-off flag)"
pass "bar off hides the bar (sets bar-off flag)"

HOME="$test_home" omarchy-toggle-bar off
[[ -f $bar_flag ]] || fail "bar off is idempotent"
pass "bar off is idempotent"

HOME="$test_home" omarchy-toggle-bar on
[[ ! -f $bar_flag ]] || fail "bar on shows the bar (clears bar-off flag)"
pass "bar on shows the bar (clears bar-off flag)"
