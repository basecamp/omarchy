#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1786305695.sh"
unit_source="$ROOT/default/systemd/system/omarchy-bluetooth-state.service"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

# sudo runs the real command, so install acts on the redirected paths below
# while systemctl and the state helper resolve to the stubs beside them.
cat >"$test_dir/bin/sudo" <<'STUB'
#!/bin/bash

exec "$@"
STUB

cat >"$test_dir/bin/systemctl" <<'STUB'
#!/bin/bash

printf 'systemctl %s\n' "$*" >>"$CALLS"

if [[ $1 == is-active ]]; then
  [[ -n ${BLUETOOTHD_ACTIVE:-} ]] && exit 0
  exit 1
fi

if [[ $1 == enable && -n ${ENABLE_FAILS:-} ]]; then
  exit 1
fi

exit 0
STUB

# seed only needs to be observed, but disable-autoenable has to actually rewrite
# main.conf, so it runs for real against OMARCHY_BLUETOOTH_MAIN_CONF.
cat >"$test_dir/bin/omarchy-bluetooth-state" <<'STUB'
#!/bin/bash

printf 'omarchy-bluetooth-state %s\n' "$*" >>"$CALLS"

[[ $1 == "disable-autoenable" ]] && exec "$ROOT/bin/omarchy-bluetooth-state" "$@"
exit 0
STUB

chmod +x "$test_dir/bin/"*

export CALLS="$test_dir/calls"

marker="$test_dir/marker"
main_conf="$test_dir/main.conf"
unit_dest="$test_dir/omarchy-bluetooth-state.service"

reset_machine() {
  rm -f "$marker" "$unit_dest"
  printf '[Policy]\n#AutoEnable=true\n' >"$main_conf"
}

run_migration() {
  : >"$CALLS"

  OMARCHY_PATH="$ROOT" \
    OMARCHY_BLUETOOTH_MIGRATION_MARKER="$marker" \
    OMARCHY_BLUETOOTH_MAIN_CONF="$main_conf" \
    OMARCHY_BLUETOOTH_STATE_UNIT="$unit_dest" \
    PATH="$test_dir/bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

call_line() {
  grep -n -- "$1" "$CALLS" | head -1 | cut -d: -f1
}

# A first run on a machine with bluetoothd up does the whole job.
reset_machine
export BLUETOOTHD_ACTIVE=1
run_migration

grep -q '^AutoEnable=false$' "$main_conf" ||
  fail "migration turns AutoEnable off" "$(cat "$main_conf")"
pass "migration turns AutoEnable off"

cmp -s "$unit_source" "$unit_dest" ||
  fail "migration installs the shipped unit"
pass "migration installs the shipped unit"

grep -q '^systemctl enable omarchy-bluetooth-state.service$' "$CALLS" ||
  fail "migration enables the unit" "$(cat "$CALLS")"
pass "migration enables the unit"

grep -q '^systemctl start omarchy-bluetooth-state.service$' "$CALLS" ||
  fail "migration starts the unit while bluetoothd is up" "$(cat "$CALLS")"
pass "migration starts the unit while bluetoothd is up"

(($(call_line '^omarchy-bluetooth-state seed$') < $(call_line '^systemctl start'))) ||
  fail "migration seeds the saved state before starting the unit" "$(cat "$CALLS")"
pass "migration seeds the saved state before starting the unit"

[[ -e $marker ]] || fail "migration records the machine as done"
pass "migration records the machine as done"

# Migration completion is recorded per user, so a second account must not undo
# an administrator's opt-out made after the first run.
printf '[Policy]\nAutoEnable=true\n' >"$main_conf"
rm -f "$unit_dest"
run_migration

grep -q '^AutoEnable=true$' "$main_conf" ||
  fail "migration leaves a later AutoEnable opt-out alone" "$(cat "$main_conf")"
pass "migration leaves a later AutoEnable opt-out alone"

[[ ! -e $unit_dest ]] || fail "migration does not reinstall the unit on a second run"
pass "migration does not reinstall the unit on a second run"

[[ ! -s $CALLS ]] ||
  fail "migration runs no systemctl on a second run" "$(cat "$CALLS")"
pass "migration runs no systemctl on a second run"

# With bluetoothd stopped, starting the unit would pull it back up through
# BindsTo, so the unit is only enabled and left for the next bluetoothd start.
reset_machine
unset BLUETOOTHD_ACTIVE
run_migration

grep -q '^systemctl enable omarchy-bluetooth-state.service$' "$CALLS" ||
  fail "migration still enables the unit while bluetoothd is down" "$(cat "$CALLS")"
pass "migration still enables the unit while bluetoothd is down"

grep -q '^systemctl start' "$CALLS" &&
  fail "migration does not start the unit while bluetoothd is down" "$(cat "$CALLS")"
pass "migration does not start the unit while bluetoothd is down"

# A bluez .pacnew merge can leave main.conf with no AutoEnable line at all, and
# the marker means this run is the only chance to put it back.
reset_machine
printf '[General]\nName=Omarchy\n\n[Policy]\nReconnectAttempts=7\n' >"$main_conf"
run_migration

grep -q '^AutoEnable=false$' "$main_conf" ||
  fail "migration adds AutoEnable when main.conf has no such key" "$(cat "$main_conf")"
pass "migration adds AutoEnable when main.conf has no such key"

grep -q '^ReconnectAttempts=7$' "$main_conf" ||
  fail "migration leaves the rest of the Policy section intact" "$(cat "$main_conf")"
pass "migration leaves the rest of the Policy section intact"

# An interrupted run must be retried by the next user rather than skipped.
reset_machine
export ENABLE_FAILS=1
if run_migration 2>/dev/null; then
  fail "migration fails when the unit cannot be enabled"
fi
pass "migration fails when the unit cannot be enabled"

[[ ! -e $marker ]] || fail "migration leaves no marker behind when it fails"
pass "migration leaves no marker behind when it fails"
