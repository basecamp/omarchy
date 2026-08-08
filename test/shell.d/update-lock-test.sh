#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
runtime_dir="$test_tmp/runtime"
mkdir -p "$stub_bin" "$test_home" "$runtime_dir"

run_with_lock_env() {
  HOME="$test_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  XDG_STATE_HOME="$test_tmp/state" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$@"
}

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

for command in \
  omarchy-toggle-idle \
  systemd-inhibit \
  omarchy-update-dev \
  omarchy-update-keyring \
  omarchy-update-system-pkgs \
  omarchy-migrate \
  omarchy-update-aur-pkgs \
  omarchy-update-mise \
  omarchy-update-orphan-pkgs \
  omarchy-hook \
  omarchy-update-analyze-logs \
  omarchy-shell \
  omarchy-update-restart; do
  write_stub "$command" 'exit 0'
done
write_stub omarchy-update-available 'exit 1'

# omarchy-update should hold the lock before snapshotting, so a second update
# cannot even enter its pre-update snapshot.
update_snapshot_marker="$test_tmp/update-snapshot-started"
write_stub omarchy-snapshot 'echo started >"$TEST_MARKER"; sleep 2; exit 0'

OMARCHY_UPDATE_LOGGED=1 TEST_MARKER="$update_snapshot_marker" run_with_lock_env "$ROOT/bin/omarchy-update" -y >"$test_tmp/update-first.out" 2>&1 &
update_pid=$!

for _ in {1..50}; do
  [[ -f $update_snapshot_marker ]] && break
  sleep 0.05
done
[[ -f $update_snapshot_marker ]] || fail "first omarchy-update reached snapshot under lock"

set +e
OMARCHY_UPDATE_LOGGED=1 TEST_MARKER="$test_tmp/update-second-snapshot-started" run_with_lock_env "$ROOT/bin/omarchy-update" -y >"$test_tmp/update-second.out" 2>&1
update_second_status=$?
set -e

wait "$update_pid"

[[ $update_second_status -ne 0 ]] || fail "second omarchy-update exits non-zero while update lock is held"
grep -q "already running" "$test_tmp/update-second.out" || fail "second omarchy-update reports held update lock"
[[ ! -f $test_tmp/update-second-snapshot-started ]] || fail "second omarchy-update did not snapshot while lock was held"
pass "omarchy-update prevents overlapping top-level updates"

# The sleep inhibitor deliberately outlives the step that starts it, so it must
# not inherit the update lock. An update killed before restore_update_inhibitors
# would otherwise leave the inhibitor holding the flock forever, blocking every
# later update and silencing omarchy-migrate-notify, which reads the same lock.
inhibit_pid_file="$test_tmp/inhibit-pid"
keyring_marker="$test_tmp/keyring-started"
write_stub omarchy-snapshot 'exit 0'
write_stub systemd-inhibit 'echo "$$" >"$INHIBIT_PID_FILE"; exec sleep 30'
write_stub omarchy-update-keyring 'echo started >"$TEST_MARKER"; sleep 3; exit 0'

OMARCHY_UPDATE_LOGGED=1 TEST_MARKER="$keyring_marker" INHIBIT_PID_FILE="$inhibit_pid_file" \
  run_with_lock_env "$ROOT/bin/omarchy-update" -y >"$test_tmp/update-inhibit.out" 2>&1 &
inhibit_update_pid=$!

for _ in {1..100}; do
  [[ -s $inhibit_pid_file && -f $keyring_marker ]] && break
  sleep 0.05
done
[[ -s $inhibit_pid_file ]] || fail "update starts its sleep inhibitor"

inhibitor_pid=$(<"$inhibit_pid_file")
kill -0 "$inhibitor_pid" 2>/dev/null || fail "sleep inhibitor is still running when its descriptors are inspected"

lock_target=$(readlink -f "$runtime_dir/omarchy-update.lock")
inhibitor_holds_lock=0
for fd in /proc/"$inhibitor_pid"/fd/*; do
  [[ -e $fd ]] || continue
  [[ $(readlink -f "$fd" 2>/dev/null) == "$lock_target" ]] && inhibitor_holds_lock=1
done

wait "$inhibit_update_pid"

(( inhibitor_holds_lock == 0 )) || fail "update keeps the update lock out of the sleep inhibitor it leaves running"
pass "omarchy-update keeps the update lock out of its sleep inhibitor"

kill -0 "$inhibitor_pid" 2>/dev/null &&
  fail "update waits for its sleep inhibitor to stop before continuing"
pass "omarchy-update waits for its sleep inhibitor to stop"

# Update-owned Stay Awake state must be cleared before the restart helper can
# reboot the machine, rather than relying on an EXIT trap during shutdown.
write_stub omarchy-snapshot 'exit 0'
write_stub omarchy-update-keyring 'exit 0'
write_stub omarchy-toggle-idle '
state_file="$HOME/.local/state/omarchy/indicators/stay-awake"
case "$1" in
  stay-awake)
    mkdir -p "$(dirname "$state_file")"
    touch "$state_file"
    ;;
  allow-idle)
    rm -f "$state_file"
    ;;
esac'
write_stub omarchy-update-restart '
state_file="$HOME/.local/state/omarchy/indicators/stay-awake"
if [[ ${EXPECT_STAY_AWAKE:-0} == "1" ]]; then
  [[ -f $state_file ]]
else
  [[ ! -f $state_file ]]
fi'

rm -f "$test_home/.local/state/omarchy/indicators/stay-awake"
OMARCHY_UPDATE_LOGGED=1 run_with_lock_env "$ROOT/bin/omarchy-update" -y
[[ ! -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "update clears its Stay Awake state before restart handling"

mkdir -p "$test_home/.local/state/omarchy/indicators"
touch "$test_home/.local/state/omarchy/indicators/stay-awake"
OMARCHY_UPDATE_LOGGED=1 EXPECT_STAY_AWAKE=1 run_with_lock_env "$ROOT/bin/omarchy-update" -y
[[ -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "update preserves pre-existing Stay Awake state"
pass "omarchy-update restores only its own Stay Awake state before restart handling"

# Stale cleanup state from a killed update must not override a Stay Awake choice
# the user made afterward.
stay_awake_helper_state="$runtime_dir/omarchy-update-stay-awake"
stay_awake_state="$test_home/.local/state/omarchy/indicators/stay-awake"
mkdir -p "$stay_awake_helper_state" "$(dirname "$stay_awake_state")"
printf '%s\n' "old-update-owner" >"$stay_awake_helper_state/idle-owner"
printf '%s\n' "user-choice" >"$stay_awake_state"

run_with_lock_env "$ROOT/bin/omarchy-update-stay-awake" stop
[[ $(<"$stay_awake_state") == "user-choice" ]] ||
  fail "stale update ownership does not remove a newer Stay Awake choice"
pass "stale update ownership preserves a newer Stay Awake choice"

# A stale PID is safe even if it has been reused by another process.
sleep 30 &
unrelated_pid=$!
unrelated_start_time=$(awk '{ print $22 }' "/proc/$unrelated_pid/stat")
mkdir -p "$stay_awake_helper_state"
printf '%s %s\n' "$unrelated_pid" "$((unrelated_start_time + 1))" >"$stay_awake_helper_state/inhibit-pid"

run_with_lock_env "$ROOT/bin/omarchy-update-stay-awake" stop
kill -0 "$unrelated_pid" 2>/dev/null ||
  fail "stale inhibitor state does not terminate a reused PID"
kill "$unrelated_pid"
wait "$unrelated_pid" 2>/dev/null || true
pass "stale inhibitor state does not terminate a reused PID"
