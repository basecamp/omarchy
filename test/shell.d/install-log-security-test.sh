#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command unshare
require_command mount
require_command setpriv

subuid_start=$(awk -F: -v user="$(id -un)" '$1 == user && $3 >= 2 { print $2; exit }' /etc/subuid)
subgid_start=$(awk -F: -v user="$(id -un)" '$1 == user && $3 >= 2 { print $2; exit }' /etc/subgid)
[[ $subuid_start =~ ^[0-9]+$ && $subgid_start =~ ^[0-9]+$ ]] ||
  fail "a subordinate uid/gid range is available for the cross-UID regression"
userns=(unshare --user --map-user=0 --map-group=0 \
  --map-users="1:${subuid_start}:2" --map-groups="1:${subgid_start}:2" --mount)

test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

safe_dir="$test_dir/safe"
mkdir -m 0700 "$safe_dir"
log_file="$safe_dir/install.log"

# A permissive caller umask must not escape into the first inode. Repeated
# starts retain prior bytes, replace the inode, and keep debug append behavior.
(
  umask 000
  export OMARCHY_INSTALL_LOG_FILE="$log_file"
  export OMARCHY_START_TIME='2026-08-31 00:00:00'
  export OMARCHY_START_EPOCH=0
  source "$ROOT/install/helpers/logging.sh"
  start_install_log
)
[[ -f $log_file && ! -L $log_file ]] || fail "fresh installer log is a regular file"
[[ $(stat -c '%u:%a' "$log_file") == "$(id -u):600" ]] || fail "fresh installer log is not privately owned from creation"
printf 'LEGITIMATE EXISTING CONTENT\n' >>"$log_file"
first_inode=$(stat -c %i "$log_file")
printf 'printf "DEBUG APPEND CONTENT\\n"\n' >"$test_dir/debug-step.sh"
(
  export OMARCHY_INSTALL_LOG_FILE="$log_file"
  export OMARCHY_START_TIME='2026-08-31 00:00:01'
  export OMARCHY_START_EPOCH=0
  export OMARCHY_INSTALL_DEBUG=1
  source "$ROOT/install/helpers/logging.sh"
  start_install_log
  run_logged "$test_dir/debug-step.sh"
) 2>/dev/null &
runner=$!
wait "$runner"
second_inode=$(stat -c %i "$log_file")
[[ $first_inode != "$second_inode" ]] || fail "rerun reused the old installer-log inode"
grep -qF 'LEGITIMATE EXISTING CONTENT' "$log_file" || fail "rerun lost existing installer log content"
grep -qF 'DEBUG APPEND CONTENT' "$log_file" || fail "debug-mode command output no longer appends"
[[ $(stat -c %a "$log_file") == 600 ]] || fail "rerun weakened installer log permissions"
pass "fresh, rerun, append, and debug logging retain a private fresh inode"

prepare_line=$(grep -nF 'prepare_install_log_file' "$ROOT/bin/omarchy-apply-hardware" | cut -d: -f1)
hardware_line=$(grep -nF 'source "$OMARCHY_INSTALL/hardware/all.sh"' "$ROOT/bin/omarchy-apply-hardware" | cut -d: -f1)
[[ $prepare_line =~ ^[0-9]+$ && $hardware_line =~ ^[0-9]+$ && $prepare_line -lt $hardware_line ]] ||
  fail "standalone hardware logging appends before the private lifecycle"
pass "standalone hardware application secures the shared root log before append"

# stdout/chroot-style logging bypasses the file lifecycle intentionally.
stdout_target="$safe_dir/stdout-only.log"
OMARCHY_INSTALL_LOG_FILE="$stdout_target" OMARCHY_LOG_TO_STDOUT=1 \
  OMARCHY_START_TIME='2026-08-31 00:00:02' OMARCHY_START_EPOCH=0 \
  bash -c 'source "$1"; start_install_log' bash "$ROOT/install/helpers/logging.sh" >"$test_dir/stdout"
[[ ! -e $stdout_target ]] || fail "stdout logging created a root-side file"
grep -qF 'Omarchy Setup Started' "$test_dir/stdout" || fail "stdout logging lost its start marker"
pass "stdout install logging remains supported without publishing a file"

# Symlinks, special files, and unsafe destination/parent spellings fail before
# their referents are opened or altered.
victim="$safe_dir/victim"
printf 'VICTIM UNCHANGED\n' >"$victim"
ln -s victim "$safe_dir/symlink.log"
if OMARCHY_INSTALL_LOG_FILE="$safe_dir/symlink.log" bash -c 'source "$1"; start_install_log' bash \
  "$ROOT/install/helpers/logging.sh" >"$test_dir/symlink.out" 2>&1; then
  fail "installer logging accepted a symlink target"
fi
[[ $(<"$victim") == 'VICTIM UNCHANGED' && -L $safe_dir/symlink.log ]] || fail "symlink rejection altered its victim"
mkfifo "$safe_dir/fifo.log"
if OMARCHY_INSTALL_LOG_FILE="$safe_dir/fifo.log" bash -c 'source "$1"; start_install_log' bash \
  "$ROOT/install/helpers/logging.sh" >"$test_dir/fifo.out" 2>&1; then
  fail "installer logging accepted a FIFO"
fi
[[ -p $safe_dir/fifo.log ]] || fail "FIFO rejection removed the anomaly"
unsafe_parent="$test_dir/world-writable"
mkdir -m 0777 "$unsafe_parent"
if OMARCHY_INSTALL_LOG_FILE="$unsafe_parent/install.log" bash -c 'source "$1"; start_install_log' bash \
  "$ROOT/install/helpers/logging.sh" >"$test_dir/parent.out" 2>&1; then
  fail "installer logging accepted an attacker-writable parent"
fi
if OMARCHY_INSTALL_LOG_FILE="$safe_dir/../safe/noncanonical.log" bash -c 'source "$1"; start_install_log' bash \
  "$ROOT/install/helpers/logging.sh" >"$test_dir/noncanonical.out" 2>&1; then
  fail "installer logging accepted a non-canonical override"
fi
pass "symlink, nonregular, and unsafe override boundaries fail closed"

# Run the cross-UID checks as namespace root, with a new root-owned sticky /tmp
# so the production parent validator sees the same ownership model as a host.
"${userns[@]}" /usr/bin/bash -s 3<"$ROOT/install/helpers/logging.sh" <<'NAMESPACE'
set -euo pipefail
mount -t tmpfs -o mode=1777 tmpfs /tmp
/usr/bin/cp /usr/bin/stat /tmp/real-stat
cat >/tmp/namespace-stat <<'STUB'
#!/bin/bash
last=${!#}
# Host root is deliberately unmapped in this unprivileged namespace. It is
# still the trusted owner of the real / inode, so expose that equivalent uid.
if [[ $1 == -c && $2 == %u && $last == / ]]; then printf '0\n'; else exec /tmp/real-stat "$@"; fi
STUB
chmod 0755 /tmp/namespace-stat
mount --bind /tmp/namespace-stat /usr/bin/stat
mkdir -m 0755 /tmp/safe
source /dev/fd/3

export OMARCHY_INSTALL_LOG_FILE=/tmp/safe/install.log
printf 'LEGITIMATE BEFORE REPLACEMENT\n' >"$OMARCHY_INSTALL_LOG_FILE"
chmod 0666 "$OMARCHY_INSTALL_LOG_FILE"

# A second uid can exploit the old release before repair.
setpriv --reuid=1 --regid=1 --clear-groups /usr/bin/bash -c \
  'grep -q LEGITIMATE "$1" && printf "SECOND UID BEFORE\\n" >>"$1"' bash "$OMARCHY_INSTALL_LOG_FILE"

mkdir -m 0777 /tmp/control
setpriv --reuid=1 --regid=1 --clear-groups /usr/bin/bash -c '
  exec 9>>"$1"
  : >"$2/ready"
  while [[ ! -e $2/go ]]; do /usr/bin/sleep 0.01; done
  printf "STALE DESCRIPTOR WRITE\n" >&9
' bash "$OMARCHY_INSTALL_LOG_FILE" /tmp/control &
foreign_writer=$!
for _ in {1..200}; do [[ -e /tmp/control/ready ]] && break; /usr/bin/sleep 0.01; done
[[ -e /tmp/control/ready ]]
old_inode=$(stat -c %i "$OMARCHY_INSTALL_LOG_FILE")
start_install_log
new_inode=$(stat -c %i "$OMARCHY_INSTALL_LOG_FILE")
[[ $old_inode != "$new_inode" && $(stat -c '%u:%a' "$OMARCHY_INSTALL_LOG_FILE") == 0:600 ]]
: >/tmp/control/go
wait "$foreign_writer"
! grep -qF 'STALE DESCRIPTOR WRITE' "$OMARCHY_INSTALL_LOG_FILE"
grep -qF 'SECOND UID BEFORE' "$OMARCHY_INSTALL_LOG_FILE"
! setpriv --reuid=1 --regid=1 --clear-groups /usr/bin/test -r "$OMARCHY_INSTALL_LOG_FILE"
! setpriv --reuid=1 --regid=1 --clear-groups /usr/bin/bash -c 'printf attack >>"$1"' bash "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null

# A foreign-owned regular target and a safe-looking child beneath a
# foreign-owned 0755 ancestor are both outside the trusted rename boundary.
printf 'FOREIGN FILE\n' >/tmp/safe/foreign.log
chown 1:1 /tmp/safe/foreign.log
chmod 0666 /tmp/safe/foreign.log
OMARCHY_INSTALL_LOG_FILE=/tmp/safe/foreign.log
! prepare_install_log_file 2>/dev/null
[[ $(stat -c '%u:%a' /tmp/safe/foreign.log) == 1:666 ]]
grep -qF 'FOREIGN FILE' /tmp/safe/foreign.log

mkdir -m 0755 /tmp/foreign-ancestor
chown 1:1 /tmp/foreign-ancestor
mkdir -m 0700 /tmp/foreign-ancestor/root-child
OMARCHY_INSTALL_LOG_FILE=/tmp/foreign-ancestor/root-child/install.log
! prepare_install_log_file 2>/dev/null
[[ ! -e $OMARCHY_INSTALL_LOG_FILE ]]
NAMESPACE
pass "cross-UID access, stale descriptors, foreign targets, and foreign ancestors are contained"

# If a required filesystem primitive fails after validating the old 0666
# target, the helper must not leave that stale-descriptor inode published at
# the canonical path.
for failed_primitive in chmod mktemp cat mv; do
  "${userns[@]}" /usr/bin/bash -s "$failed_primitive" \
    3<"$ROOT/install/helpers/logging.sh" <<'NAMESPACE'
set -euo pipefail
failed_primitive=$1
mount -t tmpfs -o mode=1777 tmpfs /tmp
/usr/bin/cp /usr/bin/stat /tmp/real-stat
cat >/tmp/namespace-stat <<'STUB'
#!/bin/bash
last=${!#}
if [[ $1 == -c && $2 == %u && $last == / ]]; then printf '0\n'; else exec /tmp/real-stat "$@"; fi
STUB
chmod 0755 /tmp/namespace-stat
mount --bind /tmp/namespace-stat /usr/bin/stat
mkdir -m 0755 /tmp/safe
source /dev/fd/3
export OMARCHY_INSTALL_LOG_FILE=/tmp/safe/install.log
printf 'UNTRUSTED LEGACY CONTENT\n' >"$OMARCHY_INSTALL_LOG_FILE"
chmod 0666 "$OMARCHY_INSTALL_LOG_FILE"
printf '#!/bin/bash\nexit 70\n' >/tmp/fail-command
chmod 0755 /tmp/fail-command
mount --bind /tmp/fail-command "/usr/bin/$failed_primitive"
! prepare_install_log_file 2>/tmp/error
[[ ! -e $OMARCHY_INSTALL_LOG_FILE && ! -L $OMARCHY_INSTALL_LOG_FILE ]]
NAMESPACE
done
pass "filesystem failures detach the formerly public installer-log inode"

# Model a desktop user collecting the new root-only log. The sudo stand-in is
# setuid root inside this disposable namespace and publishes a reusable token
# only when -N is absent. A hostile fastfetch child polls that token exactly as
# a detached user collector could on a real desktop.
"${userns[@]}" /usr/bin/bash -s "$ROOT" <<'NAMESPACE'
set -euo pipefail
repo=$1
proof=$(mktemp -d)
mount -t tmpfs -o mode=0755,suid tmpfs "$proof"
mkdir -p "$proof/bin" "$proof/home" "$proof/root"
chmod 0755 "$proof" "$proof/bin" "$proof/root"
chown 1:1 "$proof/home"
chmod 0700 "$proof/home"

cat >"$proof/sudo.c" <<'C'
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char *need(const char *name) {
  const char *value = getenv(name);
  if (!value || !*value) exit(125);
  return value;
}

int main(int argc, char **argv) {
  const char *token = need("TEST_SUDO_TOKEN");
  int index = 1, no_update = 0, noninteractive = 0, fd;
  if (argc == 2 && !strcmp(argv[1], "-h")) {
    fputs("usage: sudo [-ABbEHkNnPS] command\n", stdout);
    return 0;
  }
  if (setgid(0) || setuid(0)) return 120;
  if (index < argc && !strcmp(argv[index], "-N")) { no_update = 1; index++; }
  if (index < argc && !strcmp(argv[index], "-n")) { noninteractive = 1; index++; }
  if (index < argc && !strcmp(argv[index], "--")) index++;
  if (index < argc && !strcmp(argv[index], "-k")) {
    return unlink(token) && errno != ENOENT;
  }
  if (!no_update && access(token, F_OK)) {
    if (noninteractive) return 1;
    fd = open(token, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return 121;
    close(fd);
  }
  if (index + 2 < argc && !strcmp(argv[index], "/usr/bin/omarchy-upload-log") &&
      !strcmp(argv[index + 1], "__read-private-install-log")) {
    if (!strcmp(argv[index + 2], "live")) {
      fputs("private install fixture\n", stdout);
      return 0;
    }
    return !strcmp(argv[index + 2], "target") ? 3 : 2;
  }
  if (index >= argc) return 2;
  execv(argv[index], &argv[index]);
  return 126;
}
C
cc -O2 -Wall -Wextra -o "$proof/bin/sudo" "$proof/sudo.c"
chmod 4755 "$proof/bin/sudo"

cat >"$proof/bin/omarchy-cmd-present" <<'STUB'
#!/bin/bash
[[ ${1:-} == fastfetch ]]
STUB
cat >"$proof/bin/fastfetch" <<'STUB'
#!/bin/bash
: >"$TEST_COLLECTOR_RAN"
(
  while [[ -e $TEST_WAITER_ARMED ]]; do
    if "$TEST_SUDO" -n -- /usr/bin/touch "$TEST_ROOT_VICTIM" 2>/dev/null; then
      : >"$TEST_REUSED_SUDO"
      break
    fi
    /usr/bin/sleep 0.01
  done
) &
printf '%s\n' "$!" >"$TEST_WAITER_PID"
printf 'harmless fastfetch output\n'
STUB
cat >"$proof/bin/curl" <<'STUB'
#!/bin/bash
if [[ ${TEST_EXPECT_REUSE:-0} == 1 ]]; then
  for _ in {1..200}; do
    [[ -e $TEST_REUSED_SUDO ]] && break
    /usr/bin/sleep 0.01
  done
fi
printf 'https://logs.invalid/private\n'
STUB
chmod 0755 "$proof/bin/"*
chmod 4755 "$proof/bin/sudo"
sed "s#/usr/bin/sudo#$proof/bin/sudo#g" \
  "$repo/bin/omarchy-security-functions" >"$proof/bin/omarchy-security-functions"
sed "s#/usr/bin/sudo#$proof/bin/sudo#g" \
  "$repo/bin/omarchy-upload-log" >"$proof/bin/omarchy-upload-log"
chmod 0755 "$proof/bin/omarchy-security-functions" "$proof/bin/omarchy-upload-log"

run_upload() {
  local command=$1 expect_reuse=$2 waiter
  rm -f "$proof/token" "$proof/root/victim" "$proof/home/"{collector,reused,pid,armed}
  if ((expect_reuse == 0)); then
    : >"$proof/token"
    chown 1:1 "$proof/token"
  fi
  : >"$proof/home/armed"
  chown 1:1 "$proof/home/armed"
  setpriv --reuid=1 --regid=1 --clear-groups \
    env -i HOME="$proof/home" PATH="$proof/bin:/usr/bin:/bin" \
      TEST_SUDO="$proof/bin/sudo" TEST_SUDO_TOKEN="$proof/token" TEST_ROOT_VICTIM="$proof/root/victim" \
      TEST_COLLECTOR_RAN="$proof/home/collector" TEST_REUSED_SUDO="$proof/home/reused" \
      TEST_WAITER_ARMED="$proof/home/armed" TEST_WAITER_PID="$proof/home/pid" \
      TEST_EXPECT_REUSE="$expect_reuse" "$command" install >/dev/null
  rm -f "$proof/home/armed"
  if [[ -s $proof/home/pid ]]; then
    waiter=$(<"$proof/home/pid")
    for _ in {1..200}; do
      kill -0 "$waiter" 2>/dev/null || break
      sleep 0.01
    done
    kill -0 "$waiter" 2>/dev/null && kill "$waiter" 2>/dev/null || true
  fi
}

run_upload "$proof/bin/omarchy-upload-log" 0
[[ -e $proof/home/collector && ! -e $proof/token && ! -e $proof/root/victim && ! -e $proof/home/reused ]]

sed "s#$proof/bin/sudo -N --#$proof/bin/sudo --#" \
  "$proof/bin/omarchy-upload-log" >"$proof/bin/omarchy-upload-log-mutant"
chmod 0755 "$proof/bin/omarchy-upload-log-mutant"
run_upload "$proof/bin/omarchy-upload-log-mutant" 1
[[ -e $proof/home/reused && -e $proof/root/victim ]]
NAMESPACE
pass "desktop upload uses cold no-update sudo and the mutation reopens the exploit"

# Exercise the installed-path migration and the explicit privileged support
# reader in an isolated namespace/chroot. No host /var/log or /usr path changes.
"${userns[@]}" /usr/bin/bash -s "$ROOT" "$test_dir" <<'NAMESPACE'
set -euo pipefail
repo=$1
outer_test_dir=$2
newroot="$outer_test_dir/root"
mkdir -p "$newroot"
mount -t tmpfs -o mode=0755 tmpfs "$newroot"
mkdir -p "$newroot/usr/bin" "$newroot/usr/lib" "$newroot/usr/lib64" \
  "$newroot/usr/share/omarchy" "$newroot/var/log" "$newroot/dev" \
  "$newroot/test-bin" "$newroot/runtime" "$newroot/mnt" "$newroot/tmp"
chmod 0700 "$newroot/runtime"
chmod 1777 "$newroot/tmp"
mount --rbind /usr/bin "$newroot/usr/bin"
mount --rbind /usr/lib "$newroot/usr/lib"
[[ ! -d /usr/lib64 ]] || mount --rbind /usr/lib64 "$newroot/usr/lib64"
mount --rbind "$repo" "$newroot/usr/share/omarchy"
: >"$newroot/dev/null"
mount --bind /dev/null "$newroot/dev/null"
ln -s usr/bin "$newroot/bin"
ln -s usr/lib "$newroot/lib"
[[ ! -d /usr/lib64 ]] || ln -s usr/lib64 "$newroot/lib64"

cat >"$newroot/test-bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>/sudo.trace
if [[ ${1:-} == "-h" ]]; then
  printf 'usage: sudo [-ABbEHkNnPS] command\n'
  exit 0
fi
[[ ${1:-} == "-k" ]] && exit 0
[[ ${1:-} == "-N" ]] && shift
[[ ${1:-} == "--" ]] && shift
if [[ ${1:-} == /usr/bin/omarchy-upload-log ]]; then
  shift
  exec /usr/share/omarchy/bin/omarchy-upload-log "$@"
fi
exec "$@"
STUB
cat >"$newroot/test-bin/omarchy-cmd-present" <<'STUB'
#!/bin/bash
exit 1
STUB
cat >"$newroot/test-bin/curl" <<'STUB'
#!/bin/bash
path=
for arg in "$@"; do [[ $arg == file=@* ]] && path=${arg#file=@}; done
[[ -f $path && ! -L $path && $(stat -c %a "$path") == 600 && $(stat -c %a "${path%/*}") == 700 ]]
grep -qF 'PRIVATE ROOT INSTALL CONTENT' "$path"
printf 'uploaded:%s:%s\n' "$(stat -c %a "$path")" "$(stat -c %a "${path%/*}")" >>/upload.observe
printf 'https://logs.invalid/private\n'
STUB
chmod 0755 "$newroot/test-bin/"*
mount --bind "$newroot/test-bin/sudo" "$newroot/usr/bin/sudo"

printf 'PRIVATE ROOT INSTALL CONTENT\n' >"$newroot/var/log/omarchy-install.log"
chmod 0666 "$newroot/var/log/omarchy-install.log"
old_inode=$(stat -c %i "$newroot/var/log/omarchy-install.log")
chroot "$newroot" /usr/bin/env PATH=/test-bin:/usr/bin:/bin \
  /usr/bin/bash /usr/share/omarchy/migrations/1788163638.sh
new_inode=$(stat -c %i "$newroot/var/log/omarchy-install.log")
[[ $old_inode != "$new_inode" && $(stat -c '%u:%a' "$newroot/var/log/omarchy-install.log") == 0:600 ]]
grep -qF 'PRIVATE ROOT INSTALL CONTENT' "$newroot/var/log/omarchy-install.log"
grep -qF 'sudo:-N -- /usr/bin/env -i PATH=/usr/bin:/bin' "$newroot/sudo.trace"

chroot "$newroot" /usr/bin/env PATH=/test-bin:/usr/bin:/bin XDG_RUNTIME_DIR=/runtime \
  /usr/bin/bash /usr/share/omarchy/bin/omarchy-upload-log install >"$newroot/upload.output"
grep -qF 'https://logs.invalid/private' "$newroot/upload.output"
grep -qF 'uploaded:600:700' "$newroot/upload.observe"
[[ -z $(find "$newroot/runtime" -mindepth 1 -print -quit) ]]

# The migration preserves and rejects an exact-path administrator anomaly.
mv "$newroot/var/log/omarchy-install.log" "$newroot/var/log/safe.log"
printf 'MIGRATION VICTIM\n' >"$newroot/var/log/victim"
ln -s victim "$newroot/var/log/omarchy-install.log"
if chroot "$newroot" /usr/bin/env PATH=/test-bin:/usr/bin:/bin \
  /usr/bin/bash /usr/share/omarchy/migrations/1788163638.sh >"$newroot/migration-failure" 2>&1; then
  echo 'migration accepted a symlink anomaly' >&2
  exit 1
fi
[[ -L $newroot/var/log/omarchy-install.log ]]
grep -qF 'MIGRATION VICTIM' "$newroot/var/log/victim"
rm "$newroot/var/log/omarchy-install.log"
mkfifo "$newroot/var/log/omarchy-install.log"
if chroot "$newroot" /usr/bin/env PATH=/test-bin:/usr/bin:/bin \
  /usr/bin/bash /usr/share/omarchy/migrations/1788163638.sh >"$newroot/migration-fifo-failure" 2>&1; then
  echo 'migration accepted a FIFO anomaly' >&2
  exit 1
fi
[[ -p $newroot/var/log/omarchy-install.log ]]
rm "$newroot/var/log/omarchy-install.log"
printf 'FOREIGN ADMIN LOG\n' >"$newroot/var/log/omarchy-install.log"
chown 1:1 "$newroot/var/log/omarchy-install.log"
chmod 0666 "$newroot/var/log/omarchy-install.log"
if chroot "$newroot" /usr/bin/env PATH=/test-bin:/usr/bin:/bin \
  /usr/bin/bash /usr/share/omarchy/migrations/1788163638.sh >"$newroot/migration-owner-failure" 2>&1; then
  echo 'migration accepted a foreign-owned anomaly' >&2
  exit 1
fi
[[ $(stat -c '%u:%a' "$newroot/var/log/omarchy-install.log") == 1:666 ]]
grep -qF 'FOREIGN ADMIN LOG' "$newroot/var/log/omarchy-install.log"
NAMESPACE
pass "migration repairs the exact legacy log and the fixed root reader preserves upload"
