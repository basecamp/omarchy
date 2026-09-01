#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sleep_monitor="$ROOT/bin/omarchy-system-sleep-monitor"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
mock_omarchy="$tmpdir/omarchy"
producer_pid_file="$tmpdir/producer-pid"
lock_log="$tmpdir/lock-log"
resume_log="$tmpdir/resume-log"
resume_order_log="$tmpdir/resume-order-log"
inhibitor_armed_file="$tmpdir/inhibitor-armed"
mkdir -p "$mock_bin" "$mock_omarchy/bin"

cat >"$mock_bin/systemd-inhibit" <<'SH'
#!/bin/bash

[[ -z ${INHIBITOR_ARMED_FILE:-} ]] || : >"$INHIBITOR_ARMED_FILE"

while [[ $1 == --* ]]; do
  shift
done

exec "$@"
SH

cat >"$mock_bin/dbus-monitor" <<'SH'
#!/bin/bash

echo "$$" >"$PRODUCER_PID_FILE"
printf '   boolean true\n'
exec sleep 30
SH

cat >"$mock_bin/busctl" <<'SH'
#!/bin/bash

printf 'b false\n'
SH

cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash

if [[ -n ${RESUME_ORDER_LOG:-} ]]; then
  if [[ -e ${INHIBITOR_ARMED_FILE:-} ]]; then
    printf 'armed\n' >"$RESUME_ORDER_LOG"
  else
    printf 'unarmed\n' >"$RESUME_ORDER_LOG"
  fi
fi
printf '%s\n' "$*" >>"$RESUME_LOG"
printf 'ok\n'
SH

cat >"$mock_omarchy/bin/omarchy-system-sleep-lock" <<'SH'
#!/bin/bash

echo locked >>"$LOCK_LOG"
SH

chmod +x \
  "$mock_bin/systemd-inhibit" \
  "$mock_bin/dbus-monitor" \
  "$mock_bin/busctl" \
  "$mock_bin/omarchy-shell" \
  "$mock_omarchy/bin/omarchy-system-sleep-lock"
ln -s "$sleep_monitor" "$mock_omarchy/bin/omarchy-system-sleep-monitor"

start_us=${EPOCHREALTIME//[!0-9]/}
OMARCHY_PATH="$mock_omarchy" \
  PATH="$mock_bin:$PATH" \
  PRODUCER_PID_FILE="$producer_pid_file" \
  LOCK_LOG="$lock_log" \
  RESUME_LOG="$resume_log" \
  "$sleep_monitor" --cycle
elapsed_us=$((10#${EPOCHREALTIME//[!0-9]/} - 10#$start_us))

[[ $(<"$lock_log") == "locked" ]] ||
  fail "sleep monitor invokes the lock helper for a sleep event"
pass "sleep monitor invokes the lock helper for a sleep event"

(( elapsed_us < 2000000 )) ||
  fail "sleep monitor releases the inhibitor after locking" "elapsed: ${elapsed_us}us"
pass "sleep monitor releases the inhibitor after locking"

[[ $(<"$resume_log") == "lock resumeFromSleep" ]] ||
  fail "sleep monitor reports the completed resume to the shell"
pass "sleep monitor reports the completed resume to the shell"

producer_pid=$(<"$producer_pid_file")
if kill -0 "$producer_pid" 2>/dev/null; then
  fail "sleep monitor reaps its event producer" "producer still running: $producer_pid"
fi
pass "sleep monitor reaps its event producer"

# Losing the D-Bus event source before PrepareForSleep(true) is not a completed
# sleep cycle and must not synthesize a resume notification.
resume_count=$(wc -l <"$resume_log")
cat >"$mock_bin/dbus-monitor" <<'SH'
#!/bin/bash

echo "$$" >"$PRODUCER_PID_FILE"
exit 1
SH
chmod +x "$mock_bin/dbus-monitor"

if OMARCHY_PATH="$mock_omarchy" \
  PATH="$mock_bin:$PATH" \
  PRODUCER_PID_FILE="$producer_pid_file" \
  LOCK_LOG="$lock_log" \
  RESUME_LOG="$resume_log" \
  "$sleep_monitor" --cycle; then
  fail "sleep monitor rejects a cycle whose event source disappeared"
fi
(( $(wc -l <"$resume_log") == resume_count )) ||
  fail "sleep monitor does not report resume without a sleep event"
pass "sleep monitor rejects a lost event source without reporting resume"

# An unreadable logind state must never be interpreted as resume.
cat >"$mock_bin/busctl" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin/busctl"

OMARCHY_PATH="$mock_omarchy" \
  PATH="$mock_bin:$PATH" \
  PRODUCER_PID_FILE="$producer_pid_file" \
  LOCK_LOG="$lock_log" \
  RESUME_LOG="$resume_log" \
  "$sleep_monitor" &
unknown_state_pid=$!
sleep 0.2
kill "$unknown_state_pid"
wait "$unknown_state_pid" 2>/dev/null || true

(( $(wc -l <"$resume_log") == resume_count )) ||
  fail "sleep monitor keeps resume unknown when logind cannot answer"
pass "sleep monitor keeps resume unknown when logind cannot answer"

cat >"$mock_bin/busctl" <<'SH'
#!/bin/bash
printf 'b false\n'
SH
chmod +x "$mock_bin/busctl"

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
  RESUME_LOG="$resume_log" \
  RESUME_ORDER_LOG="$resume_order_log" \
  INHIBITOR_ARMED_FILE="$inhibitor_armed_file" \
  "$sleep_monitor" &
monitor_pid=$!

for _ in {1..100}; do
  [[ -s $producer_pid_file && -s $resume_order_log ]] && break
  sleep 0.01
done
if [[ ! -s $producer_pid_file ]]; then
  kill "$monitor_pid" 2>/dev/null || true
  wait "$monitor_pid" 2>/dev/null || true
  fail "sleep monitor starts its event producer"
fi

producer_pid=$(<"$producer_pid_file")
kill "$monitor_pid"
wait "$monitor_pid" 2>/dev/null || true

if kill -0 "$producer_pid" 2>/dev/null; then
  kill "$producer_pid" 2>/dev/null || true
  fail "sleep monitor cleans up its producer when terminated" "producer still running: $producer_pid"
fi
pass "sleep monitor cleans up its producer when terminated"

[[ $(<"$resume_order_log") == "armed" ]] ||
  fail "sleep monitor rearms the inhibitor before notifying the shell"
pass "sleep monitor rearms the inhibitor before notifying the shell"
