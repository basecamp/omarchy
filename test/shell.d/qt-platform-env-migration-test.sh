#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/systemctl" <<'STUB'
#!/bin/bash

printf '%s\n' "$*" >>"$SYSTEMCTL_CALLS"

case "$*" in
  '--user show-environment')
    if [[ ${MANAGER_AVAILABLE:-true} != "true" ]]; then
      echo "manager unavailable" >&2
      exit 1
    fi
    printf 'QT_QPA_PLATFORM=wayland;xcb\n'
    ;;
  '--user unset-environment QT_QPA_PLATFORM')
    if [[ ${FAIL_ACTION:-} == "systemd" ]]; then
      echo "unset failed" >&2
      exit 1
    fi
    ;;
  '--user show --property=ActiveState --value graphical-session.target')
    if [[ ${FAIL_ACTION:-} == "session-state" ]]; then
      echo "state lookup failed" >&2
      exit 1
    fi
    printf '%s\n' "${GRAPHICAL_STATE:-active}"
    ;;
  *) exit 1 ;;
esac
STUB

cat >"$stub_bin/dbus-update-activation-environment" <<'STUB'
#!/bin/bash

printf '%s\n' "$*" >>"$DBUS_CALLS"
if [[ ${FAIL_ACTION:-} == "dbus" ]]; then
  echo "D-Bus update failed" >&2
  exit 1
fi
STUB

cat >"$stub_bin/hyprctl" <<'STUB'
#!/bin/bash

printf '%s\n' "$*" >>"$HYPRCTL_CALLS"
if [[ ${FAIL_ACTION:-} == "hyprland" ]]; then
  echo "Hyprland update failed" >&2
  exit 1
fi
STUB

cat >"$stub_bin/pgrep" <<'STUB'
#!/bin/bash

[[ ${STEAM_RUNNING:-false} == "true" ]]
STUB

chmod +x "$stub_bin"/*

migration="$ROOT/migrations/1787946762.sh"

run_migration() {
  local calls_dir="$1"
  shift

  mkdir -p "$calls_dir/run"
  : >"$calls_dir/systemctl"
  : >"$calls_dir/dbus"
  : >"$calls_dir/hyprctl"

  HOME="$calls_dir/home" XDG_RUNTIME_DIR="$calls_dir/run" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$calls_dir/run/bus" \
    SYSTEMCTL_CALLS="$calls_dir/systemctl" DBUS_CALLS="$calls_dir/dbus" HYPRCTL_CALLS="$calls_dir/hyprctl" \
    PATH="$stub_bin:$PATH" "$@" bash -euo pipefail "$migration"
}

active_calls="$test_tmp/active"
run_migration "$active_calls" env STEAM_RUNNING=true >"$test_tmp/active-output"

grep -Fx -- '--user unset-environment QT_QPA_PLATFORM' "$active_calls/systemctl" >/dev/null ||
  fail "Qt platform migration clears the user service manager environment"
grep -Fx -- 'QT_QPA_PLATFORM=' "$active_calls/dbus" >/dev/null ||
  fail "Qt platform migration neutralizes the D-Bus activation environment"
grep -Fx -- 'eval hl.env("QT_QPA_PLATFORM", "")' "$active_calls/hyprctl" >/dev/null ||
  fail "Qt platform migration clears the running compositor environment"
pass "Qt platform migration clears every live launch environment"

grep -F 'Fully exit and restart Steam before launching SteamVR' "$test_tmp/active-output" >/dev/null ||
  fail "Qt platform migration tells users to restart an affected Steam process"
pass "Qt platform migration communicates the required Steam restart"

inactive_calls="$test_tmp/inactive"
run_migration "$inactive_calls" env GRAPHICAL_STATE=inactive >/dev/null
[[ ! -s $inactive_calls/hyprctl ]] ||
  fail "Qt platform migration tries to mutate Hyprland outside a graphical session"
pass "Qt platform migration skips Hyprland outside a graphical session"

offline_calls="$test_tmp/offline"
mkdir -p "$offline_calls"
if HOME="$offline_calls/home" XDG_RUNTIME_DIR="$offline_calls/run" \
  SYSTEMCTL_CALLS="$offline_calls/systemctl" PATH="$stub_bin:$PATH" MANAGER_AVAILABLE=false \
  bash -euo pipefail "$migration" >"$test_tmp/offline-output" 2>&1; then
  pass "Qt platform migration defers to a clean environment at the next login"
else
  fail "Qt platform migration fails without a running user manager" "$(<"$test_tmp/offline-output")"
fi

for action in systemd session-state dbus hyprland; do
  failed_calls="$test_tmp/failed-$action"
  if run_migration "$failed_calls" env FAIL_ACTION="$action" >"$test_tmp/failed-$action-output" 2>&1; then
    fail "Qt platform migration ignores a failed $action cleanup"
  fi
  grep -F 'will be retried by omarchy-migrate' "$test_tmp/failed-$action-output" >/dev/null ||
    fail "Qt platform migration does not keep a failed $action cleanup retryable"
done
pass "Qt platform migration keeps incomplete live cleanup retryable"

rerun_calls="$test_tmp/rerun"
run_migration "$rerun_calls" env STEAM_RUNNING=false >/dev/null
run_migration "$rerun_calls" env STEAM_RUNNING=false >/dev/null
pass "Qt platform migration is idempotent"
