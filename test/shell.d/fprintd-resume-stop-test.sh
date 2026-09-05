#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hook="$ROOT/default/systemd/system-sleep/fprintd-resume-stop"
[[ -x $hook ]] || fail "fingerprint resume hook is executable" "mode: $(stat -c '%A' "$hook")"
pass "fingerprint resume hook is executable"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mock_bin="$tmp_dir/bin"
timeout_log="$tmp_dir/timeout.log"
systemctl_log="$tmp_dir/systemctl.log"
logger_log="$tmp_dir/logger.log"
state_file="$tmp_dir/fprintd-sleep.pid"
mkdir -p "$mock_bin"

cat >"$mock_bin/timeout" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TIMEOUT_LOG"
if [[ ${TIMEOUT_FAIL:-0} == 1 ]]; then
  exit 124
fi
shift
exec "$@"
STUB

cat >"$mock_bin/systemctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
if [[ $1 == "show" ]]; then
  printf '%s\n' "${MOCK_FPRINTD_PID:-0}"
fi
STUB

cat >"$mock_bin/logger" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$LOGGER_LOG"
STUB

chmod +x "$mock_bin/timeout" "$mock_bin/systemctl" "$mock_bin/logger"

run_hook() {
  : >"$timeout_log"
  : >"$systemctl_log"
  : >"$logger_log"
  PATH="$mock_bin:$PATH" \
    TIMEOUT_LOG="$timeout_log" \
    SYSTEMCTL_LOG="$systemctl_log" \
    LOGGER_LOG="$logger_log" \
    OMARCHY_FPRINTD_SLEEP_STATE="$state_file" \
    "$hook" "$@"
}

MOCK_FPRINTD_PID=101 run_hook pre suspend
[[ $(<"$state_file") == 101 ]] ||
  fail "pre-suspend records the active fprintd process" "state: $(<"$state_file")"
pass "pre-suspend records the active fprintd process"

MOCK_FPRINTD_PID=101 run_hook post suspend
[[ $(<"$timeout_log") == "6s systemctl stop fprintd.service" ]] ||
  fail "resume bounds the stale daemon stop" "timeout: $(<"$timeout_log")"
grep -qx 'stop fprintd.service' "$systemctl_log" ||
  fail "resume stops fprintd without restarting it in the hook" "systemctl: $(<"$systemctl_log")"
grep -q 'Stopped fprintd PID 101 after suspend resume' "$logger_log" ||
  fail "resume logs successful recovery" "log: $(<"$logger_log")"
pass "resume stops the stale daemon within a bound"

MOCK_FPRINTD_PID=102 run_hook pre hibernate
MOCK_FPRINTD_PID=102 run_hook post hibernate
grep -qx 'stop fprintd.service' "$systemctl_log" ||
  fail "hibernate resume clears the stale daemon" "systemctl: $(<"$systemctl_log")"
pass "hibernate resume clears the stale daemon"

MOCK_FPRINTD_PID=201 run_hook pre suspend
MOCK_FPRINTD_PID=202 run_hook post suspend
[[ ! -s $timeout_log ]] ||
  fail "resume leaves a replacement daemon alone" "timeout: $(<"$timeout_log")"
! grep -q '^stop ' "$systemctl_log" ||
  fail "resume leaves a replacement daemon alone" "systemctl: $(<"$systemctl_log")"
[[ ! -s $logger_log ]] ||
  fail "resume stays quiet when preserving a replacement daemon" "log: $(<"$logger_log")"
pass "resume leaves a replacement daemon alone"

MOCK_FPRINTD_PID=0 run_hook pre suspend
[[ ! -e $state_file ]] || fail "pre-suspend records no inactive daemon"
[[ ! -s $logger_log ]] ||
  fail "pre-suspend stays quiet without an active daemon" "log: $(<"$logger_log")"
pass "pre-suspend records no inactive daemon"

MOCK_FPRINTD_PID=301 run_hook pre suspend
MOCK_FPRINTD_PID=301 TIMEOUT_FAIL=1 run_hook post suspend ||
  fail "a timed-out daemon stop does not block resume"
grep -q 'Failed to stop fprintd PID 301 after suspend resume' "$logger_log" ||
  fail "a timed-out daemon stop is visible in the journal" "log: $(<"$logger_log")"
pass "a timed-out daemon stop does not block resume"
