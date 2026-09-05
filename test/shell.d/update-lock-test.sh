#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
linger_pids=()
trap 'for pid in "${linger_pids[@]}"; do kill "$pid" 2>/dev/null || true; done; rm -rf "$test_tmp"' EXIT

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
  pkexec \
  systemd-inhibit \
  omarchy-update-pkg-prune \
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
write_stub pkexec 'exec "$@"'

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

if (( EUID != 0 )); then
  sudo_log="$test_tmp/sudo.log"
  pkexec_marker="$test_tmp/pkexec-used"
  terminal_inhibit_pid_file="$test_tmp/terminal-inhibit-pid"
  write_stub sudo '
printf "%s\n" "$*" >>"$SUDO_LOG"
if [[ $1 == "-v" ]]; then
  exit 0
fi
exec "$@"'
  write_stub pkexec 'touch "$PKEXEC_MARKER"; exec "$@"'

  # start leaves the inhibitor running on purpose, but script tears the pty down
  # the moment its command returns, which SIGHUPs that inhibitor before it can
  # exec. Keep the session open from the inside until the stub has logged.
  terminal_driver="$test_tmp/terminal-stay-awake"
  cat >"$terminal_driver" <<'SH'
#!/bin/bash
omarchy-update-stay-awake start
for _ in {1..200}; do
  grep -q '^systemd-inhibit ' "$SUDO_LOG" && break
  sleep 0.05
done
SH
  chmod +x "$terminal_driver"

  SUDO_LOG="$sudo_log" PKEXEC_MARKER="$pkexec_marker" INHIBIT_PID_FILE="$terminal_inhibit_pid_file" \
    run_with_lock_env script -qefc "$terminal_driver" /dev/null >/dev/null

  grep -qx -- '-v' "$sudo_log" || fail "terminal sleep inhibition validates sudo in the foreground"
  grep -q '^systemd-inhibit ' "$sudo_log" || fail "terminal sleep inhibition runs through sudo"
  [[ ! -e $pkexec_marker ]] || fail "terminal sleep inhibition does not use pkexec"
  run_with_lock_env "$ROOT/bin/omarchy-update-stay-awake" stop
  pass "terminal updates use sudo instead of Polkit for sleep inhibition"
fi

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

# The lock wrapper used to exec the update, so every child inherited the flock.
# Flutter's adb daemonizes onto user systemd and kept it after the update
# exited; the next omarchy update then reported one was already running (#8077).
linger="$test_tmp/linger"
daemon_pid_file="$test_tmp/daemon.pid"
cat >"$linger" <<'SH'
#!/bin/bash
printf '%s\n' "$$" >"$1"
exec sleep 30
SH
chmod +x "$linger"

lock_held_by_pid() {
  local pid="$1"
  local lock_target="$2"
  local fd

  for fd in /proc/"$pid"/fd/*; do
    [[ -e $fd ]] || continue
    [[ $(readlink -f "$fd" 2>/dev/null) == "$lock_target" ]] && return 0
  done
  return 1
}

run_with_lock_env "$ROOT/bin/omarchy-update-lock" run \
  bash -c 'setsid -f "$1" "$2"' bash "$linger" "$daemon_pid_file" ||
  fail "omarchy-update-lock run succeeds while spawning a daemonized child"

for _ in {1..50}; do
  [[ -s $daemon_pid_file ]] && break
  sleep 0.02
done
[[ -s $daemon_pid_file ]] || fail "daemonized child recorded its pid"
linger_pid=$(<"$daemon_pid_file")
linger_pids+=("$linger_pid")
kill -0 "$linger_pid" 2>/dev/null || fail "daemonized child outlives omarchy-update-lock"

lock_target=$(readlink -f "$runtime_dir/omarchy-update.lock")
lock_held_by_pid "$linger_pid" "$lock_target" &&
  fail "daemonized child does not inherit the update lock descriptor"

flock -n "$runtime_dir/omarchy-update.lock" true ||
  fail "update lock is released after omarchy-update-lock exits despite a living daemonized child"

run_with_lock_env "$ROOT/bin/omarchy-update-lock" run true ||
  fail "a later omarchy-update-lock run acquires the lock after a daemonized child was left behind"
pass "omarchy-update-lock does not leak its flock to daemonized children"

# Same leak through the real update pipeline, via the AUR step that starts adb.
write_stub omarchy-snapshot 'exit 0'
write_stub omarchy-update-keyring 'exit 0'
write_stub omarchy-update-restart 'exit 0'
write_stub systemd-inhibit 'exec sleep infinity'
rm -f "$daemon_pid_file" "$test_home/.local/state/omarchy/indicators/stay-awake"
write_stub omarchy-update-aur-pkgs 'setsid -f "$LINGER" "$DAEMON_PID_FILE"'

OMARCHY_UPDATE_LOGGED=1 LINGER="$linger" DAEMON_PID_FILE="$daemon_pid_file" \
  run_with_lock_env "$ROOT/bin/omarchy-update" -y ||
  fail "omarchy-update succeeds when the AUR step daemonizes a child"

for _ in {1..50}; do
  [[ -s $daemon_pid_file ]] && break
  sleep 0.02
done
[[ -s $daemon_pid_file ]] || fail "AUR step recorded a daemonized child"
update_linger_pid=$(<"$daemon_pid_file")
linger_pids+=("$update_linger_pid")
kill -0 "$update_linger_pid" 2>/dev/null || fail "AUR daemonized child outlives omarchy-update"

lock_target=$(readlink -f "$runtime_dir/omarchy-update.lock")
lock_held_by_pid "$update_linger_pid" "$lock_target" &&
  fail "AUR daemonized child does not inherit the update lock descriptor"

flock -n "$runtime_dir/omarchy-update.lock" true ||
  fail "update lock is released after omarchy-update exits despite a living AUR daemon"

write_stub omarchy-update-aur-pkgs 'exit 0'
OMARCHY_UPDATE_LOGGED=1 run_with_lock_env "$ROOT/bin/omarchy-update" -y ||
  fail "a later omarchy-update runs after a previous AUR step daemonized a child"
pass "omarchy-update does not leak its lock through AUR daemons"

# held() is how omarchy-update avoids re-acquiring the lock after the wrapper
# starts it. It must be true only inside that child, never because a leftover
# daemon still has an open descriptor.
held_inside="$test_tmp/held-inside"
run_with_lock_env "$ROOT/bin/omarchy-update-lock" run \
  bash -c 'omarchy-update-lock held && echo yes >"$1" || echo no >"$1"' bash "$held_inside" ||
  fail "omarchy-update-lock run with a held check exits 0"
[[ $(<"$held_inside") == "yes" ]] || fail "omarchy-update-lock held is true inside the locked child"

if run_with_lock_env "$ROOT/bin/omarchy-update-lock" held; then
  fail "omarchy-update-lock held is false outside a locked child"
fi
pass "omarchy-update-lock held is only true for the locked child"
