#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
test_bin="$test_tmp/bin"
call_log="$test_tmp/calls.log"
mkdir -p "$test_bin"
trap 'rm -rf "$test_tmp"' EXIT

cat >"$test_bin/pkill" <<'SH'
#!/bin/bash
printf 'pkill:%s\n' "$*" >>"$OMARCHY_TEST_CALL_LOG"
exit "${OMARCHY_TEST_PKILL_STATUS:-0}"
SH

cat >"$test_bin/setsid" <<'SH'
#!/bin/bash
printf 'setsid:%s\n' "$*" >>"$OMARCHY_TEST_CALL_LOG"
SH

cat >"$test_bin/omarchy-restart-app" <<'SH'
#!/bin/bash
printf 'restart-app:%s\n' "$*" >>"$OMARCHY_TEST_CALL_LOG"
SH

chmod +x "$test_bin"/*

run_restart() {
  : >"$call_log"
  PATH="$test_bin:$PATH" \
  OMARCHY_TEST_CALL_LOG="$call_log" \
  OMARCHY_TEST_PKILL_STATUS="$1" \
    "$ROOT/bin/omarchy-restart-hyprsunset"

  for _ in {1..50}; do
    grep -q '^setsid:' "$call_log" && return
    sleep 0.01
  done
}

run_restart 0
grep -Fx 'pkill:-x hyprsunset' "$call_log" >/dev/null ||
  fail "hyprsunset restart stops the existing process" "$(cat "$call_log")"
grep -Fx 'setsid:hyprsunset' "$call_log" >/dev/null ||
  fail "hyprsunset restart launches the daemon directly" "$(cat "$call_log")"
if grep -q '^restart-app:' "$call_log"; then
  fail "hyprsunset restart does not use the short-lived uwsm app launcher" "$(cat "$call_log")"
fi
pass "hyprsunset restarts directly outside the short-lived uwsm app scope"

run_restart 1
grep -Fx 'setsid:hyprsunset' "$call_log" >/dev/null ||
  fail "hyprsunset starts when no previous process exists" "$(cat "$call_log")"
pass "hyprsunset starts even when no previous process exists"
