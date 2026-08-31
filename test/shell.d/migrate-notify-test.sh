#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$stub_bin" "$test_home"

cat >"$stub_bin/omarchy-migrate" <<'SH'
#!/bin/bash
if [[ ${1:-} == "--pending" && ${OMARCHY_TEST_PENDING_MIGRATIONS:-0} == 1 ]]; then
  echo 200-migration.sh
  exit 0
else
  exit 1
fi
SH
chmod +x "$stub_bin/omarchy-migrate"

# Waiting for the notification server is the notifier's one long pause, so it is
# also where an update can start underneath it. Stand one up from inside the
# wait to prove the notifier re-checks afterwards instead of sending a toast it
# decided to send before the update existed.
cat >"$stub_bin/omarchy-notification-wait" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_LOCK_DURING_WAIT:-0} == 1 ]] || exit 0

lock="$XDG_RUNTIME_DIR/omarchy-update.lock"
held="$lock.held"
rm -f "$held"
: >"$lock"
# Hold the lock through a bash-allocated descriptor rather than `flock <file>
# <command>`: bash marks those close-on-exec, so the holder owns the lock alone
# and killing it releases immediately, with no exec'd child to outlive it. The
# holder blocks for the lock instead of taking it non-blockingly, so it cannot
# lose a startup race and leave the lock unheld.
bash -c 'exec {fd}>"$1"; flock $fd || exit 1; : >"$2"; sleep 60' _ "$lock" "$held" &
echo "$!" >"$OMARCHY_TEST_LOCK_HOLDER_PID"

# Wait on the holder's own signal rather than probing with flock. Probing would
# contend for the very lock we are waiting to see taken.
for _ in {1..200}; do
  [[ -e $held ]] && exit 0
  sleep 0.05
done

echo "stub could not establish the update lock" >&2
exit 1
SH
chmod +x "$stub_bin/omarchy-notification-wait"

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_NOTIFY_SEND:-send} == "fail" ]] && exit 1
printf '%s\n' "$@" >"$OMARCHY_TEST_NOTIFY_ARGS"
SH
chmod +x "$stub_bin/omarchy-notification-send"

runtime_dir="$test_tmp/runtime"
mkdir -p "$runtime_dir"

run_notify() {
  HOME="$test_home" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  OMARCHY_TEST_PENDING_MIGRATIONS="$1" \
  OMARCHY_TEST_NOTIFY_ARGS="$test_tmp/notify-args" \
  OMARCHY_TEST_NOTIFY_SEND="${2:-send}" \
  OMARCHY_TEST_LOCK_DURING_WAIT="${OMARCHY_TEST_LOCK_DURING_WAIT:-0}" \
  OMARCHY_TEST_LOCK_HOLDER_PID="$test_tmp/lock-holder-pid" \
    "$ROOT/bin/omarchy-migrate-notify"
}

notify_args_written() {
  [[ -s $test_tmp/notify-args ]]
}

run_notify 0 >"$test_tmp/not-pending.out" 2>"$test_tmp/not-pending.err"
[[ ! -s $test_tmp/not-pending.out ]] || fail "migration notifier stays quiet on stdout without pending migrations"
[[ ! -s $test_tmp/not-pending.err ]] || fail "migration notifier stays quiet on stderr without pending migrations"
pass "migration notifier ignores users with no pending migrations"

run_notify 1 fail >"$test_tmp/pending.out" 2>"$test_tmp/pending.err"
grep -q 'Omarchy has pending migrations' "$test_tmp/pending.err" || fail "migration notifier explains pending migrations without notification system"
grep -q '200-migration.sh' "$test_tmp/pending.err" || fail "migration notifier lists pending migration names"
pass "migration notifier reports pending migrations"

run_notify 1 >"$test_tmp/notified.out" 2>"$test_tmp/notified.err"
notify_args_written || fail "migration notifier sends a notification for pending migrations"
grep -Fx 'Pending Omarchy Migrations' "$test_tmp/notify-args" >/dev/null || fail "migration notifier uses pending migrations title"
grep -Fx 'Click to run 1 pending migration.' "$test_tmp/notify-args" >/dev/null || fail "migration notifier describes the pending migration"
grep -Fx '' "$test_tmp/notify-args" >/dev/null || fail "migration notifier includes the large-slot glyph"
pass "migration notifier uses the actionable notification format"

# `omarchy update` applies migrations itself, so nothing may notify about them
# while it holds its lock -- a stale trigger firing mid-transaction is exactly
# how the retired omarchy-update-user-notify.path used to interrupt updates.
rm -f "$test_tmp/notify-args"
update_lock="$runtime_dir/omarchy-update.lock"
: >"$update_lock"
exec {update_lock_fd}>"$update_lock"
flock -n "$update_lock_fd" || fail "test could not hold the update lock"

run_notify 1 >"$test_tmp/during-update.out" 2>"$test_tmp/during-update.err"
[[ ! -s $test_tmp/during-update.out ]] || fail "migration notifier stays quiet on stdout during an update"
[[ ! -s $test_tmp/during-update.err ]] || fail "migration notifier stays quiet on stderr during an update"
[[ ! -e $test_tmp/notify-args ]] || fail "migration notifier sends no notification during an update"
pass "migration notifier stays quiet while omarchy update holds its lock"

exec {update_lock_fd}>&-

run_notify 1 >/dev/null 2>&1
notify_args_written &&
  grep -Fx 'Pending Omarchy Migrations' "$test_tmp/notify-args" >/dev/null ||
  fail "migration notifier resumes notifying once the update lock is released"
pass "migration notifier resumes notifying after the update releases its lock"

rm -f "$test_tmp/notify-args"
OMARCHY_TEST_LOCK_DURING_WAIT=1 run_notify 1 >"$test_tmp/raced.out" 2>"$test_tmp/raced.err"
if [[ -s $test_tmp/lock-holder-pid ]]; then
  kill "$(<"$test_tmp/lock-holder-pid")" 2>/dev/null || true
  for _ in {1..200}; do
    flock -n "$runtime_dir/omarchy-update.lock" true 2>/dev/null && break
    sleep 0.05
  done
fi
[[ ! -e $test_tmp/notify-args ]] ||
  fail "migration notifier sends no notification when an update starts while it waits for the notification server"
pass "migration notifier re-checks for an update after waiting for the notification server"

# The guard must never read a lock outside this user's runtime directory: a
# shared /tmp path belongs to whoever created it first, so honouring it would
# let one user silence another user's critical notification.
rm -f "$test_tmp/notify-args" /tmp/omarchy-update.lock
foreign_lock="$test_tmp/foreign/omarchy-update.lock"
mkdir -p "$(dirname "$foreign_lock")"
: >"$foreign_lock"
exec {foreign_lock_fd}>"$foreign_lock"
flock -n "$foreign_lock_fd" || fail "test could not hold the foreign update lock"

run_notify 1 >/dev/null 2>&1
notify_args_written &&
  grep -Fx 'Pending Omarchy Migrations' "$test_tmp/notify-args" >/dev/null ||
  fail "migration notifier ignores update locks outside its own runtime directory"
pass "migration notifier ignores update locks outside its own runtime directory"

exec {foreign_lock_fd}>&-

# The notifier is a Type=oneshot with no start timeout, so it must not stay
# activating until the toast is answered. Handing the click command to the shell
# is what lets it exit immediately -- and what keeps the toast working after the
# shell restart an update performs.
rm -f "$test_tmp/notify-args"
run_notify 1 >/dev/null 2>&1
notify_args_written || fail "migration notifier sends the notification before exiting"
grep -Fx -- '--exec' "$test_tmp/notify-args" >/dev/null ||
  fail "migration notifier attaches the click command to the toast"
grep -Fx 'omarchy-launch-floating-terminal-with-presentation' "$test_tmp/notify-args" >/dev/null &&
  grep -Fx 'omarchy-migrate' "$test_tmp/notify-args" >/dev/null ||
  fail "migration notifier points the click command at omarchy-migrate"
pass "migration notifier lets the shell own the click instead of waiting for it"
