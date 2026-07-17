#!/bin/bash

set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/base-test.sh"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failing_script="$work_dir/fail.sh"
log_file="$work_dir/install.log"
cat >"$failing_script" <<'SCRIPT'
echo "about to fail"
false
SCRIPT

set +e
(
  set -euo pipefail
  export OMARCHY_INSTALL_LOG_FILE="$log_file"
  source "$ROOT/install/helpers/logging.sh"
  run_logged "$failing_script"
  echo "unreachable"
)
status=$?
set -e

(( status != 0 )) || fail "run_logged returns failing script status"
grep -q "Starting: $failing_script" "$log_file" || fail "run_logged logs script start"
grep -q "about to fail" "$log_file" || fail "run_logged captures script output"
grep -q "Failed: $failing_script (exit code: 1)" "$log_file" || fail "run_logged logs failed script before errexit exits"

stdout_log="$work_dir/stdout.log"
set +e
(
  set -euo pipefail
  export OMARCHY_INSTALL_LOG_FILE="$work_dir/iso-owned.log"
  export OMARCHY_LOG_TO_STDOUT=1
  source "$ROOT/install/helpers/logging.sh"
  run_logged "$failing_script"
) >"$stdout_log" 2>&1
stdout_status=$?
set -e

(( stdout_status != 0 )) || fail "stdout run_logged returns failing script status"
[[ ! -e $work_dir/iso-owned.log ]] || fail "stdout logging mode does not write directly to install log"
grep -q "Starting: $failing_script" "$stdout_log" || fail "stdout logging mode emits script start"
grep -q "about to fail" "$stdout_log" || fail "stdout logging mode emits script output"
grep -q "Failed: $failing_script (exit code: 1)" "$stdout_log" || fail "stdout logging mode emits failure marker"

pass "run_logged records failures under errexit"
