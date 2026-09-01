#!/bin/bash
# Exercise the real EUID-0/PKEXEC_UID boundary in an isolated user+mount namespace.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

if ((EUID != 0)); then
  if unshare --user --map-auto --map-root-user --mount true 2>/dev/null; then
    exec unshare --user --map-auto --map-root-user --mount --propagation private bash "$0"
  fi
  pass "automatic subordinate-id namespace unavailable; skipping root Windows VM boundary probe"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# The checkout may live under /home, which the tmpfs below hides, so take a
# mount-safe copy of the helper before the mounts land.
cp "$ROOT/bin/omarchy-windows-vm" "$test_tmp/omarchy-windows-vm"

# Hide host state before creating the production paths used by the root helper.
mount -t tmpfs -o mode=0755,size=8m run-test /run
mkdir -p /run/lock
mount -t tmpfs -o mode=0755,size=16m var-test /var
mkdir -p /var/lib/omarchy
mount -t tmpfs -o mode=0755,size=16m home-parent /home
mkdir /home/alice
mount -t tmpfs -o uid=0,gid=0,mode=0710,size=1g home-alice /home/alice

export HOME=/home/alice
unset OMARCHY_WINDOWS_DIR
set -- help
source "$test_tmp/omarchy-windows-vm" >/dev/null 2>&1

# The namespace maps the host filesystem's uid 0 to nobody. Only / remains on
# that filesystem; all paths the helper mutates are isolated tmpfs mounts.
stat() {
  if [[ ${!#} == / && $* == *"%u"* ]]; then printf '0\n'; return; fi
  command stat "$@"
}

TEST_PASSWD_HOME=/home/alice
getent() {
  if [[ $1 == passwd && ${2:-} == 1000 ]]; then
    printf 'alice:x:1000:1000::%s:/bin/bash\n' "$TEST_PASSWD_HOME"
    return 0
  fi
  return 2
}

assert_no_runtime_mutation() {
  [[ ! -e /var/lib/omarchy/windows && ! -L /var/lib/omarchy/windows ]] ||
    fail "$1 mutated the production runtime"
}

unset PKEXEC_UID
resolve_caller 2>/dev/null && fail "root accepted missing PKEXEC_UID"
assert_no_runtime_mutation "missing PKEXEC_UID"
PKEXEC_UID=0
resolve_caller 2>/dev/null && fail "root accepted PKEXEC_UID=0"
assert_no_runtime_mutation "zero PKEXEC_UID"
PKEXEC_UID=not-a-number
resolve_caller 2>/dev/null && fail "root accepted nonnumeric PKEXEC_UID"
assert_no_runtime_mutation "nonnumeric PKEXEC_UID"
PKEXEC_UID=1001
resolve_caller 2>/dev/null && fail "root accepted uid absent from passwd"
assert_no_runtime_mutation "missing passwd entry"

PKEXEC_UID=1000
resolve_caller 2>/dev/null && fail "root accepted a home not owned by caller"
assert_no_runtime_mutation "wrong-owned home"
chown 1000:1000 /home/alice

chmod 0777 /home
resolve_caller 2>/dev/null && fail "root accepted writable home parent"
assert_no_runtime_mutation "writable parent"
chmod 0755 /home

mkdir /home/real-alice
chown 1000:1000 /home/real-alice
ln -s /home/real-alice /home/link-alice
TEST_PASSWD_HOME=/home/link-alice
resolve_caller 2>/dev/null && fail "root accepted symlinked passwd home"
assert_no_runtime_mutation "symlinked home"
TEST_PASSWD_HOME=/home/alice
resolve_caller || fail "valid root PKEXEC_UID/home boundary was rejected"
pass "root dispatch rejects missing/invalid uid, passwd, owner, symlink, and writable-parent boundaries without mutation"

# Put each familiar source on its own filesystem. Both start with legacy 0755
# permissions and world-readable payloads to prove migration hardens the leaves.
mkdir /home/storage-target /home/shared-target
mount -t tmpfs -o uid=1000,gid=1000,mode=0755,size=3g storage-test /home/storage-target
mount -t tmpfs -o uid=1000,gid=1000,mode=0755,size=64m shared-test /home/shared-target
ln -s /home/storage-target /home/alice/.windows
ln -s /home/shared-target /home/alice/Windows
chown -h 1000:1000 /home/alice/.windows /home/alice/Windows
printf disk >/home/storage-target/disk.img
printf shared >/home/shared-target/shared.txt
chown 1000:1000 /home/storage-target/disk.img /home/shared-target/shared.txt
chmod 0644 /home/storage-target/disk.img /home/shared-target/shared.txt

home_dev=$(command stat -Lc '%d' /home/alice)
storage_dev=$(command stat -Lc '%d' /home/storage-target)
[[ $home_dev != "$storage_dev" ]] || fail "storage target did not land on a separate filesystem"

with_vm_lock prepare_caller_mounts || fail "root could not create verified production bind anchors"
resolve_caller
[[ $(readlink /home/alice/.windows) == /home/storage-target &&
  $(readlink /home/alice/Windows) == /home/shared-target ]] || fail "root consumed legitimate symlinks"
[[ $(command stat -Lc '%d:%i' "$EXPECTED_STORAGE") == $(command stat -Lc '%d:%i' /home/storage-target) ]] || fail "storage bind identity differs from pinned source"
[[ $(command stat -Lc '%d:%i' "$EXPECTED_SHARED") == $(command stat -Lc '%d:%i' /home/shared-target) ]] || fail "shared bind identity differs from pinned source"
[[ $(command stat -Lc '%d' "$CALLER_DATA_ROOT") != "$storage_dev" ]] || fail "Docker boundary unexpectedly shares the storage filesystem"
[[ $(command stat -Lc '%u:%a' "$MOUNT_ROOT") == 0:711 &&
  $(command stat -Lc '%u:%a' "$CALLER_DATA_ROOT") == 0:711 ]] || fail "production ancestors are not root-owned/private-boundary modes"
[[ $(command stat -Lc '%u:%a' "$EXPECTED_STORAGE") == 1000:700 &&
  $(command stat -Lc '%u:%a' "$EXPECTED_SHARED") == 1000:700 ]] || fail "migrated leaves are not caller-owned 0700"
if setpriv --reuid=1001 --regid=1001 --clear-groups cat "$EXPECTED_STORAGE/disk.img" >/dev/null 2>&1; then
  fail "another local account read the VM disk through its anchor"
fi
if setpriv --reuid=1001 --regid=1001 --clear-groups cat "$EXPECTED_SHARED/shared.txt" >/dev/null 2>&1; then
  fail "another local account read shared files through their anchor"
fi
pass "cross-filesystem symlink sources bind by identity and migrated 0700 leaves deny another account"

# Existing production boundary components are never repaired in place when
# their ownership or write permissions are unsafe. Both the preparation path
# and the final pre-Docker guard must fail closed without disturbing the binds.
chmod 0731 "$MOUNT_ROOT"
with_vm_lock prepare_caller_mounts 2>/dev/null && fail "root repaired a group-writable mount boundary instead of rejecting it"
mounts_ready 2>/dev/null && fail "final guard accepted a group-writable mount boundary"
[[ $(command stat -Lc '%a' "$MOUNT_ROOT") == 731 ]] || fail "rejection unexpectedly changed the writable boundary"
chmod 0711 "$MOUNT_ROOT"

chown 1000:1000 "$USERS_DIR"
with_vm_lock prepare_caller_mounts 2>/dev/null && fail "root repaired a caller-owned mount boundary instead of rejecting it"
mounts_ready 2>/dev/null && fail "final guard accepted a caller-owned mount boundary"
[[ $(command stat -Lc '%u' "$USERS_DIR") == 1000 ]] || fail "rejection unexpectedly changed the boundary owner"
chown root:root "$USERS_DIR"

[[ $(mount_layer_count "$EXPECTED_STORAGE") == 1 &&
  $(mount_layer_count "$EXPECTED_SHARED") == 1 ]] || fail "boundary rejection changed the verified mount pair"
mounts_ready || fail "restored production boundaries were rejected"
pass "root rejects wrong-owned and group-writable production mount boundaries without mutation"

expected_space=$(command df -P -- /home/storage-target | awk 'NR==2 {print int($4/1024/1024)}')
actual_space=$(available_storage_gb)
[[ $actual_space == "$expected_space" ]] || fail "disk-space helper did not measure the storage target filesystem"
[[ $(command df -P -- /home/alice | awk 'NR==2 {print int($4/1024/1024)}') != "$actual_space" ]] || fail "test filesystems do not distinguish home from storage"
pass "disk-space accounting measures the actual storage filesystem, not home"

# Exercise the real root writer and final guard against the production paths.
printf 'RAM=4G\nCORES=2\nDISK=64G\nUSERNAME=alice\nPASSWORD=pw\nTZ=UTC\n' |
  with_vm_lock __priv_write_compose
[[ $(command stat -Lc '%u:%a' "$COMPOSE_FILE") == 0:640 ]] || fail "root compose ownership/mode is wrong"
with_vm_lock assert_mounts_safe || fail "final root mount/compose assertion rejected the verified pair"
pass "root writer and final pre-Docker guard revalidate the pinned production mounts"

# Upgrade the exact sibling-anchor pair emitted by the earlier fix without
# moving or replacing either familiar home symlink.
sed -i "s|$EXPECTED_STORAGE:/storage|$OLD_EXPECTED_STORAGE:/storage|" "$COMPOSE_FILE"
sed -i "s|$EXPECTED_SHARED:/shared|$OLD_EXPECTED_SHARED:/shared|" "$COMPOSE_FILE"
sed -i '/PROTECT: "Y"/d' "$COMPOSE_FILE"
compose_needs_security_migration || fail "previous protected compose was not recognized for upgrade"
with_vm_lock assert_mounts_safe || fail "root could not upgrade previous protected anchors"
grep -q -- "- $EXPECTED_STORAGE:/storage" "$COMPOSE_FILE" || fail "upgrade did not rewrite storage anchor"
grep -q -- "- $EXPECTED_SHARED:/shared" "$COMPOSE_FILE" || fail "upgrade did not rewrite shared anchor"
grep -q 'PROTECT: "Y"' "$COMPOSE_FILE" || fail "upgrade did not protect the web console"
[[ $(readlink /home/alice/.windows) == /home/storage-target ]] || fail "protected-anchor upgrade replaced home storage link"
pass "previous sibling-anchor installs upgrade in place to the fixed /var/lib boundary"

# A compose that already uses the fixed anchors still needs an authorized
# upgrade when it predates web-console authentication.
sed -i '/PROTECT: "Y"/d' "$COMPOSE_FILE"
compose_needs_security_migration || fail "unprotected fixed-anchor compose was not recognized for upgrade"
with_vm_lock assert_mounts_safe || fail "root could not protect an existing fixed-anchor compose"
grep -q 'PROTECT: "Y"' "$COMPOSE_FILE" || fail "fixed-anchor upgrade did not protect the web console"
pass "existing fixed-anchor compose gains web-console authentication"

# Preflight both sources before either bind on a clean anchor pair.
umount "$EXPECTED_SHARED"
umount "$EXPECTED_STORAGE"
rm /home/alice/Windows
ln -s / /home/alice/Windows
chown -h 1000:1000 /home/alice/Windows
with_vm_lock prepare_caller_mounts 2>/dev/null && fail "root accepted a non-caller-owned second source"
[[ $(mount_layer_count "$EXPECTED_STORAGE") == 0 && $(mount_layer_count "$EXPECTED_SHARED") == 0 ]] || fail "failed second-source preflight left a partial bind"
[[ $(readlink /home/alice/Windows) == / ]] || fail "failed preflight consumed or quarantined symlink"
pass "root preflights both sources before mounting either and preserves rejection evidence"

# mountpoint(1) follows symlinks, so explicitly pin the invariant that even a
# root-planted anchor symlink to the expected mounted source is rejected.
rm /home/alice/Windows
ln -s /home/shared-target /home/alice/Windows
chown -h 1000:1000 /home/alice/Windows
rmdir "$EXPECTED_STORAGE"
ln -s /home/storage-target "$EXPECTED_STORAGE"
storage_id=$(command stat -Lc '%d:%i' /home/storage-target)
mounted_leaf_matches "$EXPECTED_STORAGE" "$storage_id" && fail "symlink mount anchor passed final identity check"
with_vm_lock prepare_caller_mounts 2>/dev/null && fail "root followed a symlink mount anchor"
[[ -L $EXPECTED_STORAGE ]] || fail "rejected anchor symlink was consumed"
pass "final guard rejects a symlink even when it resolves to the expected mounted source"
