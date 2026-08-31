#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

unset GUM_STATUS
unset OMARCHY_UPDATE_FORCE
unset TEST_AVAILABLE_BYTES
unset TEST_DF_INVALID

if [[ -z ${OMARCHY_UPDATE_DISK_TEST_NS:-} ]]; then
  outer_uid=$(id -u)
  outer_gid=$(id -g)
  subuid=$(awk -F: -v user="$(id -un)" '$1 == user { print $2; exit }' /etc/subuid)
  subgid=$(awk -F: -v group="$(id -gn)" '$1 == group { print $2; exit }' /etc/subgid)
  if [[ -z $subuid || -z $subgid ]]; then
    pass "no subordinate uid/gid range; skipping authorized update disk-space test"
    exit 0
  fi
  exec unshare --user --mount \
    --map-users "0:$outer_uid:1" --map-users "1:$subuid:65536" \
    --map-groups "0:$outer_gid:1" --map-groups "1:$subgid:65536" \
    env OMARCHY_UPDATE_DISK_TEST_NS=setup bash "$0"
elif [[ $OMARCHY_UPDATE_DISK_TEST_NS == setup ]]; then
  mount -t tmpfs -o mode=0755 tmpfs /run
  namespace_tmp=$(mktemp -d -p /run omarchy-update-disk-space.XXXXXXXX)
  chmod 0755 "$namespace_tmp"
  mkdir -p "$namespace_tmp/default/omarchy/sudo-no-update"
  cp "$ROOT/default/omarchy/sudo-no-update/sudo" "$namespace_tmp/default/omarchy/sudo-no-update/sudo"
  chmod 0755 "$namespace_tmp/default/omarchy/sudo-no-update/sudo"
  cat >"$namespace_tmp/fixed-sudo" <<'STUB'
#!/bin/bash
if [[ ${1:-} == "-h" ]]; then
  echo 'usage: sudo [-ABbEHkNnPS] command'
fi
exit 0
STUB
  chmod 0755 "$namespace_tmp/fixed-sudo"
  mount --bind "$namespace_tmp/fixed-sudo" /usr/bin/sudo
  mount -t tmpfs -o mode=0755 tmpfs /etc
  printf 'export OMARCHY_PATH="%s"\n' "$namespace_tmp" >/etc/omarchy.conf
  chmod 0644 /etc/omarchy.conf
  chown -R 1000:1000 "$namespace_tmp"

  set +e
  setpriv --reuid 1000 --regid 1000 --clear-groups \
    env OMARCHY_UPDATE_DISK_TEST_NS=run OMARCHY_AUTHORIZED_TEST_ROOT="$namespace_tmp" bash "$0"
  status=$?
  set -e

  umount /usr/bin/sudo
  umount /etc
  rm -rf "$namespace_tmp"
  umount /run
  exit "$status"
fi

test_tmp="$OMARCHY_AUTHORIZED_TEST_ROOT"
trap 'rm -rf "$test_tmp"/*' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
runtime_dir="$test_tmp/runtime"
snapshot_marker="$test_tmp/snapshot"
gum_marker="$test_tmp/gum"
mkdir -p "$stub_bin" "$test_home" "$runtime_dir"

run_update() {
  HOME="$test_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  LC_ALL=C \
  OMARCHY_UPDATE_LOGGED=1 \
  TEST_AVAILABLE_BYTES=${TEST_AVAILABLE_BYTES:-$((9 * 1024 * 1024 * 1024))} \
  TEST_DF_INVALID=${TEST_DF_INVALID:-0} \
  SNAPSHOT_MARKER="$snapshot_marker" \
  GUM_MARKER="$gum_marker" \
  GUM_STATUS=${GUM_STATUS:-1} \
    "$ROOT/bin/omarchy-update" "$@"
}

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

write_stub df '
if (( TEST_DF_INVALID )); then
  printf "Avail\nunknown\n"
else
  printf "Avail\n%s\n" "$TEST_AVAILABLE_BYTES"
fi'

write_stub gum '
printf "%s\n" "$*" >>"$GUM_MARKER"
if [[ ${1:-} == "confirm" ]]; then
  exit "$GUM_STATUS"
fi
exit 0'

write_stub omarchy-snapshot '
touch "$SNAPSHOT_MARKER"
exit 0'

for command in \
  omarchy-cmd-present \
  omarchy-toggle-idle \
  pkexec \
  systemd-inhibit \
  omarchy-update-dev \
  omarchy-update-pkg-prune \
  omarchy-update-keyring \
  omarchy-update-system-pkgs \
  omarchy-migrate \
  omarchy-update-aur-pkgs \
  omarchy-update-mise \
  omarchy-update-orphan-pkgs \
  omarchy-hook \
  omarchy-update-analyze-logs \
  omarchy-shell \
  omarchy-update-restart; do
  write_stub "$command" 'exit 0'
done
write_stub omarchy-update-available 'exit 1'
write_stub pkexec 'exec "$@"'

set +e
TEST_AVAILABLE_BYTES=$((9 * 1024 * 1024 * 1024)) \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-update-requires-free-space" >/dev/null
status=$?
set -e
(( status == 1 )) || fail "free-space helper exits non-zero when disk space is low"
pass "free-space helper reports low disk space through its exit status"

set +e
output=$(run_update -y)
status=$?
set -e
(( status == 1 )) || fail "non-interactive update exits non-zero with low disk space"
[[ $output == *"You need at least 10 GiB free to safely update Omarchy."* ]] || fail "low disk space emits a warning"
[[ ! -f $gum_marker ]] || fail "non-interactive update does not prompt for low disk space"
[[ ! -f $snapshot_marker ]] || fail "non-interactive update stops before snapshotting with low disk space"
pass "non-interactive update stops with low disk space"

rm -f "$snapshot_marker" "$gum_marker"
set +e
output=$(run_update)
status=$?
set -e
(( status == 1 )) || fail "interactive update exits non-zero with low disk space"
[[ $output == *"You need at least 10 GiB free to safely update Omarchy."* ]] || fail "interactive low-space update explains the requirement"
[[ ! -f $gum_marker ]] || fail "interactive update stops before confirmation with low disk space"
[[ ! -f $snapshot_marker ]] || fail "interactive update stops before snapshotting with low disk space"
pass "interactive update stops before confirmation with low disk space"

rm -f "$snapshot_marker" "$gum_marker"
output=$(OMARCHY_UPDATE_FORCE=1 run_update -y)
[[ -z $output ]] || fail "forced update does not emit the free-space warning"
[[ ! -f $gum_marker ]] || fail "forced non-interactive update does not prompt"
[[ -f $snapshot_marker ]] || fail "forced update continues with low disk space"
pass "forced update skips the free-space requirement"

rm -f "$snapshot_marker" "$gum_marker"
output=$(TEST_AVAILABLE_BYTES=$((10 * 1024 * 1024 * 1024)) run_update -y)
[[ $output != *"You need at least 10 GiB free"* ]] || fail "space equal to the threshold does not produce a warning"
[[ -f $snapshot_marker ]] || fail "space equal to the threshold allows the update"
pass "disk-space threshold includes the exact boundary"

rm -f "$snapshot_marker" "$gum_marker"
GUM_STATUS=0 TEST_AVAILABLE_BYTES=$((10 * 1024 * 1024 * 1024)) run_update >/dev/null
grep -q "confirm Continue with update?" "$gum_marker" ||
  fail "interactive update with enough space uses the normal confirmation prompt"
[[ -f $snapshot_marker ]] || fail "accepting the normal confirmation starts the update"
pass "interactive update keeps the normal confirmation prompt when space is sufficient"

rm -f "$snapshot_marker"
output=$(TEST_DF_INVALID=1 run_update -y)
[[ -z $output ]] || fail "failed disk-space detection remains silent"
[[ -f $snapshot_marker ]] || fail "failed disk-space detection does not block the update"
pass "failed disk-space detection silently continues"
