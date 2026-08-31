#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

if [[ ${OMARCHY_MIGRATE_WRAPPER_NS:-0} != 1 ]]; then
  exec unshare --user --map-root-user --mount \
    env OMARCHY_MIGRATE_WRAPPER_NS=1 bash "$0"
fi

mount -t tmpfs -o mode=0755 tmpfs /run
test_tmp=$(mktemp -d -p /run omarchy-migrate-wrapper.XXXXXXXX)
cat >"$test_tmp/sudo" <<'STUB'
#!/bin/bash
if [[ ${1:-} == "-h" ]]; then
  echo 'usage: sudo [-ABbEHkNnPS] command'
  exit 0
fi
[[ ${1:-} == "-N" ]] && shift
[[ ${1:-} == "-k" ]] && exit 0
exec "$@"
STUB
chmod 0755 "$test_tmp/sudo"
mount --bind "$test_tmp/sudo" /usr/bin/sudo
trap 'umount /usr/bin/sudo; rm -rf "$test_tmp"; umount /run' EXIT

test_root="$test_tmp/omarchy"
test_home="$test_tmp/home"
stub_bin="$test_root/bin"
mkdir -p "$test_root/migrations" "$test_home" "$stub_bin"
mkdir -p "$test_root/default/omarchy/sudo-no-update"
cp "$ROOT/default/omarchy/sudo-no-update/sudo" "$test_root/default/omarchy/sudo-no-update/sudo"
chmod 0755 "$test_root/default/omarchy/sudo-no-update/sudo"

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
