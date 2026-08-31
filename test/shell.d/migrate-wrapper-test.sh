#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_root="$test_tmp/omarchy"
test_home="$test_tmp/home"
stub_bin="$test_tmp/bin"
conf="$test_tmp/omarchy.conf"
mkdir -p "$test_root/migrations" "$test_home" "$stub_bin"

# omarchy-migrate reads migrations from the packaged tree, or from a checkout
# that a root-owned /etc/omarchy.conf names. Run a copy whose conf path points
# at a stand-in, and authorize the scratch tree the way omarchy-dev-link
# would. stat is stubbed to report the stand-in as root-owned, which is the
# part of dev-link only root can do for real.
migrate_copy="$test_tmp/omarchy-migrate"
sed "s#/etc/omarchy.conf#$conf#g" "$ROOT/bin/omarchy-migrate" >"$migrate_copy"
chmod +x "$migrate_copy"

cat >"$stub_bin/stat" <<'SH'
#!/bin/bash
for last; do :; done
if [[ $last == "$TEST_CONF" ]]; then
  case " $* " in
    *" %u "*) echo 0 ;;
    *" %a "*) echo 644 ;;
  esac
  exit 0
fi
exec /usr/bin/stat "$@"
SH
chmod +x "$stub_bin/stat"

printf 'export OMARCHY_PATH="%s"\n' "$test_root" >"$conf"
chmod 0644 "$conf"

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
  TEST_CONF="$conf" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_CALLS="$test_tmp/calls" \
  TEST_DISMISSALS="$test_tmp/dismissals" \
    "$migrate_copy" "$@"
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
