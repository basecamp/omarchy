#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

lid_close="$ROOT/bin/omarchy-system-lid-close"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# closed/docked are the two facts logind uses to decide whether a lid close
# suspends, so each scenario pins them and records what the lid handler did.
setup_scenario() {
  scenario_dir="$tmpdir/$1"
  mock_bin="$scenario_dir/bin"
  call_log="$scenario_dir/calls"
  mkdir -p "$mock_bin"
  : >"$call_log"

  local closed="$2" docked="$3"

  cat >"$mock_bin/omarchy-hw-laptop-closed" <<SH
#!/bin/bash
exit $closed
SH
  cat >"$mock_bin/omarchy-hw-external-monitors" <<SH
#!/bin/bash
exit $docked
SH
  for command in omarchy-system-lock omarchy-hyprland-monitor-clamshell; do
    cat >"$mock_bin/$command" <<SH
#!/bin/bash
echo $command >>"\$CALL_LOG"
SH
  done
  chmod +x "$mock_bin"/*
}

run_lid_close() {
  CALL_LOG="$call_log" PATH="$mock_bin:$PATH" "$lid_close"
  mapfile -t calls <"$call_log"
}

# An undocked lid close is about to suspend, and logind's inhibitor window is a
# timer rather than a promise, so the lock has to start now instead of waiting
# for PrepareForSleep.
setup_scenario undocked 0 1
run_lid_close

[[ ${calls[0]} == "omarchy-system-lock" ]] ||
  fail "undocked lid close locks before anything else" "calls: ${calls[*]}"
pass "undocked lid close locks before anything else"

[[ ${calls[1]} == "omarchy-hyprland-monitor-clamshell" ]] ||
  fail "undocked lid close still reconciles displays" "calls: ${calls[*]}"
pass "undocked lid close still reconciles displays"

# A docked lid close is clamshell mode: logind leaves the machine awake and the
# session stays in use on the external display, so locking it would be wrong.
setup_scenario docked 0 0
run_lid_close

[[ ${calls[*]} != *omarchy-system-lock* ]] ||
  fail "docked lid close does not lock the session" "calls: ${calls[*]}"
pass "docked lid close does not lock the session"

[[ ${calls[0]} == "omarchy-hyprland-monitor-clamshell" ]] ||
  fail "docked lid close reconciles displays" "calls: ${calls[*]}"
pass "docked lid close reconciles displays"

# Hyprland can replay a switch binding when the lid is already open, and an
# open lid must never lock the machine the user is sitting at.
setup_scenario open 1 1
run_lid_close

[[ ${calls[*]} != *omarchy-system-lock* ]] ||
  fail "an open lid never locks the session" "calls: ${calls[*]}"
pass "an open lid never locks the session"

# The lid handler runs from a Hyprland binding, so a lock that hangs or fails
# must not stop the display reconciliation behind it.
setup_scenario failing_lock 0 1
cat >"$mock_bin/omarchy-system-lock" <<'SH'
#!/bin/bash
echo omarchy-system-lock >>"$CALL_LOG"
exit 1
SH
chmod +x "$mock_bin/omarchy-system-lock"
run_lid_close

[[ ${calls[1]} == "omarchy-hyprland-monitor-clamshell" ]] ||
  fail "a failing lock still reconciles displays" "calls: ${calls[*]}"
pass "a failing lock still reconciles displays"
