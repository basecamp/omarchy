#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sleep_monitor="$ROOT/bin/omarchy-system-sleep-monitor"
tmpdir=$(mktemp -d)
monitor_pid=
cleanup() {
  if [[ -n $monitor_pid ]]; then
    kill "$monitor_pid" 2>/dev/null || true
    wait "$monitor_pid" 2>/dev/null || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

mock_bin="$tmpdir/bin"
mock_omarchy="$tmpdir/omarchy"
producer_pid_file="$tmpdir/producer-pid"
lock_log="$tmpdir/lock-log"
mkdir -p "$mock_bin" "$mock_omarchy/bin"

cat >"$mock_bin/systemd-inhibit" <<'SH'
#!/bin/bash

while [[ $1 == --* ]]; do
  shift
done

exec "$@"
SH

cat >"$mock_bin/busctl" <<'SH'
#!/bin/bash

exit 1
SH

cat >"$mock_bin/dbus-monitor" <<'SH'
#!/bin/bash

echo "$$" >"$PRODUCER_PID_FILE"
printf '   boolean true\n'
exec sleep 30
SH

cat >"$mock_omarchy/bin/omarchy-system-sleep-lock" <<'SH'
#!/bin/bash

echo locked >>"$LOCK_LOG"
SH

chmod +x \
  "$mock_bin/systemd-inhibit" \
  "$mock_bin/busctl" \
  "$mock_bin/dbus-monitor" \
  "$mock_omarchy/bin/omarchy-system-sleep-lock"
ln -s "$sleep_monitor" "$mock_omarchy/bin/omarchy-system-sleep-monitor"

# --inhibited is the process systemd-inhibit wraps; returning after the lock
# is what drops the delay inhibitor.
start_us=${EPOCHREALTIME//[!0-9]/}
OMARCHY_PATH="$mock_omarchy" \
  PATH="$mock_bin:$PATH" \
  PRODUCER_PID_FILE="$producer_pid_file" \
  LOCK_LOG="$lock_log" \
  bash "$sleep_monitor" --inhibited
elapsed_us=$((10#${EPOCHREALTIME//[!0-9]/} - 10#$start_us))

[[ $(<"$lock_log") == "locked" ]] ||
  fail "sleep monitor invokes the lock helper for a sleep event"
pass "sleep monitor invokes the lock helper for a sleep event"

(( elapsed_us < 2000000 )) ||
  fail "sleep monitor releases the inhibitor after locking" "elapsed: ${elapsed_us}us"
pass "sleep monitor releases the inhibitor after locking"

producer_pid=$(<"$producer_pid_file")
if kill -0 "$producer_pid" 2>/dev/null; then
  fail "sleep monitor reaps its event producer" "producer still running: $producer_pid"
fi
pass "sleep monitor reaps its event producer"

# Terminating the monitor must also clean up the producer instead of orphaning
# it under the user systemd instance.
cat >"$mock_bin/dbus-monitor" <<'SH'
#!/bin/bash

sleep 0.1
echo "$$" >"$PRODUCER_PID_FILE"
exec sleep 30
SH
chmod +x "$mock_bin/dbus-monitor"
rm -f "$producer_pid_file"

OMARCHY_PATH="$mock_omarchy" \
  PATH="$mock_bin:$PATH" \
  PRODUCER_PID_FILE="$producer_pid_file" \
  LOCK_LOG="$lock_log" \
  bash "$sleep_monitor" &
monitor_pid=$!

for _ in {1..100}; do
  [[ -s $producer_pid_file ]] && break
  sleep 0.01
done
if [[ ! -s $producer_pid_file ]]; then
  fail "sleep monitor starts its event producer"
fi

producer_pid=$(<"$producer_pid_file")
kill "$monitor_pid"
wait "$monitor_pid" 2>/dev/null || true
monitor_pid=

if kill -0 "$producer_pid" 2>/dev/null; then
  kill "$producer_pid" 2>/dev/null || true
  fail "sleep monitor cleans up its producer when terminated" "producer still running: $producer_pid"
fi
pass "sleep monitor cleans up its producer when terminated"

# A second delay inhibitor while logind is still in PrepareForSleep(true) is
# the "inhibition already running" failure. After one true, wait for false.
inhibit_log="$tmpdir/inhibit-log"
resume_gate="$tmpdir/resume-gate"
emitted_true="$tmpdir/emitted-true"
: >"$inhibit_log"
rm -f "$lock_log" "$resume_gate" "$emitted_true" "$producer_pid_file"

cat >"$mock_bin/systemd-inhibit" <<'SH'
#!/bin/bash

echo inhibit >>"$INHIBIT_LOG"
while [[ $1 == --* ]]; do
  shift
done
exec "$@"
SH

cat >"$mock_bin/dbus-monitor" <<'SH'
#!/bin/bash

echo "$$" >"$PRODUCER_PID_FILE"

if [[ ! -f $EMITTED_TRUE ]]; then
  touch "$EMITTED_TRUE"
  printf '   boolean true\n'
  exec sleep 30
fi

while [[ ! -f $RESUME_GATE ]]; do
  sleep 0.01
done
printf '   boolean false\n'
exec sleep 30
SH

chmod +x "$mock_bin/systemd-inhibit" "$mock_bin/dbus-monitor"

OMARCHY_PATH="$mock_omarchy" \
  PATH="$mock_bin:$PATH" \
  PRODUCER_PID_FILE="$producer_pid_file" \
  LOCK_LOG="$lock_log" \
  INHIBIT_LOG="$inhibit_log" \
  RESUME_GATE="$resume_gate" \
  EMITTED_TRUE="$emitted_true" \
  bash "$sleep_monitor" &
monitor_pid=$!

for _ in {1..200}; do
  [[ -s $lock_log ]] && break
  sleep 0.01
done
[[ -s $lock_log ]] || fail "sleep monitor locks on the first PrepareForSleep true"

# The inhibitor must already have been dropped (and not retaken) while we
# are still waiting for resume.
sleep 0.3
inhibit_count=$(grep -c '^inhibit$' "$inhibit_log" || true)
(( inhibit_count == 1 )) ||
  fail "sleep monitor does not re-take the inhibitor before resume" \
    "inhibits: $inhibit_count"
pass "sleep monitor does not re-take the inhibitor before resume"

touch "$resume_gate"

for _ in {1..200}; do
  inhibit_count=$(grep -c '^inhibit$' "$inhibit_log" || true)
  (( inhibit_count >= 2 )) && break
  sleep 0.01
done
inhibit_count=$(grep -c '^inhibit$' "$inhibit_log" || true)
(( inhibit_count >= 2 )) ||
  fail "sleep monitor re-takes the inhibitor after resume" \
    "inhibits: $inhibit_count"
pass "sleep monitor re-takes the inhibitor after resume"

kill "$monitor_pid"
wait "$monitor_pid" 2>/dev/null || true
monitor_pid=
