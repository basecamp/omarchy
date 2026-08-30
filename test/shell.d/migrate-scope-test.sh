#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_root="$test_tmp/omarchy"
test_home="$test_tmp/home"
mkdir -p "$test_root/migrations" "$test_home"

cat >"$test_root/migrations/100-first.sh" <<'SH'
[[ $OMARCHY_PATH == "$TEST_EXPECTED_OMARCHY_PATH" ]]
echo first >>"$TEST_CALLS"
SH
cat >"$test_root/migrations/200-second.sh" <<'SH'
[[ $OMARCHY_PATH == "$TEST_EXPECTED_OMARCHY_PATH" ]]
echo second >>"$TEST_CALLS"
SH

calls="$test_tmp/calls"

if ! HOME="$test_home" OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-migrate" --pending >"$test_tmp/pending.out"; then
  fail "migration runner reports pending migrations before state exists"
fi
grep -q '^100-first\.sh$' "$test_tmp/pending.out" || fail "migration runner lists first pending migration filename"
grep -q '^200-second\.sh$' "$test_tmp/pending.out" || fail "migration runner lists second pending migration filename"
pass "migration runner detects pending migrations"

HOME="$test_home" \
OMARCHY_PATH="$test_root" \
TEST_EXPECTED_OMARCHY_PATH="$test_root" \
TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/first-run.out"
[[ $(sed -n '1p' "$calls") == "first" ]] || fail "migration runner runs first migration"
[[ $(sed -n '2p' "$calls") == "second" ]] || fail "migration runner runs second migration"
[[ -f $test_home/.local/state/omarchy/migrations/100-first.sh ]] || fail "migration runner records first migration marker"
[[ -f $test_home/.local/state/omarchy/migrations/200-second.sh ]] || fail "migration runner records second migration marker"
pass "migration runner runs all migrations"

HOME="$test_home" \
OMARCHY_PATH="$test_root" \
TEST_EXPECTED_OMARCHY_PATH="$test_root" \
TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/second-run.out"
[[ $(wc -l <"$calls") -eq 2 ]] || fail "migration runner skips completed migrations"
pass "migration runner skips completed migrations"

if HOME="$test_home" OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-migrate" --pending >"$test_tmp/not-pending.out"; then
  fail "migration runner reports no pending migrations after state exists"
fi
pass "migration runner detects no pending migrations"

failure_root="$test_tmp/failure-omarchy"
failure_home="$test_tmp/failure-home"
mkdir -p "$failure_root/migrations" "$failure_home"

cat >"$failure_root/migrations/500-fail.sh" <<'SH'
echo before-fail >>"$TEST_CALLS"
false
echo after-fail >>"$TEST_CALLS"
SH

set +e
HOME="$failure_home" \
OMARCHY_PATH="$failure_root" \
TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/failure.out" 2>"$test_tmp/failure.err"
failure_status=$?
set -e
[[ $failure_status -ne 0 ]] || fail "migration runner exits non-zero when a migration fails"
[[ ! -f $failure_home/.local/state/omarchy/migrations/500-fail.sh ]] || fail "migration runner does not mark failed migration complete"
grep -q '^before-fail$' "$calls" || fail "migration runner started failing migration"
! grep -q '^after-fail$' "$calls" || fail "migration runner stops failing migration under strict mode"
pass "migration runner does not mark failed migrations complete"

deferred_root="$test_tmp/deferred-omarchy"
deferred_home="$test_tmp/deferred-home"
deferred_calls="$test_tmp/deferred-calls"
mkdir -p "$deferred_root/migrations" "$deferred_home"

cat >"$deferred_root/migrations/100-deferred.sh" <<'SH'
echo deferred >>"$TEST_CALLS"
printf '%s\n' "$OMARCHY_MIGRATION_DEFER_TOKEN" >"$OMARCHY_MIGRATION_DEFER_FILE"
exit 75
SH
cat >"$deferred_root/migrations/200-after.sh" <<'SH'
echo after >>"$TEST_CALLS"
SH

HOME="$deferred_home" \
OMARCHY_PATH="$deferred_root" \
TEST_CALLS="$deferred_calls" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/deferred.out"

grep -q '^deferred$' "$deferred_calls" || fail "migration runner starts a deferred migration"
grep -q '^after$' "$deferred_calls" || fail "migration runner continues after a deferred migration"
[[ ! -f $deferred_home/.local/state/omarchy/migrations/100-deferred.sh ]] ||
  fail "migration runner leaves a deferred migration pending"
[[ -f $deferred_home/.local/state/omarchy/migrations/200-after.sh ]] ||
  fail "migration runner records a later successful migration"
grep -q 'was deferred and will be retried later' "$test_tmp/deferred.out" ||
  fail "migration runner reports a deferred migration"
pass "migration runner leaves exit-75 migrations pending and continues the queue"

HOME="$deferred_home" OMARCHY_PATH="$deferred_root" \
  "$ROOT/bin/omarchy-migrate" --pending >"$test_tmp/deferred-pending.out"
grep -q '^100-deferred\.sh$' "$test_tmp/deferred-pending.out" ||
  fail "migration runner still reports a deferred migration as pending"
! grep -q '^200-after\.sh$' "$test_tmp/deferred-pending.out" ||
  fail "migration runner does not report the completed later migration as pending"
pass "migration runner reports only the deferred migration as pending"

raw_75_root="$test_tmp/raw-75-omarchy"
raw_75_home="$test_tmp/raw-75-home"
raw_75_calls="$test_tmp/raw-75-calls"
mkdir -p "$raw_75_root/migrations" "$raw_75_home"

cat >"$raw_75_root/migrations/100-child-tempfail.sh" <<'SH'
echo child-tempfail >>"$TEST_CALLS"
bash -c 'exit 75'
SH
cat >"$raw_75_root/migrations/200-after.sh" <<'SH'
echo after-tempfail >>"$TEST_CALLS"
SH

set +e
HOME="$raw_75_home" \
OMARCHY_PATH="$raw_75_root" \
TEST_CALLS="$raw_75_calls" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/raw-75.out" 2>"$test_tmp/raw-75.err"
raw_75_status=$?
set -e

(( raw_75_status == 75 )) ||
  fail "migration runner preserves an unmarked child exit 75" "status=$raw_75_status"
grep -q '^child-tempfail$' "$raw_75_calls" || fail "migration runner starts the exit-75 child"
! grep -q '^after-tempfail$' "$raw_75_calls" || fail "migration runner stops after an unmarked exit 75"
[[ ! -f $raw_75_home/.local/state/omarchy/migrations/100-child-tempfail.sh ]] ||
  fail "migration runner leaves an unmarked exit-75 migration incomplete"
pass "migration runner does not mistake a child EX_TEMPFAIL for intentional deferral"
