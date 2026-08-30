#!/bin/bash
# Exercise the production EUID-0 helper, its fixed paths, crash journal, and
# separate-filesystem archive behavior inside an isolated user+mount namespace.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

if [[ ${OMARCHY_UPDATE_CONFLICT_TEST_NAMESPACED:-0} != "1" ]]; then
  parent_mount_namespace=$(readlink /proc/self/ns/mnt)
  if ((EUID == 0)); then
    namespace_runner=(unshare --mount --propagation private)
  else
    namespace_runner=(unshare --user --map-auto --map-root-user --mount --propagation private)
  fi

  if "${namespace_runner[@]}" true 2>/dev/null; then
    exec env OMARCHY_UPDATE_CONFLICT_TEST_NAMESPACED=1 \
      OMARCHY_UPDATE_CONFLICT_TEST_PARENT_MOUNT_NAMESPACE="$parent_mount_namespace" \
      "${namespace_runner[@]}" bash "$0"
  fi
  pass "private mount namespace unavailable; skipping root update-conflict boundary probe"
  exit 0
fi

((EUID == 0)) || fail "the update-conflict boundary probe did not enter its root namespace"
current_mount_namespace=$(readlink /proc/self/ns/mnt)
[[ -n ${OMARCHY_UPDATE_CONFLICT_TEST_PARENT_MOUNT_NAMESPACE:-} && \
  $current_mount_namespace != "$OMARCHY_UPDATE_CONFLICT_TEST_PARENT_MOUNT_NAMESPACE" ]] ||
  fail "the update-conflict boundary probe did not enter a fresh mount namespace"
require_command setpriv

test_tmp=$(mktemp -d)
report_probe_pid=""
report_probe_release=""

cleanup() {
  if [[ -n $report_probe_release ]]; then
    : >"$report_probe_release" 2>/dev/null || true
  fi
  if [[ -n $report_probe_pid ]]; then
    kill "$report_probe_pid" 2>/dev/null || true
    wait "$report_probe_pid" 2>/dev/null || true
  fi
  rm -rf "$test_tmp"
}
trap cleanup EXIT

# Hide every production path the helper can mutate. Keeping /usr visible lets
# the test execute the real system tools, while /usr/local/sbin supplies only
# deterministic pacman and mv shims inside this mount namespace.
mount -t tmpfs -o mode=0755,size=8m conflict-etc /etc
mount -t tmpfs -o mode=0755,size=16m conflict-var /var
mount -t tmpfs -o mode=0755,size=4m conflict-run /run
mount -t tmpfs -o mode=0755,size=4m conflict-stubs /usr/local/sbin
mkdir -p /var/cache/pacman/pkg /var/lib/omarchy /var/tmp
chmod 0755 /var/cache /var/cache/pacman /var/cache/pacman/pkg /var/lib /var/lib/omarchy
chmod 1777 /var/tmp

cat >/usr/local/sbin/pacman <<'SH'
#!/bin/bash
set -euo pipefail

case ${1:-} in
-Sup)
  if [[ ${TEST_PLAN_PACKAGE:-0} == 1 ]]; then
    printf 'omarchy-settings-dev\tomarchy-settings-dev-test.pkg.tar.zst\n'
  fi
  ;;
-Qlp)
  printf 'omarchy-settings-dev %s\n' "$TEST_CONFLICT_PATH"
  ;;
-Qo)
  exit 1
  ;;
-Qoq)
  if [[ ${TEST_RETRY_INSTALLS:-0} == 1 && ( -e $TEST_CONFLICT_PATH || -L $TEST_CONFLICT_PATH ) ]]; then
    printf 'omarchy-settings-dev\n'
  else
    exit 1
  fi
  ;;
-Syu | -Su)
  attempt=$(($(<"$TEST_PACMAN_ATTEMPTS") + 1))
  printf '%s\n' "$attempt" >"$TEST_PACMAN_ATTEMPTS"
  if ((attempt == 1)); then
    printf 'error: failed to commit transaction (conflicting files)\n' >&2
    printf 'omarchy-settings-dev: %s exists in filesystem\n' "$TEST_CONFLICT_PATH" >&2
    if [[ ${TEST_REPORT_PROBE:-0} == 1 ]]; then
      readlink -f "/proc/$$/fd/2" >"$TEST_REPORT_PATH_FILE"
      : >"$TEST_REPORT_READY"
      while [[ ! -e $TEST_REPORT_RELEASE ]]; do
        sleep 0.01
      done
    fi
    exit 1
  fi
  if [[ ${TEST_RETRY_INSTALLS:-0} == 1 ]]; then
    printf 'packaged\n' >"$TEST_CONFLICT_PATH"
  fi
  ;;
*)
  echo "unexpected pacman invocation: $*" >&2
  exit 97
  ;;
esac
SH

cat >/usr/local/sbin/pacman-conf <<'SH'
#!/bin/bash
[[ ${1:-} == CacheDir ]] || exit 97
printf '/var/cache/pacman/pkg/\n'
SH

cat >/usr/local/sbin/mv <<'SH'
#!/bin/bash
/usr/bin/mv "$@"
status=$?
((status == 0)) || exit "$status"

destination=${@: -1}
if [[ ${KILL_AFTER_MOVE:-0} == 1 && $destination == /etc/.omarchy-update-conflicts.*/item-* ]]; then
  kill -KILL "$PPID"
fi
SH
chmod 0755 /usr/local/sbin/pacman /usr/local/sbin/pacman-conf /usr/local/sbin/mv

: >/var/cache/pacman/pkg/omarchy-settings-dev-test.pkg.tar.zst
chmod 0644 /var/cache/pacman/pkg/omarchy-settings-dev-test.pkg.tar.zst

# The decisive Pacman report must remain root-owned and inaccessible to the
# unprivileged caller for the entire transaction. Pause Pacman with stderr still
# open, inspect the real production report, and attempt both modification and
# replacement from a mapped non-root UID before allowing the helper to parse it.
printf 'report boundary\n' >/etc/report-boundary.conf
printf '0\n' >/var/tmp/pacman-attempts
report_path_file=/var/tmp/report-path
report_ready=/var/tmp/report-ready
report_probe_release=/var/tmp/report-release
attacker_report=/var/tmp/attacker-report

TEST_CONFLICT_PATH=/etc/report-boundary.conf TEST_PLAN_PACKAGE=0 TEST_REPORT_PROBE=1 \
  TEST_REPORT_PATH_FILE="$report_path_file" TEST_REPORT_READY="$report_ready" \
  TEST_REPORT_RELEASE="$report_probe_release" TEST_PACMAN_ATTEMPTS=/var/tmp/pacman-attempts \
  bash "$ROOT/bin/omarchy-update-file-conflicts" >/dev/null 2>&1 &
report_probe_pid=$!

for ((attempt = 0; attempt < 500; attempt++)); do
  [[ -e $report_ready ]] && break
  sleep 0.01
done
if [[ ! -e $report_ready ]]; then
  fail "the Pacman report privilege probe did not reach its synchronization point"
fi

report_file=$(<"$report_path_file")
report_dir=$(dirname -- "$report_file")
report_dir_state=$(stat -Lc '%u:%g:%a' "$report_dir")
report_file_state=$(stat -Lc '%u:%g:%a' "$report_file")
report_before=$(<"$report_file")

append_succeeded=0
if setpriv --reuid=1 --regid=1 --clear-groups \
  bash -c 'printf "forged conflict\n" >>"$1"' _ "$report_file" 2>/dev/null; then
  append_succeeded=1
fi

replacement_succeeded=0
if setpriv --reuid=1 --regid=1 --clear-groups \
  bash -c 'printf "forged report\n" >"$2" && mv -T -- "$2" "$1"' _ "$report_file" "$attacker_report" 2>/dev/null; then
  replacement_succeeded=1
fi
report_after=$(<"$report_file")

: >"$report_probe_release"
if wait "$report_probe_pid"; then
  report_probe_status=0
else
  report_probe_status=$?
fi
report_probe_pid=""
report_probe_release=""

[[ $report_dir_state == "0:0:700" ]] || fail "the privileged report directory is not root-only" "got: $report_dir_state"
[[ $report_file_state == "0:0:600" ]] || fail "the privileged report file is not root-only" "got: $report_file_state"
((append_succeeded == 0)) || fail "a non-root process modified the privileged Pacman report"
((replacement_succeeded == 0)) || fail "a non-root process replaced the privileged Pacman report"
[[ $report_after == "$report_before" ]] || fail "the privileged Pacman report changed during the non-root attack"
((report_probe_status != 0)) || fail "the deliberately unauthorized report probe completed an update"
grep -qx 'report boundary' /etc/report-boundary.conf || fail "the report probe displaced its unauthorized conflict path"
pass "the Pacman report remains root-only until the privileged helper parses it"

# A cached allowed archive is insufficient when the package is absent from the
# pending sysupgrade transaction.
printf 'inactive\n' >/etc/inactive.conf
printf '0\n' >/var/tmp/pacman-attempts
if TEST_CONFLICT_PATH=/etc/inactive.conf TEST_PLAN_PACKAGE=0 \
  TEST_PACMAN_ATTEMPTS=/var/tmp/pacman-attempts \
  bash "$ROOT/bin/omarchy-update-file-conflicts" >/dev/null 2>&1; then
  fail "the real root helper accepted an archive outside the sysupgrade transaction"
fi
grep -qx inactive /etc/inactive.conf || fail "a non-transaction package displaced a root path"
pass "real root authorization is bound to the pending sysupgrade transaction"

# Kill the helper after rename(2), bypassing every shell trap. The mapping must
# already be durable beside the opaque item.
printf 'crash payload\n' >/etc/crash.conf
printf '0\n' >/var/tmp/pacman-attempts
if TEST_CONFLICT_PATH=/etc/crash.conf TEST_PLAN_PACKAGE=1 KILL_AFTER_MOVE=1 \
  TEST_PACMAN_ATTEMPTS=/var/tmp/pacman-attempts \
  bash "$ROOT/bin/omarchy-update-file-conflicts" >/dev/null 2>&1; then
  fail "the crash fixture did not kill the helper"
fi
crash_manifest=$(grep -Fl $'item-0\t/etc/crash.conf' /etc/.omarchy-update-conflicts.*/manifest 2>/dev/null | head -n1)
[[ -n $crash_manifest ]] || fail "an uncatchable interruption lost the opaque-path mapping"
crash_stage=${crash_manifest%/manifest}
grep -qx 'crash payload' "$crash_stage/item-0" || fail "the crash journal does not identify the retained payload"
[[ $(stat -Lc '%u:%a' "$crash_stage/manifest") == 0:600 ]] || fail "the crash manifest is not root-only"
pass "the opaque-path journal is durable before the destructive rename"

# /etc and /var are distinct tmpfs mounts. Archival must refuse mv(1)'s
# recursive cross-filesystem copy and retain the complete stage beside /etc.
[[ $(stat -Lc '%d' /etc) != "$(stat -Lc '%d' /var)" ]] || fail "the archive boundary test did not create separate filesystems"
printf 'legacy payload\n' >/etc/legacy.conf
printf '0\n' >/var/tmp/pacman-attempts
TEST_CONFLICT_PATH=/etc/legacy.conf TEST_PLAN_PACKAGE=1 TEST_RETRY_INSTALLS=1 \
  TEST_PACMAN_ATTEMPTS=/var/tmp/pacman-attempts \
  bash "$ROOT/bin/omarchy-update-file-conflicts" >/dev/null 2>&1 ||
  fail "the real root helper rejected a valid separate-filesystem conflict"
grep -qx packaged /etc/legacy.conf || fail "the retry did not install its package path"
legacy_manifest=$(grep -Fl $'item-0\t/etc/legacy.conf' /etc/.omarchy-update-conflicts.*/manifest 2>/dev/null | head -n1)
[[ -n $legacy_manifest ]] || fail "separate-filesystem archival copied or lost the protected stage"
legacy_stage=${legacy_manifest%/manifest}
grep -qx 'legacy payload' "$legacy_stage/item-0" || fail "the retained same-filesystem stage lost its payload"
locations=$(find /var/lib/omarchy/replaced -type f -name locations -print -quit)
grep -Fqx $'etc\t'"$legacy_stage" "$locations" || fail "the archive transaction does not point to its retained stage"
pass "archival never recursively copies a quarantined tree across filesystems"
