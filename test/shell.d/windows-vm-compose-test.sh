#!/bin/bash
# Security regression coverage for the Windows VM compose/mount boundary.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Bind mounts need CAP_SYS_ADMIN in a private mount namespace. Keep the
# caller's uid so the non-root development path is exercised.
if [[ ${OMARCHY_WINDOWS_TEST_NAMESPACE:-0} != 1 ]]; then
  if unshare --user --map-current-user --keep-caps --mount true 2>/dev/null; then
    exec env OMARCHY_WINDOWS_TEST_NAMESPACE=1 \
      unshare --user --map-current-user --keep-caps --mount --propagation private bash "$0"
  fi
  pass "unprivileged mount namespaces unavailable; skipping Windows VM mount runtime tests"
  exit 0
fi

TMPDIR=$(mktemp -d)
export OMARCHY_WINDOWS_DIR="$TMPDIR/win"
export HOME="$TMPDIR/home"
mkdir -p "$HOME"

set -- help
source "$ROOT/bin/omarchy-windows-vm" >/dev/null 2>&1
COMPOSE="$OMARCHY_WINDOWS_DIR/docker-compose.yml"

unmount_all() {
  local path
  resolve_caller >/dev/null 2>&1 || return 0
  for path in "$EXPECTED_SHARED" "$EXPECTED_STORAGE"; do
    while mountpoint -q -- "$path" 2>/dev/null; do umount -- "$path" || break; done
  done
}

cleanup() {
  set +e
  unmount_all
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

write() { # RAM CORES DISK USER PASS TZ
  printf 'RAM=%s\nCORES=%s\nDISK=%s\nUSERNAME=%s\nPASSWORD=%s\nTZ=%s\n' \
    "$@" | __priv_write_compose
}

fd_count() { find "/proc/$$/fd" -mindepth 1 -maxdepth 1 -printf x | wc -c; }

reset_case() {
  unmount_all
  rm -rf "$OMARCHY_WINDOWS_DIR" "$HOME/.windows" "$HOME/Windows"
  mkdir -p "$HOME"
}

# Fixed protected anchors consume the pinned source inodes.
prepare_user_mount_sources
write 4G 2 64G alice s3cret Europe/Copenhagen
resolve_caller
[[ -f $COMPOSE ]] || fail "writer produced a compose file"
grep -q 'image: dockurr/windows' "$COMPOSE" || fail "image is pinned"
grep -q -- '- NET_ADMIN' "$COMPOSE" || fail "cap_add is pinned"
grep -q -- "- $EXPECTED_STORAGE:/storage" "$COMPOSE" || fail "storage uses the protected anchor"
grep -q -- "- $EXPECTED_SHARED:/shared" "$COMPOSE" || fail "shared uses the protected anchor"
grep -q 'PROTECT: "Y"' "$COMPOSE" || fail "web console is not password protected"
[[ ! -L $HOME/.windows && ! -L $HOME/Windows ]] || fail "fresh sources stay real directories"
[[ $(stat -Lc '%d:%i' "$HOME/.windows") == $(stat -Lc '%d:%i' "$EXPECTED_STORAGE") ]] || fail "storage bind did not pin source"
[[ $(stat -Lc '%d:%i' "$HOME/Windows") == $(stat -Lc '%d:%i' "$EXPECTED_SHARED") ]] || fail "shared bind did not pin source"
[[ $(stat -Lc '%a' "$EXPECTED_STORAGE") == 700 && $(stat -Lc '%a' "$EXPECTED_SHARED") == 700 ]] || fail "mount leaves are not private"
grep -q -- '- /:/' "$COMPOSE" && fail "compose contains host-root bind"
pass "writer emits fixed anchors bound to exact private source inodes"

# Input cannot widen a mount or compose field.
rm -f "$COMPOSE"
write 4G 2 64G 'x -v /:/h' p UTC 2>/dev/null && fail "malicious username accepted"
[[ ! -f $COMPOSE ]] || fail "bad input wrote compose"
printf 'RAM=4G\nCORES=2\nDISK=64G\nUSERNAME=ok\nPASSWORD=p\nTZ=UTC\nSTORAGE=/\nSHARED=/etc\n' | __priv_write_compose
grep -q -- "- $EXPECTED_STORAGE:/storage" "$COMPOSE" || fail "caller storage affected compose"
grep -q -- '- /:/storage' "$COMPOSE" && fail "host root accepted as storage"
write '4G; rm -rf /' 2 64G ok p UTC 2>/dev/null && fail "malicious RAM accepted"
pass "input cannot inject a host path or compose field"

tricky='p@$$w:rd$HOME"x\y'
write 8G 4 64G bob "$tricky" UTC
grep -q 'PASSWORD: ".*\$\$.*"' "$COMPOSE" || fail "dollar not escaped"
[[ $(unescape "$(read_compose_value PASSWORD "$COMPOSE")") == "$tricky" ]] || fail "password did not round-trip"
pass "password with quote, backslash, and dollar round-trips"

for action in write_compose up up_wait down status remove; do
  valid_priv_action "$action" || fail "known action rejected: $action"
done
for action in '/../evil/x' bogus 'up;rm' '' '__priv_up'; do
  valid_priv_action "$action" && fail "action whitelist accepted: [$action]"
done
pass "privileged action dispatch is allowlisted"

# A PATH symlink to bash must never become the pkexec target. Hide the packaged
# file from priv_target's stat checks to exercise the historical fallback.
attack_bin="$TMPDIR/attack-bin"
mkdir -p "$attack_bin"
ln -s /bin/bash "$attack_bin/omarchy-windows-vm"
printf 'printf exploited >"$TMPDIR/exploited"\n' >"$TMPDIR/__priv"
stat() {
  [[ ${!#} == /usr/bin/omarchy-windows-vm ]] && return 1
  command stat "$@"
}
PATH="$attack_bin:$PATH" priv_target >/dev/null 2>&1 && fail "PATH symlink became a privileged target"
unset -f stat
[[ ! -e $TMPDIR/exploited ]] || fail "attacker __priv script executed"
pass "pkexec target is only the canonical packaged regular file, never a PATH symlink"

# Legacy migration keeps directories and legitimate symlinks in place.
reset_case
external_shared="$TMPDIR/external-shared"
mkdir -m 0755 -p "$HOME/.windows" "$external_shared" "$HOME/.config/windows"
ln -s "$external_shared" "$HOME/Windows"
touch "$HOME/.windows/existing-disk" "$external_shared/existing-shared-file"
LEGACY_COMPOSE_FILE="$HOME/.config/windows/docker-compose.yml"
COMPOSE_FILE="$COMPOSE"
cat >"$LEGACY_COMPOSE_FILE" <<'LEG'
services:
  windows:
    environment:
      RAM_SIZE: "16G"
      CPU_CORES: "6"
      DISK_SIZE: "128G"
      USERNAME: "legacyuser"
      PASSWORD: "legacypass"
      TZ: "America/New_York"
    volumes:
      - /./:/storage
      - /etc:/shared
LEG
priv() { local action=$1; shift; "__priv_$action" "$@"; }
migrate_legacy_compose
resolve_caller
[[ -f $COMPOSE ]] || fail "migration did not write compose"
grep -q 'USERNAME: "legacyuser"' "$COMPOSE" || fail "migration lost settings"
[[ -f $HOME/.windows/existing-disk && -f $external_shared/existing-shared-file ]] || fail "migration lost data"
[[ ! -L $HOME/.windows && $(readlink "$HOME/Windows") == "$external_shared" ]] || fail "migration consumed source path"
[[ $(stat -Lc '%a' "$HOME/.windows") == 700 && $(stat -Lc '%a' "$external_shared") == 700 ]] || fail "migration did not harden legacy directories"
grep -q -- '- /:/' "$COMPOSE" && fail "migration copied malicious storage"
grep -q -- '- /etc:/shared' "$COMPOSE" && fail "migration copied malicious share"
[[ ! -f $LEGACY_COMPOSE_FILE ]] || fail "migration left legacy compose"
pass "migration preserves data and symlinks while hardening permissions"

# Bring-up re-proves compose trust, cardinality, and mounted identities.
assert_mounts_safe || fail "verified sources rejected"
sed -i "s|$EXPECTED_SHARED:/shared|/etc:/shared|" "$COMPOSE"
assert_mounts_safe 2>/dev/null && fail "tampered host path accepted"
sed -i "s|/etc:/shared|$EXPECTED_SHARED:/shared|" "$COMPOSE"
printf '      - %s:/storage\n' "$EXPECTED_STORAGE" >>"$COMPOSE"
assert_mounts_safe 2>/dev/null && fail "duplicate destination accepted"
write 16G 6 128G legacyuser legacypass America/New_York
sed -i 's/PROTECT: "Y"/PROTECT: "N"/' "$COMPOSE"
assert_mounts_safe 2>/dev/null && fail "unprotected web console accepted"
sed -i 's/PROTECT: "N"/PROTECT: "Y"/' "$COMPOSE"
printf '      PROTECT: "N"\n' >>"$COMPOSE"
assert_mounts_safe 2>/dev/null && fail "duplicate web protection setting accepted"
sed -i '$d' "$COMPOSE"
chmod 0666 "$COMPOSE"
assert_mounts_safe 2>/dev/null && fail "writable compose accepted"
chmod 0640 "$COMPOSE"
pass "bring-up rejects tampered, duplicate, unprotected, and writable compose inputs"

# Both sources are pinned before a bind; bad symlinks stay untouched.
reset_case
mkdir -p "$HOME/.windows"
ln -s / "$HOME/Windows"
before_fds=$(fd_count)
prepare_user_mount_sources 2>/dev/null && fail "root symlink passed user preflight"
[[ -L $HOME/Windows && $(readlink "$HOME/Windows") == / ]] || fail "rejected symlink consumed"
printf 'RAM=4G\nCORES=2\nDISK=64G\nUSERNAME=x\nPASSWORD=p\nTZ=UTC\n' | __priv_write_compose 2>/dev/null && fail "root symlink passed privileged preflight"
resolve_caller
[[ $(mount_layer_count "$EXPECTED_STORAGE") == 0 && $(mount_layer_count "$EXPECTED_SHARED") == 0 ]] || fail "one source mounted before other failed"
[[ $(fd_count) == "$before_fds" ]] || fail "source preflight leaked FD"
find "$CALLER_DATA_ROOT" -name 'rejected-*' -print -quit | grep -q . && fail "source was quarantined"
pass "invalid second source leaves paths and anchors untouched and leaks no FD"

# Distinct caller-owned symlink targets are supported and remain links.
reset_case
external_storage="$TMPDIR/external-storage"
external_shared2="$TMPDIR/external-shared-2"
mkdir -p "$external_storage" "$external_shared2"
ln -s "$external_storage" "$HOME/.windows"
ln -s "$external_shared2" "$HOME/Windows"
prepare_user_mount_sources
write 4G 2 64G symlinked pw UTC
resolve_caller
[[ $(readlink "$HOME/.windows") == "$external_storage" && $(readlink "$HOME/Windows") == "$external_shared2" ]] || fail "writer replaced symlinks"
[[ $(stat -Lc '%d:%i' "$EXPECTED_STORAGE") == $(stat -Lc '%d:%i' "$external_storage") ]] || fail "symlink target not pinned"
pass "legitimate caller-owned symlinks remain in place"

# Reproduce the original post-validation race at the last possible moment:
# replace the familiar shared path with / only after the final guard returns,
# inside the mocked Docker Compose invocation. Compose must still consume the
# protected anchor bound to the inode that was validated earlier.
raced_shared="$HOME/Windows.before-race"
shared_id_before_race=$(stat -Lc '%d:%i' "$external_shared2")
race_ran=0
dc() {
  [[ $1 == up && ${2:-} == -d ]] || return 1
  mv -T -- "$HOME/Windows" "$raced_shared"
  ln -s / "$HOME/Windows"
  race_ran=1
  [[ $(get_mount_source /shared) == "$EXPECTED_SHARED" ]] || return 1
  [[ $(stat -Lc '%d:%i' "$EXPECTED_SHARED") == "$shared_id_before_race" ]] || return 1
}
__priv_up || fail "post-validation home-path swap changed the Docker mount source"
(( race_ran == 1 )) || fail "post-validation race hook did not run"
[[ -L $HOME/Windows && $(readlink "$HOME/Windows") == / ]] || fail "race did not replace the familiar shared path"
rm "$HOME/Windows"
mv -T -- "$raced_shared" "$HOME/Windows"
unset -f dc
pass "a post-validation path swap cannot redirect Docker away from the pinned shared inode"

# Run the same attack as a genuinely concurrent process. A successful bring-up
# deliberately waits inside the Docker boundary until the attacker has replaced
# the familiar path with /, then verifies that the real bind anchor still names
# the caller-owned directory that was pinned before the race.
reset_case
prepare_user_mount_sources
touch "$HOME/Windows/safe-marker"
write 4G 2 64G concurrent pw UTC
resolve_caller
concurrent_shared_id=$(stat -Lc '%d:%i' "$HOME/Windows")
host_root_id=$(stat -Lc '%d:%i' /)
race_source="$HOME/Windows.race-source"
race_stop="$TMPDIR/stop-concurrent-race"
race_swaps="$TMPDIR/concurrent-race-swaps"
(
  set +e
  while [[ ! -e $race_stop ]]; do
    if [[ -d $HOME/Windows && ! -L $HOME/Windows ]] && mv -T -- "$HOME/Windows" "$race_source" 2>/dev/null; then
      ln -s / "$HOME/Windows" 2>/dev/null || true
      printf x >>"$race_swaps"
      sleep 0.002
    fi
    if [[ -L $HOME/Windows ]]; then
      rm -f -- "$HOME/Windows"
      mv -T -- "$race_source" "$HOME/Windows" 2>/dev/null || true
      sleep 0.005
    fi
  done
) &
racer_pid=$!
concurrent_dc_calls=0
dc() {
  local attempt
  [[ $1 == up && ${2:-} == -d ]] || return 1
  for ((attempt = 0; attempt < 20000; attempt++)); do
    if [[ -L $HOME/Windows && $(readlink "$HOME/Windows" 2>/dev/null) == / ]]; then
      break
    fi
  done
  [[ -L $HOME/Windows && $(readlink "$HOME/Windows" 2>/dev/null) == / ]] || return 1
  ((concurrent_dc_calls++))
  [[ $(get_mount_source /shared) == "$EXPECTED_SHARED" ]] || return 1
  [[ $(stat -Lc '%d:%i' "$EXPECTED_SHARED") == "$concurrent_shared_id" ]] || return 1
  [[ $(stat -Lc '%d:%i' "$EXPECTED_SHARED") != "$host_root_id" ]] || return 1
  [[ -f $EXPECTED_SHARED/safe-marker ]]
}
for ((attempt = 0; attempt < 200; attempt++)); do
  if __priv_up 2>/dev/null; then break; fi
done
touch "$race_stop"
wait "$racer_pid"
unset -f dc
if [[ -L $HOME/Windows ]]; then rm -f -- "$HOME/Windows"; fi
if [[ ! -e $HOME/Windows && -d $race_source ]]; then mv -T -- "$race_source" "$HOME/Windows"; fi
[[ -s $race_swaps ]] || fail "concurrent attacker never swapped the shared path"
((concurrent_dc_calls > 0)) || fail "concurrent race never reached Docker while the familiar path named host root"
[[ $(stat -Lc '%d:%i' "$EXPECTED_SHARED") == "$concurrent_shared_id" ]] || fail "concurrent race changed the protected shared inode"
pass "a concurrent home-path swap cannot redirect Docker away from the pinned shared inode"

# Same-inode sources fail before mounting and close both descriptors.
reset_case
same="$TMPDIR/same-source"
mkdir -p "$same"
ln -s "$same" "$HOME/.windows"
ln -s "$same" "$HOME/Windows"
before_fds=$(fd_count)
prepare_user_mount_sources 2>/dev/null && fail "same source passed user preflight"
printf 'RAM=4G\nCORES=2\nDISK=64G\nUSERNAME=x\nPASSWORD=p\nTZ=UTC\n' | __priv_write_compose 2>/dev/null && fail "same source passed root preflight"
resolve_caller
[[ $(mount_layer_count "$EXPECTED_STORAGE") == 0 && $(mount_layer_count "$EXPECTED_SHARED") == 0 ]] || fail "same source left mount"
[[ $(fd_count) == "$before_fds" ]] || fail "same source leaked FDs"
pass "storage and shared must differ and failure closes FDs"

# Ancestor/descendant aliases are just as destructive as same-inode aliases:
# removal must never recurse from storage into shared (or accept the inverse).
reset_case
shared_inside="$TMPDIR/shared-inside-storage"
mkdir -p "$shared_inside/storage/shared"
ln -s "$shared_inside/storage" "$HOME/.windows"
ln -s "$shared_inside/storage/shared" "$HOME/Windows"
prepare_user_mount_sources
before_fds=$(fd_count)
write 4G 2 64G nested pw UTC 2>/dev/null && fail "shared-inside-storage sources were accepted"
resolve_caller
[[ $(mount_layer_count "$EXPECTED_STORAGE") == 0 && $(mount_layer_count "$EXPECTED_SHARED") == 0 ]] || fail "shared-inside-storage failure left a mount"
[[ $(fd_count) == "$before_fds" ]] || fail "shared-inside-storage failure leaked FDs"

reset_case
storage_inside="$TMPDIR/storage-inside-shared"
mkdir -p "$storage_inside/shared/storage"
ln -s "$storage_inside/shared/storage" "$HOME/.windows"
ln -s "$storage_inside/shared" "$HOME/Windows"
prepare_user_mount_sources
before_fds=$(fd_count)
write 4G 2 64G nested pw UTC 2>/dev/null && fail "storage-inside-shared sources were accepted"
resolve_caller
[[ $(mount_layer_count "$EXPECTED_STORAGE") == 0 && $(mount_layer_count "$EXPECTED_SHARED") == 0 ]] || fail "storage-inside-shared failure left a mount"
[[ $(fd_count) == "$before_fds" ]] || fail "storage-inside-shared failure leaked FDs"
pass "pinned-FD ancestry checks reject overlap in both directions before mounting"

# Exact bind-alias bypass regression: the shared FD's visible parent is the
# alias directory, but its inode is still reachable below storage.
reset_case
alias_under="$TMPDIR/bind-alias-under"
alias_shared="$TMPDIR/bind-alias-shared"
mkdir -p "$alias_under/storage/shared" "$alias_shared"
mount --no-canonicalize --bind "$alias_under/storage/shared" "$alias_shared"
ln -s "$alias_under/storage" "$HOME/.windows"
ln -s "$alias_shared" "$HOME/Windows"
prepare_user_mount_sources
before_fds=$(fd_count)
resolve_caller
open_mount_source "$LEGACY_STORAGE" storage
alias_storage_fd=$OPENED_MOUNT_FD
alias_storage_id=$OPENED_MOUNT_ID
open_mount_source "$LEGACY_SHARED" shared
alias_shared_fd=$OPENED_MOUNT_FD
pinned_dir_contains "$alias_storage_id" "$alias_shared_fd" && fail "bind-alias repro unexpectedly shared the underlying parent walk"
pinned_tree_contains "$alias_storage_fd" "$alias_shared_fd" || fail "tree-rooted discovery missed the bind-alias inode"
exec {alias_storage_fd}<&-
exec {alias_shared_fd}<&-
write 4G 2 64G alias pw UTC
resolve_caller
touch "$HOME/.windows/disk.img" "$HOME/Windows/keep.txt"
dc() { :; }
docker() { [[ $1 == inspect ]] && return 1; :; }
__priv_remove 2>/dev/null && fail "removal accepted a shared bind alias into storage"
[[ -f $HOME/.windows/disk.img && -f $HOME/Windows/keep.txt && -f $COMPOSE ]] || fail "bind-alias removal refusal changed state"
[[ $(mount_layer_count "$EXPECTED_STORAGE") == 1 && $(mount_layer_count "$EXPECTED_SHARED") == 1 ]] || fail "bind-alias removal refusal changed mounts"
[[ $(fd_count) == "$before_fds" ]] || fail "bind-alias removal refusal leaked FDs"
unmount_all
umount -- "$alias_shared"
pass "cheap startup permits a bind alias, but bounded removal discovery refuses it"

# A late writer failure rolls back both newly-created binds.
reset_case
prepare_user_mount_sources
mv() { return 1; }
write 4G 2 64G rollback pw UTC 2>/dev/null && fail "forced writer failure succeeded"
unset -f mv
resolve_caller
[[ $(mount_layer_count "$EXPECTED_STORAGE") == 0 && $(mount_layer_count "$EXPECTED_SHARED") == 0 ]] || fail "writer failure left binds"
[[ ! -f $COMPOSE ]] || fail "writer failure replaced compose"
pass "atomic writer failure rolls back both new bind mounts"

# Revalidate ancestry during removal: move the already-bound shared inode below
# storage, keep its familiar path as a symlink, and prove nothing is deleted.
reset_case
prepare_user_mount_sources
write 4G 2 64G moved pw UTC
touch "$HOME/.windows/disk.img" "$HOME/Windows/keep.txt"
mv "$HOME/Windows" "$HOME/.windows/moved-shared"
ln -s "$HOME/.windows/moved-shared" "$HOME/Windows"
dc() { :; }
docker() { [[ $1 == inspect ]] && return 1; :; }
__priv_remove 2>/dev/null && fail "removal accepted a shared inode moved below storage"
[[ -f $HOME/.windows/disk.img && -f $HOME/.windows/moved-shared/keep.txt && -f $COMPOSE ]] || fail "overlap rejection changed disk, shared data, or compose"
pass "removal revalidates pinned ancestry and leaves moved shared data untouched"

# Even when both familiar paths remain disjoint, a same-filesystem bind of the
# pinned shared inode introduced below storage must stop removal before change.
reset_case
prepare_user_mount_sources
write 4G 2 64G removal-alias pw UTC
touch "$HOME/.windows/disk.img" "$HOME/Windows/keep.txt"
mkdir "$HOME/.windows/shared-bind-alias"
mount --no-canonicalize --bind "$HOME/Windows" "$HOME/.windows/shared-bind-alias"
__priv_remove 2>/dev/null && fail "removal missed a shared bind alias introduced below storage"
[[ -f $HOME/.windows/disk.img && -f $HOME/Windows/keep.txt && -f $COMPOSE ]] || fail "removal bind-alias rejection changed state"
umount -- "$HOME/.windows/shared-bind-alias"
pass "removal tree discovery catches a shared alias not used by either home path"

# A direct alias on another filesystem is still visited by find -xdev at its
# mountpoint and must be rejected, while unrelated separate filesystems remain
# supported by the root suite.
reset_case
prepare_user_mount_sources
mount -t tmpfs -o uid="$(id -u)",gid="$(id -g)",mode=0700,size=8m crossdev-shared "$HOME/Windows"
touch "$HOME/Windows/keep.txt"
write 4G 2 64G crossdev-alias pw UTC
touch "$HOME/.windows/disk.img"
mkdir "$HOME/.windows/crossdev-shared-alias"
mount --no-canonicalize --bind "$HOME/Windows" "$HOME/.windows/crossdev-shared-alias"
__priv_remove 2>/dev/null && fail "removal missed a different-device shared alias below storage"
[[ -f $HOME/.windows/disk.img && -f $HOME/Windows/keep.txt && -f $COMPOSE ]] || fail "cross-device alias rejection changed state"
umount -- "$HOME/.windows/crossdev-shared-alias"
unmount_all
umount -- "$HOME/Windows"
pass "removal catches a direct different-filesystem shared alias at the xdev boundary"

# Recursive alias discovery is destructive-removal-only and bounded. A hung or
# failing scanner must fail closed before the disk, share, compose, or mounts
# are changed.
reset_case
prepare_user_mount_sources
write 4G 2 64G scan-failure pw UTC
touch "$HOME/.windows/disk.img" "$HOME/Windows/keep.txt"
scan_helper="$TMPDIR/tree-scan-helper"
saved_tree_scan_find=$TREE_SCAN_FIND
saved_tree_scan_timeout=$TREE_SCAN_TIMEOUT_SECONDS
saved_tree_scan_kill_after=$TREE_SCAN_KILL_AFTER_SECONDS
printf '#!/bin/bash\n/bin/sleep 10\n' >"$scan_helper"
chmod 0700 "$scan_helper"
TREE_SCAN_FIND=$scan_helper
TREE_SCAN_TIMEOUT_SECONDS=0.05
TREE_SCAN_KILL_AFTER_SECONDS=0.05
__priv_remove 2>/dev/null && fail "removal continued after its containment scan timed out"
[[ -f $HOME/.windows/disk.img && -f $HOME/Windows/keep.txt && -f $COMPOSE ]] || fail "timed-out containment scan changed state"
[[ $(mount_layer_count "$EXPECTED_STORAGE") == 1 && $(mount_layer_count "$EXPECTED_SHARED") == 1 ]] || fail "timed-out containment scan changed mounts"

printf '#!/bin/bash\nexit 42\n' >"$scan_helper"
__priv_remove 2>/dev/null && fail "removal continued after its containment scanner failed"
[[ -f $HOME/.windows/disk.img && -f $HOME/Windows/keep.txt && -f $COMPOSE ]] || fail "failed containment scan changed state"
[[ $(mount_layer_count "$EXPECTED_STORAGE") == 1 && $(mount_layer_count "$EXPECTED_SHARED") == 1 ]] || fail "failed containment scan changed mounts"
TREE_SCAN_FIND=$saved_tree_scan_find
TREE_SCAN_TIMEOUT_SECONDS=$saved_tree_scan_timeout
TREE_SCAN_KILL_AFTER_SECONDS=$saved_tree_scan_kill_after
pass "removal scan timeout and errors fail closed without changing VM state"

# Removal rejects stacks, then deletes disk only through verified binds.
reset_case
prepare_user_mount_sources
write 4G 2 64G remove pw UTC
resolve_caller
touch "$HOME/.windows/disk.img" "$HOME/Windows/keep.txt"
mount --no-canonicalize --bind "$HOME/.windows" "$EXPECTED_STORAGE"
dc() { :; }
docker() { [[ $1 == inspect ]] && return 1; :; }
__priv_remove 2>/dev/null && fail "removal accepted stacked storage mount"
[[ -f $HOME/.windows/disk.img && -f $HOME/Windows/keep.txt && -f $COMPOSE ]] || fail "rejected removal changed state"
umount -- "$EXPECTED_STORAGE"
dc() { return 1; }
__priv_remove 2>/dev/null && fail "removal deleted data after docker-compose down failed"
[[ -f $HOME/.windows/disk.img && -f $HOME/Windows/keep.txt && -f $COMPOSE ]] || fail "failed down changed data or compose"
dc() { :; }
__priv_remove
[[ ! -e $HOME/.windows/disk.img ]] || fail "removal preserved disk data"
[[ -e $HOME/Windows/keep.txt ]] || fail "removal deleted shared data"
[[ ! -f $COMPOSE ]] || fail "removal left compose"
resolve_caller
[[ $(mount_layer_count "$EXPECTED_STORAGE") == 0 && $(mount_layer_count "$EXPECTED_SHARED") == 0 ]] || fail "removal left binds"
pass "removal rejects stacks, deletes disk, and preserves shared files"

# Credentials replace a planted link rather than following it, and a failed
# atomic rename preserves the last complete private file.
credentials_dir="$TMPDIR/credentials"
CREDENTIALS_FILE="$credentials_dir/credentials"
credentials_victim="$TMPDIR/credentials-victim"
mkdir -m 0755 -p "$credentials_dir"
printf 'victim\n' >"$credentials_victim"
ln -s "$credentials_victim" "$CREDENTIALS_FILE"
write_credentials carol 'p=a$$w"x'
[[ -f $CREDENTIALS_FILE && ! -L $CREDENTIALS_FILE ]] || fail "credentials did not replace a planted symlink"
[[ $(stat -c '%a' "$credentials_dir") == 700 && $(stat -c '%a' "$CREDENTIALS_FILE") == 600 ]] || fail "credentials path is not private"
[[ $(cat "$credentials_victim") == victim ]] || fail "credentials write changed a symlink victim"
[[ $(read_credential USERNAME) == carol && $(read_credential PASSWORD) == 'p=a$$w"x' ]] || fail "credentials did not round-trip"
credentials_before=$(cat "$CREDENTIALS_FILE")
mv() { return 1; }
write_credentials changed replacement 2>/dev/null && fail "forced credentials rename failure succeeded"
unset -f mv
[[ $(cat "$CREDENTIALS_FILE") == "$credentials_before" ]] || fail "failed credentials rename replaced the live file"
! find "$credentials_dir" -name '.credentials.*' -print -quit | grep -q . || fail "failed credentials write left a temporary file"
pass "credentials are atomically replaced as a private regular file"

# Free-space accounting follows the real storage target.
reset_case
mkdir -p "$external_storage" "$HOME/Windows"
ln -s "$external_storage" "$HOME/.windows"
prepare_user_mount_sources
df_log="$TMPDIR/df-path"
df() {
  printf '%s\n' "${!#}" >"$df_log"
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\nmock 104857600 0 94371840 0%% /mock\n'
}
[[ $(available_storage_gb) == 90 ]] || fail "free-space parsed wrong value"
unset -f df
[[ $(cat "$df_log") == "$external_storage" ]] || fail "free-space used home filesystem"
pass "disk-space checks follow the storage symlink target"
