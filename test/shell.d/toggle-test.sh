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

# Presence of bar-off hides the bar. User-facing on/off must track visibility,
# not the internal flag polarity (#9925).
HOME="$test_home" omarchy-toggle-bar off
[[ -f $bar_flag ]] || fail "bar off hides the bar by creating bar-off"
pass "bar off hides the bar by creating bar-off"

HOME="$test_home" omarchy-toggle-bar off
[[ -f $bar_flag ]] || fail "bar off is idempotent while the bar stays hidden"
pass "bar off is idempotent while the bar stays hidden"

HOME="$test_home" omarchy-toggle-bar on
[[ ! -f $bar_flag ]] || fail "bar on shows the bar by clearing bar-off"
pass "bar on shows the bar by clearing bar-off"

HOME="$test_home" omarchy-toggle-bar on
[[ ! -f $bar_flag ]] || fail "bar on is idempotent while the bar stays visible"
pass "bar on is idempotent while the bar stays visible"

# Plain toggle still flips visibility either way.
HOME="$test_home" omarchy-toggle-bar
[[ -f $bar_flag ]] || fail "bar toggle hides a visible bar"
pass "bar toggle hides a visible bar"

HOME="$test_home" omarchy-toggle-bar toggle
[[ ! -f $bar_flag ]] || fail "bar toggle shows a hidden bar"
pass "bar toggle shows a hidden bar"
