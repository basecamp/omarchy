#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
fake_home="$test_tmp/home"
mkdir -p "$fake_bin" "$fake_home"

secrets_dir="$fake_home/.local/share/omarchy/backup"
state_dir="$fake_home/.local/state/omarchy/backup"
config_dir="$fake_home/.config/omarchy/backup"
status_file="$state_dir/status.json"

stub() {
  local name="$1"
  cat >"$fake_bin/$name"
  chmod +x "$fake_bin/$name"
}

# restic, reduced to the three things the runner reads: the JSON stream, the
# exit code, and the snapshot listing.
stub restic <<'STUB'
#!/bin/bash
while [[ $1 == --retry-lock ]]; do shift 2; done
printf 'restic %s\n' "$*" >>"$TEST_LOG"

case "$1" in
backup)
  printf '{"message_type":"status","percent_done":0.5,"bytes_done":100,"total_bytes":200,"files_done":3}\n'
  if [[ ${STUB_UNREADABLE:-0} == 1 ]]; then
    printf '{"message_type":"error","item":"/home/x/vault"}\n'
  fi
  printf '{"message_type":"summary","snapshot_id":"abcd1234"}\n'
  [[ ${STUB_BACKUP_EXIT:-0} == 0 ]] || echo "restic said no" >&2
  exit "${STUB_BACKUP_EXIT:-0}"
  ;;
snapshots)
  printf '[{"short_id":"abcd1234","time":"2026-08-22T10:00:00.123456+02:00","hostname":"%s","paths":["/home/x"]}]\n' "$(hostname)"
  ;;
stats)
  echo '{"total_size":12345}'
  ;;
esac
exit 0
STUB

stub omarchy-cmd-missing <<'STUB'
#!/bin/bash
exit 1
STUB

stub omarchy-battery-below <<'STUB'
#!/bin/bash
exit "${STUB_BATTERY_LOW:-1}"
STUB

stub omarchy-notification-send <<'STUB'
#!/bin/bash
printf 'notification %s\n' "$*" >>"$TEST_LOG"
STUB

run_backup() {
  : >"$test_tmp/calls.log"
  TEST_LOG="$test_tmp/calls.log" \
    HOME="$fake_home" \
    XDG_STATE_HOME="$fake_home/.local/state" \
    OMARCHY_PATH="$ROOT" \
    PATH="$fake_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-backup-run" >/dev/null 2>&1
}

field() {
  jq -r "$1" "$status_file"
}

configure() {
  mkdir -p "$secrets_dir" "$config_dir"
  printf 'RESTIC_REPOSITORY=%s\n' "$test_tmp/repo" >"$secrets_dir/env"
  printf 'passphrase\n' >"$secrets_dir/passphrase"
  cat >"$config_dir/settings" <<SETTINGS
BACKUP_DESTINATION_LABEL="test bucket"
BACKUP_DESTINATION_KIND="s3"
BACKUP_MAINTENANCE_HOST="$(hostname)"
SETTINGS
}

# An unconfigured machine must record that it is unconfigured rather than
# looking like a machine whose backups merely have not run yet.
run_backup
[[ $(field '.phase') == "unconfigured" ]] || fail "an unconfigured run records unconfigured" "$(cat "$status_file")"
! grep -q '^restic backup' "$test_tmp/calls.log" || fail "an unconfigured run does not call restic"
pass "a run without credentials records unconfigured and touches nothing"

configure
run_backup

[[ $(field '.last_backup.result') == "complete" ]] || fail "a successful run is recorded as complete" "$(cat "$status_file")"
[[ $(field '.last_backup.snapshot') == "abcd1234" ]] || fail "the snapshot id is recorded"
[[ $(field '.last_complete.snapshot') == "abcd1234" ]] || fail "a complete run advances the restore default"
[[ $(field '.phase') == "idle" ]] || fail "the run finishes idle, not running"
[[ $(field '.pid') == "0" ]] || fail "the finished run clears its pid"
[[ $(field '.repository.size_bytes') == "12345" ]] || fail "the repository size is refreshed"
(( $(field '.snapshots[0].time') > 0 )) || fail "snapshot times are converted to epoch seconds" "$(field '.snapshots')"
pass "a successful run records the snapshot, the size, and an idle phase"

grep -q '^restic backup --json --one-file-system' "$test_tmp/calls.log" ||
  fail "the backup stays on one filesystem" "$(cat "$test_tmp/calls.log")"
pass "mounted disks and network shares are never traversed"

# restic takes exclude patterns literally, so a ~ that survives into the file
# excludes a directory named "~" and nothing else.
! grep -q '~' "$state_dir/excludes" || fail "exclude patterns are expanded, not left as tildes" "$(cat "$state_dir/excludes")"
grep -qxF "$secrets_dir" "$state_dir/excludes" || fail "the credentials are excluded from the backup that they unlock"
grep -qxF "$fake_home/.cache" "$state_dir/excludes" || fail "caches are excluded"
pass "the effective exclude file is absolute and keeps the credentials out"

printf 'Videos/raw\n' >"$config_dir/excludes"
run_backup
grep -qxF "$fake_home/Videos/raw" "$state_dir/excludes" || fail "user patterns are honored" "$(cat "$state_dir/excludes")"
rm -f "$config_dir/excludes"
pass "user exclude patterns are expanded the same way"

printf 'manual\n' >"$state_dir/pause"
run_backup
[[ $(field '.phase') == "paused" ]] || fail "a paused machine records the pause"
[[ $(field '.last_skip.reason') == *paused* ]] || fail "the pause is recorded as a skip, not a failure"
! grep -q '^restic backup' "$test_tmp/calls.log" || fail "a paused machine does not back up"
pass "an open-ended pause skips the run without failing it"

# A pause that has expired has to clear itself: the runner is the only thing
# that runs on a schedule, so nothing else would ever notice.
printf '%s\n' "$(( $(date +%s) - 60 ))" >"$state_dir/pause"
run_backup
[[ ! -f $state_dir/pause ]] || fail "an expired pause is cleared"
[[ $(field '.last_backup.result') == "complete" ]] || fail "an expired pause lets the backup run"
pass "an expired pause clears itself and the backup resumes"

STUB_BATTERY_LOW=0 run_backup
[[ $(field '.last_skip.reason') == *battery* ]] || fail "a flat battery is a skip" "$(cat "$status_file")"
pass "a discharging laptop below the floor skips instead of uploading"

complete_at=$(field '.last_complete.time')
complete_snapshot=$(field '.last_complete.snapshot')

STUB_BACKUP_EXIT=3 STUB_UNREADABLE=1 run_backup
[[ $(field '.last_backup.result') == "partial" ]] || fail "exit 3 is a partial backup, not a failure"
[[ $(field '.last_backup.unreadable[0]') == "/home/x/vault" ]] || fail "the unreadable paths are surfaced"
[[ $(field '.last_complete.snapshot') == "$complete_snapshot" ]] || fail "the earlier complete snapshot is still the restore default"
[[ $(field '.last_complete.time') == "$complete_at" ]] ||
  fail "a partial backup must not become the snapshot restores default to"
pass "a partial backup is kept, flagged, and never becomes the restore default"

STUB_BACKUP_EXIT=1 run_backup
[[ $(field '.phase') == "error" ]] || fail "a failed run records an error phase"
[[ $(field '.last_backup.error') == *"restic said no"* ]] || fail "the failure carries restic's own words" "$(field '.last_backup.error')"
pass "a failed run records why it failed"

STUB_BACKUP_EXIT=11 run_backup
[[ $(field '.last_skip.reason') == *"another machine"* ]] || fail "lock contention is a skip"
[[ $(field '.phase') != "error" ]] || fail "lock contention is not an error"
pass "another machine holding the repository lock is a skip, not a failure"

# A crash or a reboot mid-backup leaves a `running` record behind. Left alone
# the panel shows an upload that will never finish.
jq '.phase = "running" | .pid = 999999' "$status_file" >"$status_file.tmp" && mv "$status_file.tmp" "$status_file"
printf 'manual\n' >"$state_dir/pause"
run_backup
[[ $(field '.last_backup.result') == "failed" ]] || fail "a run that died is reconciled as failed" "$(cat "$status_file")"
rm -f "$state_dir/pause"
pass "a run that died without reporting is reconciled instead of showing forever"

printf '%s 0\n' "$(( $(date +%s) - 40 * 86400 ))" >"$state_dir/maintenance"
run_backup
grep -q 'restic forget --prune .*--keep-hourly 24 --keep-daily 7 --keep-weekly 5 --keep-monthly 12' "$test_tmp/calls.log" ||
  fail "maintenance forgets on the documented retention" "$(cat "$test_tmp/calls.log")"
grep -q 'restic check --read-data-subset=1/12' "$test_tmp/calls.log" ||
  fail "maintenance reads a rotating slice of the data" "$(cat "$test_tmp/calls.log")"
[[ $(cut -d' ' -f2 "$state_dir/maintenance") == "1" ]] || fail "the read-data slice advances"
pass "monthly maintenance prunes and verifies a rotating slice"

# The expensive half of the work belongs to one machine, or every laptop
# sharing a repository pays for it.
sed -i "s/^BACKUP_MAINTENANCE_HOST=.*/BACKUP_MAINTENANCE_HOST=\"some-other-machine\"/" "$config_dir/settings"
printf '%s 0\n' "$(( $(date +%s) - 40 * 86400 ))" >"$state_dir/maintenance"
run_backup
! grep -q 'restic forget' "$test_tmp/calls.log" || fail "only the maintenance host prunes"
pass "machines that do not own maintenance never prune or check"
