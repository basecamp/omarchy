#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_root="$test_tmp/omarchy"
test_home="$test_tmp/home"
system_state="$test_tmp/system-state"
mkdir -p "$test_root/migrations/system" "$test_root/migrations/user" "$test_home" "$system_state"

cat >"$test_root/migrations/system/100-system.sh" <<'SH'
[[ $OMARCHY_PATH == "$TEST_EXPECTED_OMARCHY_PATH" ]]
echo system >>"$TEST_CALLS"
SH
cat >"$test_root/migrations/user/200-user.sh" <<'SH'
[[ $OMARCHY_PATH == "$TEST_EXPECTED_OMARCHY_PATH" ]]
echo user >>"$TEST_CALLS"
SH

calls="$test_tmp/calls"

if ! HOME="$test_home" OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-migrate-user" --pending >"$test_tmp/user-pending.out"; then
  fail "user migration runner reports pending migrations before state exists"
fi
grep -q '^200-user\.sh$' "$test_tmp/user-pending.out" || fail "user migration runner lists pending migration filename"
pass "user migration runner detects pending migrations"

HOME="$test_home" \
OMARCHY_PATH="$test_root" \
TEST_EXPECTED_OMARCHY_PATH="$test_root" \
TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate-user" >"$test_tmp/user-first.out"
[[ $(grep -c '^user$' "$calls") -eq 1 ]] || fail "user migration runner runs user migrations"
! grep -q '^system$' "$calls" || fail "user migration runner does not run system migrations"
[[ -f $test_home/.local/state/omarchy/migrations/user/200-user.sh ]] || fail "user migration runner records user migration marker"
pass "user migration runner only runs user migrations"

HOME="$test_home" \
OMARCHY_PATH="$test_root" \
TEST_EXPECTED_OMARCHY_PATH="$test_root" \
TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate-user" >"$test_tmp/user-second.out"
[[ $(grep -c '^user$' "$calls") -eq 1 ]] || fail "user migration runner skips completed migrations"
pass "user migration runner skips completed migrations"

if HOME="$test_home" OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-migrate-user" --pending >"$test_tmp/user-not-pending.out"; then
  fail "user migration runner reports no pending migrations after state exists"
fi
pass "user migration runner detects no pending migrations"

if ! OMARCHY_PATH="$test_root" OMARCHY_SYSTEM_MIGRATION_STATE="$system_state" "$ROOT/bin/omarchy-migrate-system" --pending >"$test_tmp/system-pending.out"; then
  fail "system migration runner reports pending migrations before state exists"
fi
grep -q '^100-system\.sh$' "$test_tmp/system-pending.out" || fail "system migration runner lists pending migration filename"

OMARCHY_PATH="$test_root" \
OMARCHY_SYSTEM_MIGRATION_STATE="$system_state" \
TEST_EXPECTED_OMARCHY_PATH="$test_root" \
TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate-system" >"$test_tmp/system-first.out"
[[ $(grep -c '^system$' "$calls") -eq 1 ]] || fail "system migration runner runs system migrations"
[[ -f $system_state/100-system.sh ]] || fail "system migration runner records system migration marker"
pass "system migration runner only runs system migrations"

if OMARCHY_PATH="$test_root" OMARCHY_SYSTEM_MIGRATION_STATE="$system_state" "$ROOT/bin/omarchy-migrate-system" --pending >"$test_tmp/system-not-pending.out"; then
  fail "system migration runner reports no pending migrations after state exists"
fi
pass "system migration runner detects no pending migrations"

failure_root="$test_tmp/failure-omarchy"
failure_home="$test_tmp/failure-home"
failure_system_state="$test_tmp/failure-system-state"
mkdir -p "$failure_root/migrations/system" "$failure_root/migrations/user" "$failure_home" "$failure_system_state"

cat >"$failure_root/migrations/user/300-fail-user.sh" <<'SH'
echo user-before-fail >>"$TEST_CALLS"
false
echo user-after-fail >>"$TEST_CALLS"
SH

set +e
HOME="$failure_home" \
OMARCHY_PATH="$failure_root" \
TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate-user" >"$test_tmp/user-failure.out" 2>"$test_tmp/user-failure.err"
user_failure_status=$?
set -e
[[ $user_failure_status -ne 0 ]] || fail "user migration runner exits non-zero when a migration fails"
[[ ! -f $failure_home/.local/state/omarchy/migrations/user/300-fail-user.sh ]] || fail "user migration runner does not mark failed migration complete"
grep -q '^user-before-fail$' "$calls" || fail "user migration runner started failing migration"
! grep -q '^user-after-fail$' "$calls" || fail "user migration runner stops failing migration under strict mode"
pass "user migration runner does not mark failed migrations complete"

cat >"$failure_root/migrations/system/400-fail-system.sh" <<'SH'
echo system-before-fail >>"$TEST_CALLS"
false
echo system-after-fail >>"$TEST_CALLS"
SH

set +e
OMARCHY_PATH="$failure_root" \
OMARCHY_SYSTEM_MIGRATION_STATE="$failure_system_state" \
TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate-system" >"$test_tmp/system-failure.out" 2>"$test_tmp/system-failure.err"
system_failure_status=$?
set -e
[[ $system_failure_status -ne 0 ]] || fail "system migration runner exits non-zero when a migration fails"
[[ ! -f $failure_system_state/400-fail-system.sh ]] || fail "system migration runner does not mark failed migration complete"
grep -q '^system-before-fail$' "$calls" || fail "system migration runner started failing migration"
! grep -q '^system-after-fail$' "$calls" || fail "system migration runner stops failing migration under strict mode"
pass "system migration runner does not mark failed migrations complete"
