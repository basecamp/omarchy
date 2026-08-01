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
    [[ ${MANAGER_AVAILABLE:-true} == "true" ]]
    ;;
  '--user daemon-reload')
    if [[ ${FAIL_SYSTEMCTL_ACTION:-} == "daemon-reload" ]]; then
      echo "reload failed" >&2
      exit 1
    fi
    ;;
  '--user show --property=ActiveState --value graphical-session.target')
    if [[ ${FAIL_SYSTEMCTL_ACTION:-} == "show-graphical" ]]; then
      echo "state lookup failed" >&2
      exit 1
    fi
    printf '%s\n' "${GRAPHICAL_STATE:-inactive}"
    ;;
  '--user show --property=ActiveState --value omarchy-sleep-lock.service')
    printf '%s\n' "${SLEEP_LOCK_STATE:-inactive}"
    ;;
  '--user restart omarchy-sleep-lock.service')
    if [[ ${FAIL_SYSTEMCTL_ACTION:-} == "restart" ]]; then
      echo "restart failed" >&2
      exit 1
    fi
    ;;
  '--user stop omarchy-sleep-lock.service')
    if [[ ${FAIL_SYSTEMCTL_ACTION:-} == "stop" ]]; then
      echo "stop failed" >&2
      exit 1
    fi
    ;;
  '--user reset-failed omarchy-sleep-lock.service') ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$stub_bin/systemctl"

migration="$ROOT/migrations/1785608166.sh"

run_migration() {
  local home="$1" calls="$2"
  shift 2

  mkdir -p "$home/run"
  HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_RUNTIME_DIR="$home/run" \
    SYSTEMCTL_CALLS="$calls" PATH="$stub_bin:$PATH" \
    "$@" bash -euo pipefail "$migration"
}

active_home="$test_tmp/active-home"
active_calls="$test_tmp/active-calls"
mkdir -p "$active_home/.config/systemd/user"
printf '%s\n' '[Service]' 'ExecStart=/usr/bin/omarchy-system-sleep-monitor' \
  >"$active_home/.config/systemd/user/omarchy-sleep-lock.service"

run_migration "$active_home" "$active_calls" \
  env GRAPHICAL_STATE=active SLEEP_LOCK_STATE=active >/dev/null

dropin="$active_home/.config/systemd/user/omarchy-sleep-lock.service.d/90-omarchy-session-environment.conf"
grep -Fx 'After=dbus.socket wayland-session-waitenv.service' "$dropin" >/dev/null ||
  fail "sleep lock migration orders a retained unit after the session environment import"
grep -Fx 'PartOf=graphical-session.target' "$dropin" >/dev/null ||
  fail "sleep lock migration ties a retained unit to the graphical session lifecycle"
grep -Fx 'ConditionEnvironment=OMARCHY_PATH' "$dropin" >/dev/null ||
  fail "sleep lock migration gates a retained unit on the Omarchy path"
grep -Fx 'ConditionEnvironment=WAYLAND_DISPLAY' "$dropin" >/dev/null ||
  fail "sleep lock migration gates a retained unit on the Wayland display"
pass "sleep lock migration repairs retained full-unit overrides with a drop-in"

grep -Fx -- '--user daemon-reload' "$active_calls" >/dev/null ||
  fail "sleep lock migration reloads the live user manager"
grep -Fx -- '--user reset-failed omarchy-sleep-lock.service' "$active_calls" >/dev/null ||
  fail "sleep lock migration cannot recover a start-limited monitor"
grep -Fx -- '--user restart omarchy-sleep-lock.service' "$active_calls" >/dev/null ||
  fail "sleep lock migration leaves an active monitor with its inherited environment"
grep -Fx -- '--user stop omarchy-sleep-lock.service' "$active_calls" >/dev/null &&
  fail "sleep lock migration stops the monitor inside an active graphical session"
pass "sleep lock migration replaces the monitor inside an active graphical session"

inactive_home="$test_tmp/inactive-home"
inactive_calls="$test_tmp/inactive-calls"
mkdir -p "$inactive_home"

run_migration "$inactive_home" "$inactive_calls" \
  env GRAPHICAL_STATE=inactive >/dev/null

grep -Fx -- '--user stop omarchy-sleep-lock.service' "$inactive_calls" >/dev/null ||
  fail "sleep lock migration leaves a stale monitor running after logout"
grep -Fx -- '--user restart omarchy-sleep-lock.service' "$inactive_calls" >/dev/null &&
  fail "sleep lock migration starts the monitor outside a graphical session"
pass "sleep lock migration stops a monitor left behind after logout"

failed_calls="$test_tmp/failed-calls"
if run_migration "$test_tmp/failed-home" "$failed_calls" \
  env GRAPHICAL_STATE=active SLEEP_LOCK_STATE=active FAIL_SYSTEMCTL_ACTION=restart \
  >"$test_tmp/failed-output" 2>&1; then
  fail "sleep lock migration marks a failed active-session repair complete"
fi
grep -F 'will be retried by omarchy-migrate' "$test_tmp/failed-output" >/dev/null ||
  fail "sleep lock migration does not explain that a failed repair remains pending"
pass "sleep lock migration keeps an active-session repair failure retryable"

reload_failed_calls="$test_tmp/reload-failed-calls"
if run_migration "$test_tmp/reload-failed-home" "$reload_failed_calls" \
  env FAIL_SYSTEMCTL_ACTION=daemon-reload >"$test_tmp/reload-failed-output" 2>&1; then
  fail "sleep lock migration ignores a failed user-manager reload"
fi
grep -F 'Could not reload the user service manager' "$test_tmp/reload-failed-output" >/dev/null ||
  fail "sleep lock migration does not report a failed user-manager reload"
pass "sleep lock migration keeps a failed user-manager reload retryable"

stop_failed_calls="$test_tmp/stop-failed-calls"
if run_migration "$test_tmp/stop-failed-home" "$stop_failed_calls" \
  env GRAPHICAL_STATE=inactive FAIL_SYSTEMCTL_ACTION=stop \
  >"$test_tmp/stop-failed-output" 2>&1; then
  fail "sleep lock migration ignores a stale monitor that could not be stopped"
fi
grep -F 'Could not stop stale omarchy-sleep-lock.service' "$test_tmp/stop-failed-output" >/dev/null ||
  fail "sleep lock migration does not report a stale monitor stop failure"
pass "sleep lock migration keeps a stale-monitor stop failure retryable"

state_failed_calls="$test_tmp/state-failed-calls"
if run_migration "$test_tmp/state-failed-home" "$state_failed_calls" \
  env FAIL_SYSTEMCTL_ACTION=show-graphical >"$test_tmp/state-failed-output" 2>&1; then
  fail "sleep lock migration ignores a failed session-state inspection"
fi
grep -F 'Could not inspect graphical-session.target' "$test_tmp/state-failed-output" >/dev/null ||
  fail "sleep lock migration does not report a failed session-state inspection"
pass "sleep lock migration keeps an indeterminate session repair retryable"

deferred_home="$test_tmp/deferred-home"
deferred_calls="$test_tmp/deferred-calls"
mkdir -p "$deferred_home/.config/systemd/user"
touch "$deferred_home/.config/systemd/user/omarchy-sleep-lock.service"

run_migration "$deferred_home" "$deferred_calls" \
  env MANAGER_AVAILABLE=false >/dev/null

[[ -f $deferred_home/.config/systemd/user/omarchy-sleep-lock.service.d/90-omarchy-session-environment.conf ]] ||
  fail "sleep lock migration does not persist the repair without a live user manager"
deferred_call_count=$(wc -l <"$deferred_calls")
(( deferred_call_count == 1 )) ||
  fail "sleep lock migration tries to mutate a user manager that is not running"
pass "sleep lock migration defers safely when no user manager is running"
