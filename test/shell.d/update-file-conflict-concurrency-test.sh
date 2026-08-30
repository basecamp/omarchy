#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command flock

test_tmp=$(mktemp -d)
a_pid=""
b_pid=""

cleanup() {
  : >"$test_tmp/release-a"
  if [[ -n $a_pid ]]; then
    kill "$a_pid" 2>/dev/null || true
    wait "$a_pid" 2>/dev/null || true
  fi
  if [[ -n $b_pid ]]; then
    kill "$b_pid" 2>/dev/null || true
    wait "$b_pid" 2>/dev/null || true
  fi
  rm -rf "$test_tmp"
}
trap cleanup EXIT

stub_bin="$test_tmp/bin"
system_root="$test_tmp/system"
archive_root="$test_tmp/archive"
report_parent="$test_tmp/run"
package_cache="$system_root/var/cache/pacman/pkg"
conflict_path="$system_root/usr/lib/omarchy-test/concurrent.conf"
helper_a="$test_tmp/omarchy-update-file-conflicts-a"
helper_b="$test_tmp/omarchy-update-file-conflicts-b"
mkdir -p "$stub_bin" "$package_cache" "$(dirname -- "$conflict_path")" "$system_root/etc" "$report_parent"
chmod 0755 "$system_root/usr" "$system_root/usr/lib" "$(dirname -- "$conflict_path")" \
  "$system_root/var" "$system_root/var/cache" "$system_root/var/cache/pacman" "$package_cache" \
  "$system_root/etc" "$report_parent"

printf 'original\n' >"$conflict_path"
: >"$package_cache/omarchy-settings-dev-test.pkg.tar.zst"
chmod 0644 "$package_cache/omarchy-settings-dev-test.pkg.tar.zst"
printf '0\n' >"$test_tmp/A-attempts"
printf '0\n' >"$test_tmp/B-attempts"
: >"$test_tmp/lock-events"
: >"$test_tmp/pacman-events"

# Make two independently executable copies that share only their isolated fake
# system, archive, report directory, and therefore the global transaction lock.
# Helper A pauses after validating the original path and before moving it.
make_helper_copy() {
  local destination="$1" test_uid test_gid
  test_uid=$(id -u)
  test_gid=$(id -g)

  sed \
    -e 's/if ((EUID != 0)); then/if false; then/' \
    -e 's|export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin|export PATH=${OMARCHY_TEST_HELPER_PATH:?}|' \
    -e 's/readonly ROOT_UID=0/readonly ROOT_UID='"$test_uid"'/' \
    -e 's/readonly ROOT_GID=0/readonly ROOT_GID='"$test_gid"'/' \
    -e "s|readonly ARCHIVE_BOUNDARY=/var|readonly ARCHIVE_BOUNDARY=$test_tmp|" \
    -e "s|readonly ARCHIVE_PARENT=/var/lib/omarchy|readonly ARCHIVE_PARENT=$test_tmp|" \
    -e "s|readonly ARCHIVE_ROOT=/var/lib/omarchy/replaced|readonly ARCHIVE_ROOT=$archive_root|" \
    -e "s|readonly PACKAGE_CACHE_BOUNDARY=/|readonly PACKAGE_CACHE_BOUNDARY=$system_root/var|" \
    -e "s|readonly REPORT_PARENT=/run|readonly REPORT_PARENT=$report_parent|" \
    -e "s|allowed_roots=(/etc /usr)|allowed_roots=($system_root/etc $system_root/usr)|" \
    -e '/^validate_conflicts$/a\
if [[ ${HELPER_ID:-} == A ]]; then\
  : >"$TEST_A_VALIDATED"\
  while [[ ! -e $TEST_RELEASE_A ]]; do /usr/bin/sleep 0.01; done\
fi' \
    "$ROOT/bin/omarchy-update-file-conflicts" >"$destination"
  chmod 0755 "$destination"
}

make_helper_copy "$helper_a"
make_helper_copy "$helper_b"

cat >"$stub_bin/flock" <<'SH'
#!/bin/bash
printf '%s attempt\n' "$HELPER_ID" >>"$LOCK_EVENTS"
/usr/bin/flock "$@"
status=$?
((status == 0)) || exit "$status"
printf '%s acquired\n' "$HELPER_ID" >>"$LOCK_EVENTS"
SH

cat >"$stub_bin/pacman-conf" <<'SH'
#!/bin/bash
[[ ${1:-} == CacheDir ]] || exit 97
printf '%s/\n' "$PACKAGE_CACHE"
SH

cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
set -euo pipefail

case ${1:-} in
-Sup)
  printf 'omarchy-settings-dev\tomarchy-settings-dev-test.pkg.tar.zst\n'
  ;;
-Qlp)
  printf 'omarchy-settings-dev %s\n' "$CONFLICT_PATH"
  ;;
-Qo)
  [[ -e $INSTALLED_STATE ]]
  ;;
-Qoq)
  if [[ -e $INSTALLED_STATE ]]; then
    printf 'omarchy-settings-dev\n'
  else
    exit 1
  fi
  ;;
-Syu | -Su)
  attempts="$TEST_STATE/$HELPER_ID-attempts"
  attempt=$(($(<"$attempts") + 1))
  printf '%s\n' "$attempt" >"$attempts"
  printf '%s pacman %s\n' "$HELPER_ID" "$attempt" >>"$PACMAN_EVENTS"

  if ((attempt == 1)); then
    if [[ -e $INSTALLED_STATE ]]; then
      exit 0
    fi
    printf 'error: failed to commit transaction (conflicting files)\n' >&2
    printf 'omarchy-settings-dev: %s exists in filesystem\n' "$CONFLICT_PATH" >&2
    exit 1
  fi

  # The first retry commits the package. If another helper already committed
  # it, Pacman has no pending work and succeeds without recreating a file that
  # the stale helper moved after its earlier validation.
  if [[ ! -e $INSTALLED_STATE ]]; then
    printf 'packaged\n' >"$CONFLICT_PATH"
    : >"$INSTALLED_STATE"
    printf '%s committed\n' "$HELPER_ID" >>"$LOCK_EVENTS"
  fi
  ;;
*)
  echo "unexpected pacman invocation: $*" >&2
  exit 97
  ;;
esac
SH

chmod 0755 "$stub_bin"/*

run_helper() {
  local helper_id="$1" helper="$2"
  HELPER_ID="$helper_id" \
    OMARCHY_TEST_HELPER_PATH="$stub_bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin" \
    LOCK_EVENTS="$test_tmp/lock-events" PACMAN_EVENTS="$test_tmp/pacman-events" \
    TEST_STATE="$test_tmp" TEST_A_VALIDATED="$test_tmp/a-validated" TEST_RELEASE_A="$test_tmp/release-a" \
    PACKAGE_CACHE="$package_cache" CONFLICT_PATH="$conflict_path" INSTALLED_STATE="$test_tmp/installed" \
    "$helper"
}

wait_for() {
  local predicate="$1"
  local attempt
  for ((attempt = 0; attempt < 500; attempt++)); do
    if eval "$predicate"; then
      return 0
    fi
    /usr/bin/sleep 0.01
  done
  return 1
}

run_helper A "$helper_a" >"$test_tmp/a-out" 2>"$test_tmp/a-err" &
a_pid=$!
wait_for '[[ -e $test_tmp/a-validated ]]' ||
  fail "helper A did not reach the validation pause" "$(cat "$test_tmp/a-err")"

run_helper B "$helper_b" >"$test_tmp/b-out" 2>"$test_tmp/b-err" &
b_pid=$!

# With the global lock, B reaches flock but cannot acquire it or invoke Pacman
# while A is paused inside the conflict transaction. Without the lock, B runs
# to completion here and installs the path that stale helper A later removes.
wait_for 'grep -Fqx "B attempt" "$test_tmp/lock-events" || grep -Fq "B pacman" "$test_tmp/pacman-events" || ! kill -0 "$b_pid" 2>/dev/null' ||
  fail "helper B neither contended on the transaction lock nor reached Pacman" "$(cat "$test_tmp/b-err")"

b_contended=0
b_acquired_early=0
b_ran_pacman_early=0
b_status=""
grep -Fqx 'B attempt' "$test_tmp/lock-events" && b_contended=1
grep -Fqx 'B acquired' "$test_tmp/lock-events" && b_acquired_early=1
grep -Fq 'B pacman' "$test_tmp/pacman-events" && b_ran_pacman_early=1

# In the unprotected implementation, let B finish installing before releasing
# stale helper A. This deterministically reproduces A moving B's installed file.
if ((b_contended == 0)); then
  if wait "$b_pid"; then
    b_status=0
  else
    b_status=$?
  fi
  b_pid=""
fi

: >"$test_tmp/release-a"

if wait "$a_pid"; then
  a_status=0
else
  a_status=$?
fi
a_pid=""

if [[ -n $b_pid ]]; then
  if wait "$b_pid"; then
    b_status=0
  else
    b_status=$?
  fi
  b_pid=""
fi

[[ $a_status == 0 && $b_status == 0 ]] ||
  fail "serialized conflict helpers do not both complete successfully" "$(cat "$test_tmp/a-err" "$test_tmp/b-err")"
[[ -f $conflict_path ]] ||
  fail "a stale concurrent helper removes the path installed by the other transaction"
grep -qx packaged "$conflict_path" ||
  fail "the serialized helpers do not leave the package's installed content intact"
((b_contended == 1)) || fail "the second helper does not contend on the global transaction lock"
((b_acquired_early == 0)) || fail "the second helper acquires the lock before the first transaction finishes"
((b_ran_pacman_early == 0)) || fail "the second helper starts Pacman before the first transaction finishes"
[[ $(<"$test_tmp/A-attempts") == 2 && $(<"$test_tmp/B-attempts") == 1 ]] ||
  fail "serialization does not turn the second helper into a single clean transaction"
[[ $(<"$test_tmp/lock-events") == $'A attempt\nA acquired\nB attempt\nA committed\nB acquired' ]] ||
  fail "the helpers do not acquire the global transaction lock in order" "$(cat "$test_tmp/lock-events")"

pass "concurrent file-conflict helpers serialize without losing installed files"
