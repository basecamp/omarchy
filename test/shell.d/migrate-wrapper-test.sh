#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$stub_bin" "$test_home"

cat >"$stub_bin/omarchy-migrate-system" <<'SH'
#!/bin/bash
if [[ ${1:-} == "--pending" ]]; then
  [[ ${OMARCHY_TEST_PENDING_SYSTEM:-1} == 1 ]] || exit 1
  echo 100-system.sh
  exit 0
fi
echo system >>"$TEST_CALLS"
SH
chmod +x "$stub_bin/omarchy-migrate-system"

cat >"$stub_bin/omarchy-migrate-user" <<'SH'
#!/bin/bash
if [[ ${1:-} == "--pending" ]]; then
  [[ ${OMARCHY_TEST_PENDING_USER:-1} == 1 ]] || exit 1
  echo 200-user.sh
  exit 0
fi
echo user >>"$TEST_CALLS"
SH
chmod +x "$stub_bin/omarchy-migrate-user"

run_migrate() {
  HOME="$test_home" \
  PATH="$stub_bin:$PATH" \
  TEST_CALLS="$test_tmp/calls" \
    "$ROOT/bin/omarchy-migrate" "$@"
}

: >"$test_tmp/calls"
run_migrate >"$test_tmp/migrate.out"
[[ $(sed -n '1p' "$test_tmp/calls") == "system" ]] || fail "omarchy-migrate runs system migrations first"
[[ $(sed -n '2p' "$test_tmp/calls") == "user" ]] || fail "omarchy-migrate runs user migrations second"
[[ $(wc -l <"$test_tmp/calls") -eq 2 ]] || fail "omarchy-migrate only delegates to system and user migration runners"
pass "omarchy-migrate runs system and user migrations without force"

run_migrate --pending >"$test_tmp/pending-all.out"
grep -q '^system/100-system\.sh$' "$test_tmp/pending-all.out" || fail "omarchy-migrate --pending lists pending system migrations"
grep -q '^user/200-user\.sh$' "$test_tmp/pending-all.out" || fail "omarchy-migrate --pending lists pending user migrations"
pass "omarchy-migrate --pending lists all pending migrations"

run_migrate --pending user >"$test_tmp/pending-user.out"
grep -q '^user/200-user\.sh$' "$test_tmp/pending-user.out" || fail "omarchy-migrate --pending user lists user migrations"
! grep -q '^system/' "$test_tmp/pending-user.out" || fail "omarchy-migrate --pending user omits system migrations"
pass "omarchy-migrate --pending user scopes pending output"

if OMARCHY_TEST_PENDING_SYSTEM=0 OMARCHY_TEST_PENDING_USER=0 run_migrate --pending >"$test_tmp/not-pending.out"; then
  fail "omarchy-migrate --pending exits non-zero without pending migrations"
fi
[[ ! -s $test_tmp/not-pending.out ]] || fail "omarchy-migrate --pending stays quiet without pending migrations"
pass "omarchy-migrate --pending reports no pending migrations"

if run_migrate --force >"$test_tmp/force.out" 2>&1; then
  fail "omarchy-migrate rejects obsolete --force option"
fi
grep -q 'Unknown option: --force' "$test_tmp/force.out" || fail "omarchy-migrate reports obsolete --force option"
pass "omarchy-migrate no longer needs --force"
