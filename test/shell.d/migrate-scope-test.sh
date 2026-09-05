#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

if [[ ${OMARCHY_MIGRATE_SCOPE_NS:-0} != 1 ]]; then
  exec unshare --user --map-root-user --mount \
    env OMARCHY_MIGRATE_SCOPE_NS=1 bash "$0"
fi

mount -t tmpfs -o mode=0755 tmpfs /run
test_tmp=$(mktemp -d -p /run omarchy-migrate-scope.XXXXXXXX)
cat >"$test_tmp/sudo" <<'STUB'
#!/bin/bash
if [[ ${1:-} == "-h" ]]; then
  echo 'usage: sudo [-ABbEHkNnPS] command'
  exit 0
fi
[[ -z ${TEST_SUDO_ARGS_LOG:-} ]] || printf '%s\n' "${1:-none}" >>"$TEST_SUDO_ARGS_LOG"
[[ ${1:-} == "-N" ]] && shift
[[ ${1:-} == "-k" ]] && exit 0
[[ ${1:-} == "--" ]] && shift
exec "$@"
STUB
chmod 0755 "$test_tmp/sudo"
mount --bind "$test_tmp/sudo" /usr/bin/sudo
trap 'umount /usr/bin/sudo; rm -rf "$test_tmp"; umount /run' EXIT

prepare_test_root() {
  local root="$1"

  mkdir -p "$root/default/omarchy/sudo-no-update"
  cp "$ROOT/default/omarchy/sudo-no-update/sudo" "$root/default/omarchy/sudo-no-update/sudo"
  chmod 0755 "$root/default/omarchy/sudo-no-update/sudo"
}

test_root="$test_tmp/omarchy"
test_home="$test_tmp/home"
mkdir -p "$test_root/migrations" "$test_home"
prepare_test_root "$test_root"

cat >"$test_root/migrations/100-first.sh" <<'SH'
[[ $OMARCHY_PATH == "$TEST_EXPECTED_OMARCHY_PATH" ]]
[[ ${OMARCHY_SUDO_NO_UPDATE:-0} == 1 ]]
[[ $(command -v sudo) == "$TEST_EXPECTED_SUDO_WRAPPER" ]]
sudo /usr/bin/true
echo first >>"$TEST_CALLS"
SH
cat >"$test_root/migrations/200-second.sh" <<'SH'
[[ $OMARCHY_PATH == "$TEST_EXPECTED_OMARCHY_PATH" ]]
echo second >>"$TEST_CALLS"
SH

calls="$test_tmp/calls"
sudo_args_log="$test_tmp/sudo-args"
: >"$sudo_args_log"

if ! HOME="$test_home" OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-migrate" --pending >"$test_tmp/pending.out"; then
  fail "migration runner reports pending migrations before state exists"
fi
grep -q '^100-first\.sh$' "$test_tmp/pending.out" || fail "migration runner lists first pending migration filename"
grep -q '^200-second\.sh$' "$test_tmp/pending.out" || fail "migration runner lists second pending migration filename"
pass "migration runner detects pending migrations"

HOME="$test_home" \
OMARCHY_PATH="$test_root" \
TEST_EXPECTED_OMARCHY_PATH="$test_root" \
TEST_EXPECTED_SUDO_WRAPPER="$test_root/default/omarchy/sudo-no-update/sudo" \
TEST_SUDO_ARGS_LOG="$sudo_args_log" \
TEST_CALLS="$calls" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/first-run.out"
[[ $(sed -n '1p' "$calls") == "first" ]] || fail "migration runner runs first migration"
[[ $(sed -n '2p' "$calls") == "second" ]] || fail "migration runner runs second migration"
[[ -f $test_home/.local/state/omarchy/migrations/100-first.sh ]] || fail "migration runner records first migration marker"
[[ -f $test_home/.local/state/omarchy/migrations/200-second.sh ]] || fail "migration runner records second migration marker"
grep -qxF -- '-N' "$sudo_args_log" || fail "migration sudo wrapper did not enforce --no-update"
pass "migration runner runs all migrations"

HOME="$test_home" \
OMARCHY_PATH="$test_root" \
TEST_EXPECTED_OMARCHY_PATH="$test_root" \
TEST_EXPECTED_SUDO_WRAPPER="$test_root/default/omarchy/sudo-no-update/sudo" \
TEST_SUDO_ARGS_LOG="$sudo_args_log" \
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
prepare_test_root "$failure_root"

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

stdin_root="$test_tmp/stdin-omarchy"
stdin_home="$test_tmp/stdin-home"
stdin_calls="$test_tmp/stdin-calls"
mkdir -p "$stdin_root/migrations" "$stdin_home"
prepare_test_root "$stdin_root"

cat >"$stdin_root/migrations/100-reader.sh" <<'SH'
IFS= read -r value
printf 'reader:%s\n' "$value" >>"$TEST_CALLS"
SH
cat >"$stdin_root/migrations/200-after.sh" <<'SH'
echo after-reader >>"$TEST_CALLS"
SH

printf 'migration input\n' | \
  HOME="$stdin_home" \
  OMARCHY_PATH="$stdin_root" \
  TEST_CALLS="$stdin_calls" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/stdin.out"

grep -q '^reader:migration input$' "$stdin_calls" ||
  fail "migration runner preserves the caller's stdin for a migration" "$(cat "$stdin_calls")"
grep -q '^after-reader$' "$stdin_calls" ||
  fail "a migration reading stdin does not swallow later queue entries" "$(cat "$stdin_calls")"
[[ -f $stdin_home/.local/state/omarchy/migrations/100-reader.sh &&
  -f $stdin_home/.local/state/omarchy/migrations/200-after.sh ]] ||
  fail "migration runner marks both stdin-isolated migrations complete"
pass "migration queue uses a private file descriptor instead of migration stdin"
