#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
watch_pid=""
events_fd=""

# The watcher forks delayed clamshell retries and the recovery loop. Orphaning
# those would leave them running against a deleted test tree.
# Closing the event stream first would let the watcher exit on its own and
# reparent the recovery loop, which then outlives the test and keeps reloading.
stop_watcher() {
  local child descendants

  if [[ -n $watch_pid ]]; then
    # Note them down before the watcher dies, then kill it first so it never
    # gets to announce the loss of its jobs.
    descendants=$(pgrep -P "$watch_pid" 2>/dev/null || true)
    for child in $descendants; do
      descendants+=" $(pgrep -P "$child" 2>/dev/null || true)"
    done

    kill -KILL "$watch_pid" 2>/dev/null || true
    wait "$watch_pid" 2>/dev/null || true
    for child in $descendants; do
      kill -KILL "$child" 2>/dev/null || true
    done
    watch_pid=""
  fi

  if [[ -n $events_fd ]]; then
    exec {events_fd}>&-
    events_fd=""
  fi

  return 0
}

cleanup() {
  stop_watcher
  rm -rf "$test_tmp"
}
trap cleanup EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

monitors_file="$test_tmp/monitors.json"
reload_log="$test_tmp/reload.log"
recovered="$test_tmp/recovered.json"
events="$test_tmp/events"
modeless_lock="$test_tmp/omarchy-monitor-modeless.lock"
hyprctl_fail="$test_tmp/hyprctl-fails"

# The monitor list lives in a file so a reload can "fix" it mid-run.
cat >"$fake_bin/hyprctl" <<'SH'
#!/bin/bash

# Mirrors are absent from plain `monitors`, so the helper must ask for `all`.
if [[ ${1:-} == "monitors" && ${2:-} == "all" && ${3:-} == "-j" ]]; then
  [[ -f $OMARCHY_TEST_HYPRCTL_FAIL_FLAG ]] && exit 4
  cat "$OMARCHY_TEST_MONITORS_FILE"
elif [[ ${1:-} == "reload" ]]; then
  printf 'reload\n' >>"$OMARCHY_TEST_RELOAD_LOG"
  [[ -f $OMARCHY_TEST_RECOVERED_MONITORS ]] &&
    cp "$OMARCHY_TEST_RECOVERED_MONITORS" "$OMARCHY_TEST_MONITORS_FILE"
fi
SH

cat >"$fake_bin/omarchy-hyprland-reload-guard" <<'SH'
#!/bin/bash

[[ ${1:-} == "paused" && ${OMARCHY_TEST_GUARD_PAUSED:-0} == 1 ]]
SH

cat >"$fake_bin/socat" <<'SH'
#!/bin/bash

exec cat "$OMARCHY_TEST_EVENTS"
SH

# A desktop, so the clamshell half of the watcher stays idle.
cat >"$fake_bin/omarchy-hw-laptop" <<'SH'
#!/bin/bash

exit 1
SH

cat >"$fake_bin/omarchy-hyprland-monitor-clamshell" <<'SH'
#!/bin/bash

exit 0
SH

chmod +x "$fake_bin"/*
ln -s "$ROOT/bin/omarchy-hyprland-monitor-modeless" "$fake_bin/omarchy-hyprland-monitor-modeless"

MODELESS=0
WORKING=1
UNDETERMINED=2

assert_state() {
  local expected="$1" actual=0

  printf '%s' "$2" >"$monitors_file"
  PATH="$fake_bin:$PATH" OMARCHY_TEST_MONITORS_FILE="$monitors_file" \
  OMARCHY_TEST_HYPRCTL_FAIL_FLAG="$hyprctl_fail" \
    "$ROOT/bin/omarchy-hyprland-monitor-modeless" || actual=$?

  (( actual == expected )) || fail "$3" "expected exit $expected, got $actual"
  pass "$3"
}

reloads() {
  wc -l <"$reload_log" | tr -d ' '
}

# A monitor powered off at boot reports an EDID with no modes, so Hyprland
# brings it up at 0x0.
assert_state $MODELESS '[{"name":"DP-1","width":0,"height":0,"disabled":false}]' \
  "a monitor brought up with no mode is detected"

assert_state $MODELESS \
  '[{"name":"DP-1","width":2560,"height":1440,"disabled":false},{"name":"DP-2","width":0,"height":0,"disabled":false}]' \
  "one modeless monitor among working ones is detected"

# Hyprland drops mirrors from `monitors`, so only `monitors all` sees them.
assert_state $MODELESS \
  '[{"name":"HDMI-A-1","width":0,"height":0,"disabled":false,"mirrorOf":"eDP-1"}]' \
  "a modeless mirrored monitor is detected"

assert_state $WORKING '[{"name":"DP-1","width":2560,"height":1440,"disabled":false}]' \
  "a working monitor is not reported as modeless"

# A monitor turned off on purpose is 0x0 too, and re-applying config would fight
# the user over it.
assert_state $WORKING '[{"name":"DP-1","width":0,"height":0,"disabled":true}]' \
  "a deliberately disabled monitor is not reported as modeless"

assert_state $WORKING '[]' "a session with no monitors is not reported as modeless"

# Nothing fires an event for this state, so taking an unanswered query for a
# healthy monitor would leave the screen black for good.
assert_state $UNDETERMINED 'not json' "an unreadable monitor payload cannot say"

printf '%s' '[{"name":"DP-1","width":0,"height":0,"disabled":false}]' >"$monitors_file"
touch "$hyprctl_fail"
unreachable=0
PATH="$fake_bin:$PATH" OMARCHY_TEST_MONITORS_FILE="$monitors_file" \
OMARCHY_TEST_HYPRCTL_FAIL_FLAG="$hyprctl_fail" \
  "$ROOT/bin/omarchy-hyprland-monitor-modeless" || unreachable=$?
rm -f "$hyprctl_fail"
(( unreachable == UNDETERMINED )) || fail "an unreachable compositor cannot say" "got $unreachable"
pass "an unreachable compositor cannot say"

start_watcher() {
  : >"$reload_log"
  rm -f "$events"
  mkfifo "$events"

  PATH="$fake_bin:$PATH" \
  XDG_RUNTIME_DIR="$test_tmp" \
  HYPRLAND_INSTANCE_SIGNATURE=test \
  OMARCHY_TEST_EVENTS="$events" \
  OMARCHY_TEST_MONITORS_FILE="$monitors_file" \
  OMARCHY_TEST_RELOAD_LOG="$reload_log" \
  OMARCHY_TEST_RECOVERED_MONITORS="$recovered" \
  OMARCHY_TEST_GUARD_PAUSED="${1:-0}" \
  OMARCHY_TEST_HYPRCTL_FAIL_FLAG="$hyprctl_fail" \
    "$ROOT/bin/omarchy-hyprland-monitor-watch" &
  watch_pid=$!

  exec {events_fd}>"$events"
}

await_reloads() {
  local waited

  for (( waited = 0; waited < 100; waited++ )); do
    (( $(reloads) >= $1 )) && return 0
    sleep 0.05
  done

  return 1
}

# The watcher reloads until the monitor reports a mode, then stops. It has to
# stop on its own: powering the monitor on fires no event to stop it.
printf '%s' '[{"name":"DP-1","width":0,"height":0,"disabled":false}]' >"$monitors_file"
printf '%s' '[{"name":"DP-1","width":2560,"height":1440,"disabled":false}]' >"$recovered"
start_watcher

await_reloads 1 || fail "a monitor with no mode is reloaded at startup"
sleep 1
(( $(reloads) == 1 )) || fail "recovery stops once the monitor reports a mode" "$(<"$reload_log")"
pass "recovery reloads until the monitor comes back, then stops on its own"

# A reload lands a monitor at 0x0 the same way a boot does, and no hotplug
# follows. The watcher's own recovery reload comes back through this event too,
# which the lock makes a no-op rather than a second loop.
printf '%s' '[{"name":"DP-1","width":0,"height":0,"disabled":false}]' >"$monitors_file"
rm -f "$recovered"
printf 'configreloaded>>\n' >&"$events_fd"

await_reloads 2 || fail "a monitor left at 0x0 by a reload is recovered"
pass "a monitor left at 0x0 by a reload is recovered"

before=$(reloads)
printf 'configreloaded>>\n' >&"$events_fd"
printf 'configreloaded>>\n' >&"$events_fd"
sleep 2
(( $(reloads) - before <= 2 )) ||
  fail "an echoed configreloaded does not stack a second recovery loop" "$before -> $(reloads)"
pass "an echoed configreloaded does not stack a second recovery loop"

stop_watcher

# A package transaction has config half-replaced; reloading into that is exactly
# what the reload guard exists to prevent.
printf '%s' '[{"name":"DP-1","width":0,"height":0,"disabled":false}]' >"$monitors_file"
start_watcher 1

sleep 1
[[ ! -s $reload_log ]] || fail "recovery holds off while the reload guard is paused" "$(<"$reload_log")"
pass "recovery holds off while the reload guard is paused"

stop_watcher

# An unanswerable query is not a healthy monitor. Giving up on one would strand
# the screen, because nothing fires an event to start recovery again.
printf '%s' '[{"name":"DP-1","width":0,"height":0,"disabled":false}]' >"$monitors_file"
rm -f "$recovered"
touch "$hyprctl_fail"
start_watcher

sleep 1
[[ ! -s $reload_log ]] || fail "an unanswerable query does not trigger a reload" "$(<"$reload_log")"
rm -f "$hyprctl_fail"

await_reloads 1 || fail "recovery keeps asking after the compositor could not answer"
pass "recovery keeps asking after the compositor could not answer"

stop_watcher

# An event landing while a worker is on its way out must not be dropped: it is
# the last one that will ever come for this state.
printf '%s' '[{"name":"DP-1","width":2560,"height":1440,"disabled":false}]' >"$monitors_file"
rm -f "$recovered"
start_watcher

# The healthy startup worker has to be gone before the lock stands in for one on
# its way out, or it would hold it here and loop on the 0x0 state below instead.
flock -w 5 "$modeless_lock" -c true || fail "the startup worker released the recovery lock"

flock "$modeless_lock" -c 'sleep 0.5' &
lock_holder=$!
sleep 0.1

printf '%s' '[{"name":"DP-1","width":0,"height":0,"disabled":false}]' >"$monitors_file"
printf 'configreloaded>>\n' >&"$events_fd"
wait "$lock_holder" 2>/dev/null || true

await_reloads 1 || fail "a trigger contending with the recovery lock is not dropped"
pass "a trigger contending with the recovery lock is not dropped"

stop_watcher

# Nothing to recover means nothing to run.
printf '%s' '[{"name":"DP-1","width":2560,"height":1440,"disabled":false}]' >"$monitors_file"
start_watcher

sleep 1
[[ ! -s $reload_log ]] || fail "a healthy machine is left alone" "$(<"$reload_log")"
pass "a healthy machine is never reloaded"

stop_watcher
