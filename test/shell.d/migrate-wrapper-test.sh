#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_root="$test_tmp/omarchy"
test_home="$test_tmp/home"
stub_bin="$test_tmp/bin"
mkdir -p "$test_root/migrations" "$test_home" "$stub_bin"

cat >"$stub_bin/omarchy-notification-dismiss" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >>"$TEST_DISMISSALS"
SH
chmod +x "$stub_bin/omarchy-notification-dismiss"

cat >"$test_root/migrations/100-migration.sh" <<'SH'
echo migration >>"$TEST_CALLS"
SH

run_migrate() {
  HOME="$test_home" \
  OMARCHY_PATH="$test_root" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_CALLS="$test_tmp/calls" \
  TEST_DISMISSALS="$test_tmp/dismissals" \
    "$ROOT/bin/omarchy-migrate" "$@"
}

: >"$test_tmp/calls"
run_migrate >"$test_tmp/migrate.out"
[[ $(sed -n '1p' "$test_tmp/calls") == "migration" ]] || fail "omarchy-migrate runs pending migrations"
pass "omarchy-migrate runs migrations without force"

grep -Fx 'Omarchy Migrations' "$test_tmp/dismissals" >/dev/null || fail "omarchy-migrate dismisses migration notifications"
pass "omarchy-migrate clears completed migration notifications"

rm -rf "$test_home/.local/state/omarchy/migrations"
run_migrate --pending >"$test_tmp/pending.out"
grep -q '^100-migration\.sh$' "$test_tmp/pending.out" || fail "omarchy-migrate --pending lists pending migrations"
pass "omarchy-migrate --pending lists pending migrations"

run_migrate >"$test_tmp/migrate-second.out"
if run_migrate --pending >"$test_tmp/not-pending.out"; then
  fail "omarchy-migrate --pending exits non-zero without pending migrations"
fi
[[ ! -s $test_tmp/not-pending.out ]] || fail "omarchy-migrate --pending stays quiet without pending migrations"
pass "omarchy-migrate --pending reports no pending migrations"

if run_migrate --force >"$test_tmp/force.out" 2>&1; then
  fail "omarchy-migrate rejects obsolete --force option"
fi
grep -q 'Unknown option: --force' "$test_tmp/force.out" || fail "omarchy-migrate reports obsolete --force option"
pass "omarchy-migrate no longer needs --force"

rm -rf "$test_home/.local/state/omarchy/migrations"
cat >"$test_root/migrations/100-migration.sh" <<'SH'
echo deferred >>"$TEST_CALLS"
exit 75
SH
cat >"$test_root/migrations/200-migration.sh" <<'SH'
echo later >>"$TEST_CALLS"
SH
: >"$test_tmp/calls"
run_migrate >"$test_tmp/deferred.out" || fail "a safely deferred migration aborts the surrounding update"
[[ $(<"$test_tmp/calls") == "deferred" ]] || fail "later migrations run past a deferred predecessor"
[[ ! -e $test_home/.local/state/omarchy/migrations/100-migration.sh ]] || fail "a deferred migration receives a completion marker"
grep -q 'Migration deferred' "$test_tmp/deferred.out" || fail "a deferred migration is not explained"
pass "exit 75 leaves a migration pending, stops its queue, and lets the update continue"

cat >"$test_root/migrations/100-migration.sh" <<'SH'
exit 2
SH
if run_migrate >"$test_tmp/usage-error.out" 2>&1; then
  fail "a migration usage error is normalized as a safe deferral"
fi
pass "conventional exit 2 remains a migration failure"

cat >"$test_root/migrations/100-migration.sh" <<'SH'
exit 9
SH
if run_migrate >"$test_tmp/failed.out" 2>&1; then
  fail "an actual migration failure is normalized as a safe deferral"
fi
pass "migration failures other than exit 75 still fail the update"
