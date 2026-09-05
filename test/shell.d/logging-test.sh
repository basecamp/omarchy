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


# --- start_install_log permissions ---------------------------------------------

# start_install_log only writes the file when a root-side apply command is
# rerun by hand on an installed system (the ISO logs to stdout and copies the
# log itself). It used to chmod 666 the file, so every local account could read
# the step output and append forged lines. Only root writes it; wheel may read
# it so omarchy-upload-log keeps working for the owner account.

grep -q 'chmod 666' "$ROOT/install/helpers/logging.sh" &&
  fail "install log is no longer world readable and writable"
grep -q 'chmod 640' "$ROOT/install/helpers/logging.sh" ||
  fail "install log is readable by root and wheel only"
pass "install log is readable by root and wheel only in the source"

# Logging still works after the permission change.
perms_log="$work_dir/perms-install.log"
(
  set -euo pipefail
  export OMARCHY_INSTALL_LOG_FILE="$perms_log"
  source "$ROOT/install/helpers/logging.sh"
  start_install_log
  omarchy_log_line "still logging"
)
grep -q "still logging" "$perms_log" ||
  fail "start_install_log still writes the log"
pass "start_install_log still writes the log"

# Where the filesystem reports modes faithfully, pin the actual bits. A
# filesystem that maps everything to one mode takes the source check above
# instead.
mode_probe="$work_dir/mode-probe"
touch "$mode_probe"
chmod 600 "$mode_probe"
if [[ $(stat -c %a "$mode_probe") == "600" ]]; then
  (
    set -euo pipefail
    export OMARCHY_INSTALL_LOG_FILE="$work_dir/root-only.log"
    source "$ROOT/install/helpers/logging.sh"
    start_install_log >/dev/null
  )
  [[ $(stat -c %a "$work_dir/root-only.log") == "640" ]] ||
    fail "a new install log is 0640"

  # A log left behind by an older, 0666 version is replaced the moment the new
  # run starts: same name, same content, new inode, restricted mode.
  left_open="$work_dir/left-open.log"
  printf 'earlier run\n' >"$left_open"
  chmod 666 "$left_open"
  old_inode=$(stat -c %i "$left_open")

  # A writer that opened the old file before the rerun. A chmod alone would
  # leave this descriptor able to append; the fresh file must not see it.
  exec 7>>"$left_open"

  (
    set -euo pipefail
    export OMARCHY_INSTALL_LOG_FILE="$left_open"
    source "$ROOT/install/helpers/logging.sh"
    start_install_log >/dev/null
  )
  printf 'stale write\n' >&7
  exec 7>&-

  [[ $(stat -c %a "$left_open") == "640" ]] ||
    fail "an existing world-open install log is restricted at startup"
  [[ $(stat -c %i "$left_open") != "$old_inode" ]] ||
    fail "an existing world-open install log is replaced, not chmodded in place"
  grep -q 'earlier run' "$left_open" ||
    fail "replacing the install log keeps its earlier content"
  grep -q 'stale write' "$left_open" &&
    fail "a descriptor opened on the old install log cannot write to the new one"
  pass "install log is 0640 when new, and an old 0666 log is replaced with a fresh file"
else
  pass "filesystem does not report modes here; mode bits pinned by the source check"
fi
