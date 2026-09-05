#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command pgrep

test_tmp=$(mktemp -d)
stub_bin="$test_tmp/bin"
curl_log=""
speedtest_pid=""
worker_pids=()
started_pids=()
observed_worker_pids=()

cleanup() {
  local pid

  for pid in ${started_pids+"${started_pids[@]}"} ${observed_worker_pids+"${observed_worker_pids[@]}"}; do
    kill -KILL "$pid" 2>/dev/null || true
  done

  rm -rf "$test_tmp"
}
trap cleanup EXIT

mkdir -p "$stub_bin"

cat >"$stub_bin/ip" <<'SH'
#!/bin/bash
echo "1.1.1.1 via 127.0.0.1 dev lo src 127.0.0.1"
SH

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/jq" <<'SH'
#!/bin/bash
cat
SH

# Stands in for every curl the speed test makes. The endpoint lookup answers
# with fixed targets; traffic requests record the worker that issued them and
# then act out one outcome so each case below can drive a single curl
# behaviour. $PPID is the worker subshell, which is what the assertions track.
cat >"$stub_bin/curl" <<'SH'
#!/bin/bash

if [[ $* == *"api.fast.com"* ]]; then
  printf '%s\n' \
    "https://example.test/speedtest/a" \
    "https://example.test/speedtest/b" \
    "https://example.test/speedtest/c"
  exit 0
fi

printf '%s\t%s\n' "$PPID" "$*" >>"$TEST_CURL_LOG"

max_time=1
previous=""
for argument in "$@"; do
  [[ $previous == "--max-time" ]] && max_time=$argument
  previous=$argument
done

case "${TEST_CURL_MODE:-complete}" in
  cutoff)
    # A link too slow to finish inside the budget: curl's own --max-time
    # cutoff, which reports 28 without the endpoint having failed.
    sleep 0.05
    exit 28
    ;;
  stall)
    # The same cutoff, but with the worker genuinely parked inside curl for
    # the whole budget the way a stalled transfer parks it.
    sleep "$max_time"
    exit 28
    ;;
  refuse)
    exit 7
    ;;
  *)
    sleep 0.05
    ;;
esac
SH

chmod +x "$stub_bin/"*

start_speedtest() {
  local direction="$1"
  shift

  curl_log="$test_tmp/curl-$direction-${#started_pids[@]}.log"
  : >"$curl_log"
  worker_pids=()

  env "$@" TEST_CURL_LOG="$curl_log" PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-network-speedtest" "$direction" \
    >"$test_tmp/stdout" 2>"$test_tmp/stderr" &

  speedtest_pid=$!
  started_pids+=("$speedtest_pid")
}

wait_for_workers() {
  local expected="$1" attempt

  for (( attempt = 0; attempt < 400; attempt++ )); do
    if [[ -s $curl_log ]]; then
      mapfile -t worker_pids < <(cut -f1 "$curl_log" | sort -nu)
      if (( ${#worker_pids[@]} >= expected )); then
        observed_worker_pids+=("${worker_pids[@]}")
        return 0
      fi
    fi
    sleep 0.02
  done

  return 1
}

workers_have_requests_in_flight() {
  local pid

  for pid in "${worker_pids[@]}"; do
    pgrep -P "$pid" >/dev/null 2>&1 || return 1
  done

  return 0
}

wait_for_workers_to_exit() {
  local attempt pid alive

  for (( attempt = 0; attempt < 400; attempt++ )); do
    alive=0
    for pid in "${worker_pids[@]}"; do
      kill -0 "$pid" 2>/dev/null && alive=1
    done
    (( alive == 0 )) && return 0
    sleep 0.02
  done

  return 1
}

wait_for_speedtest_to_exit() {
  local attempt

  for (( attempt = 0; attempt < 400; attempt++ )); do
    kill -0 "$speedtest_pid" 2>/dev/null || return 0
    sleep 0.02
  done

  return 1
}

kill_speedtest() {
  kill -KILL "$speedtest_pid" 2>/dev/null || true
  wait "$speedtest_pid" 2>/dev/null || true
}

speedtest_exit_status() {
  local status=0

  wait "$speedtest_pid" || status=$?
  return "$status"
}

request_count() {
  wc -l <"$curl_log"
}

assert_rejected_setting() {
  local setting="$1"
  local description="$2"
  local status=0

  start_speedtest down "$setting"
  wait_for_speedtest_to_exit || fail "$description" "speed test did not exit"
  wait "$speedtest_pid" || status=$?

  (( status == 2 )) || fail "$description" "exit status: $status"
  [[ ! -s $curl_log ]] || fail "$description" "traffic requests: $(request_count)"
  grep -qF 'must be an integer between' "$test_tmp/stderr" ||
    fail "$description" "$(cat "$test_tmp/stderr")"
  pass "$description"
}

injection_marker="$test_tmp/arithmetic-injection"
assert_rejected_setting \
  "OMARCHY_SPEEDTEST_WORKER_LIFETIME=x[\$(touch $injection_marker)0]" \
  "network speed test rejects an invalid worker lifetime"
[[ ! -e $injection_marker ]] || fail "network speed test does not evaluate an invalid worker lifetime"
pass "network speed test does not evaluate an invalid worker lifetime"

assert_rejected_setting \
  "OMARCHY_SPEEDTEST_WORKER_LIFETIME=0" \
  "network speed test rejects a zero worker lifetime"
assert_rejected_setting \
  "OMARCHY_SPEEDTEST_WORKER_LIFETIME=-1" \
  "network speed test rejects a negative worker lifetime"
assert_rejected_setting \
  "OMARCHY_SPEEDTEST_WORKER_LIFETIME=31" \
  "network speed test rejects an excessive worker lifetime"
assert_rejected_setting \
  "OMARCHY_SPEEDTEST_REQUEST_TIMEOUT=6" \
  "network speed test rejects an excessive request timeout"

start_speedtest down OMARCHY_SPEEDTEST_REQUEST_TIMEOUT=3
wait_for_workers 8 || fail "network speed test starts eight traffic workers" "$(cat "$curl_log")"
pass "network speed test starts eight traffic workers"

grep -q -- '--max-time 3' "$curl_log" ||
  fail "network speed test bounds each traffic request" "$(cat "$curl_log")"
pass "network speed test bounds each traffic request"

kill_speedtest
wait_for_workers_to_exit || fail "network speed test workers exit when their parent disappears"
pass "network speed test workers exit when their parent disappears"

# The parent check only runs between requests, so a worker parked inside a
# transfer notices nothing until curl returns. --max-time is what guarantees it
# returns at all, and this is the case that guarantee exists for.
start_speedtest down TEST_CURL_MODE=stall OMARCHY_SPEEDTEST_REQUEST_TIMEOUT=1
wait_for_workers 8 || fail "network speed test workers park inside a stalled request" "$(cat "$curl_log")"
workers_have_requests_in_flight || fail "network speed test workers park inside a stalled request"
pass "network speed test workers park inside a stalled request"

kill_speedtest
wait_for_workers_to_exit ||
  fail "network speed test workers stop after a stalled request when their parent disappears"
pass "network speed test workers stop after a stalled request when their parent disappears"

# An orphan that outlives its parent check still has to expire, so the lifetime
# is the backstop. Watched here through the parent, which cannot outlive its
# own workers.
start_speedtest down OMARCHY_SPEEDTEST_WORKER_LIFETIME=1
wait_for_workers 8 || fail "network speed test workers expire on their own lifetime" "$(cat "$curl_log")"
wait_for_speedtest_to_exit || fail "network speed test workers expire on their own lifetime"
speedtest_exit_status || fail "network speed test workers expire on their own lifetime" "$(cat "$test_tmp/stderr")"
pass "network speed test workers expire on their own lifetime"

# Every request on a slow link ends at the --max-time cutoff. Retiring the
# worker there would end the whole test one request in.
start_speedtest down TEST_CURL_MODE=cutoff OMARCHY_SPEEDTEST_WORKER_LIFETIME=2
wait_for_workers 8 || fail "network speed test keeps working after a request hits its timeout" "$(cat "$curl_log")"
wait_for_speedtest_to_exit || fail "network speed test keeps working after a request hits its timeout"
(( $(request_count) >= 16 )) ||
  fail "network speed test keeps working after a request hits its timeout" "requests: $(request_count)"
pass "network speed test keeps working after a request hits its timeout"

# The flip side: a real curl error is still fatal to the worker, so a dead
# endpoint does not spin for the whole lifetime.
start_speedtest down TEST_CURL_MODE=refuse
wait_for_workers 8 || fail "network speed test retires a worker whose request fails" "$(cat "$curl_log")"
wait_for_speedtest_to_exit || fail "network speed test retires a worker whose request fails"
(( $(request_count) == 8 )) ||
  fail "network speed test retires a worker whose request fails" "requests: $(request_count)"
pass "network speed test retires a worker whose request fails"

start_speedtest up OMARCHY_SPEEDTEST_REQUEST_TIMEOUT=3
wait_for_workers 8 || fail "network speed test starts eight upload workers" "$(cat "$curl_log")"
pass "network speed test starts eight upload workers"

grep -q -- '-X POST' "$curl_log" || fail "network speed test uploads its own payload" "$(cat "$curl_log")"
grep -q -- '--data-binary @-' "$curl_log" || fail "network speed test uploads its own payload" "$(cat "$curl_log")"
pass "network speed test uploads its own payload"

grep -q -- '--max-time 3' "$curl_log" ||
  fail "network speed test bounds each upload request" "$(cat "$curl_log")"
pass "network speed test bounds each upload request"

kill_speedtest
wait_for_workers_to_exit || fail "network speed test upload workers exit when their parent disappears"
pass "network speed test upload workers exit when their parent disappears"
