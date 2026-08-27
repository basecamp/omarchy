#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq
require_command pkill
require_command python3

test_tmp=$(mktemp -d)
test_bin="$test_tmp/bin"
child_file="$test_tmp/speedtest.pid"
curl_pids="$test_tmp/curl-pids"
parent_pid=""
speedtest_pid=""
mkdir -p "$test_bin"
mkdir -p "$test_tmp/net/lo/statistics"
: >"$curl_pids"
printf '0\n' >"$test_tmp/net/lo/statistics/rx_bytes"
printf '0\n' >"$test_tmp/net/lo/statistics/tx_bytes"

cleanup_test() {
  local pid
  [[ -n $parent_pid ]] && kill "$parent_pid" 2>/dev/null || true
  [[ -n $speedtest_pid ]] && kill "$speedtest_pid" 2>/dev/null || true
  while IFS= read -r pid; do
    [[ -n $pid ]] && kill "$pid" 2>/dev/null || true
  done <"$curl_pids"
  rm -rf "$test_tmp"
}
trap cleanup_test EXIT

cat >"$test_bin/ip" <<'SH'
#!/bin/bash
printf '1.1.1.1 via 127.0.0.1 dev lo\n'
SH

cat >"$test_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ ${1:-} == "curl" ]]
SH

cat >"$test_bin/curl" <<'SH'
#!/usr/bin/env python3
import os
import signal
import sys

if any(arg.startswith("https://api.fast.com/") for arg in sys.argv[1:]):
  print('{"targets":[{"url":"https://speedtest.invalid/payload"}]}')
  raise SystemExit(0)

with open(os.environ["OMARCHY_TEST_CURL_PIDS"], "a") as log:
  print(os.getpid(), file=log, flush=True)
signal.pause()
SH

cat >"$test_bin/speedtest-parent" <<'SH'
#!/bin/bash

"$OMARCHY_TEST_SPEEDTEST" down >"$OMARCHY_TEST_OUTPUT" 2>"$OMARCHY_TEST_ERROR" &
child=$!
printf '%s\n' "$child" >"$OMARCHY_TEST_CHILD_FILE"
wait "$child"
SH

chmod +x "$test_bin"/*

PATH="$test_bin:$PATH" \
OMARCHY_TEST_SPEEDTEST="$ROOT/bin/omarchy-network-speedtest" \
OMARCHY_TEST_CHILD_FILE="$child_file" \
OMARCHY_TEST_CURL_PIDS="$curl_pids" \
OMARCHY_TEST_OUTPUT="$test_tmp/output" \
OMARCHY_TEST_ERROR="$test_tmp/error" \
OMARCHY_NETWORK_DEVICES_PATH="$test_tmp/net" \
  "$test_bin/speedtest-parent" &
parent_pid=$!

for _ in {1..100}; do
  [[ -s $child_file ]] && (( $(wc -l <"$curl_pids") >= 8 )) && break
  sleep 0.05
done

[[ -s $child_file ]] || fail "speed test starts under its launcher" "$(cat "$test_tmp/error" 2>/dev/null || true)"
(( $(wc -l <"$curl_pids") >= 8 )) || fail "speed test starts traffic workers" "$(cat "$test_tmp/error" 2>/dev/null || true)"
speedtest_pid=$(<"$child_file")
actual_parent=$(ps -o ppid= -p "$speedtest_pid" | awk '{print $1}')
[[ $actual_parent == "$parent_pid" ]] ||
  fail "speed test is a child of the simulated launcher" "expected $parent_pid, got $actual_parent"

# Model Quickshell crashing without giving its Process children a signal.
kill -KILL "$parent_pid"
wait "$parent_pid" 2>/dev/null || true
parent_pid=""

for _ in {1..100}; do
  if ! kill -0 "$speedtest_pid" 2>/dev/null; then
    all_curls_stopped=1
    while IFS= read -r pid; do
      if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
        all_curls_stopped=0
        break
      fi
    done <"$curl_pids"
    (( all_curls_stopped )) && break
  fi
  sleep 0.05
done

if kill -0 "$speedtest_pid" 2>/dev/null; then
  fail "speed test exits when its launcher dies" "curl pids: $(tr '\n' ' ' <"$curl_pids")
$(ps -axo pid,ppid,stat,command | grep -E "(^ *PID|$speedtest_pid|omarchy-network-speedtest)" | grep -v grep)"
fi
while IFS= read -r pid; do
  if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
    fail "speed test stops traffic processes when its launcher dies" "$(ps -o pid,ppid,stat,command -p "$pid")"
  fi
done <"$curl_pids"
pass "speed test stops itself and its traffic processes when its launcher dies"
