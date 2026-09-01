#!/bin/bash

# Shutdown and reboot arm the poweroff/reboot timer in the user manager before
# closing windows. The timer must fire after the close-all wait has run its
# course, or a heavy session is killed mid-flush and its state is lost on the
# next launch (issue #7085). Pin that invariant: the armed timer outlasts the
# close-all wait timeout.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

close_all_timeout=$(sed -n 's/.*OMARCHY_CLOSE_ALL_TIMEOUT:-\([0-9][0-9]*\)}.*/\1/p' \
  "$ROOT/bin/omarchy-hyprland-window-close-all" | head -n1)
[[ -n $close_all_timeout ]] || fail "close-all declares a wait timeout"
pass "close-all declares a wait timeout"

for script in omarchy-system-shutdown omarchy-system-reboot; do
  armed=$(sed -n 's/.*--on-active="\([0-9][0-9]*\)s".*/\1/p' "$ROOT/bin/$script" | head -n1)
  [[ -n $armed ]] || fail "$script arms a poweroff timer"
  (( armed > close_all_timeout )) ||
    fail "$script arms its timer ($armed s) past the close-all wait ($close_all_timeout s)"
  pass "$script arms its timer past the close-all wait"
done