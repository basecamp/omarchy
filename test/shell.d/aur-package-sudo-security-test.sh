#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command unshare
require_command setpriv
require_command gcc

if [[ ${OMARCHY_AUR_SUDO_SECURITY_NS:-0} != 1 ]]; then
  outer_uid=$(id -u)
  outer_gid=$(id -g)
  subuid=$(awk -F: -v user="$(id -un)" '$1 == user { print $2; exit }' /etc/subuid)
  subgid=$(awk -F: -v user="$(id -un)" '$1 == user { print $2; exit }' /etc/subgid)
  if [[ -z $subuid || -z $subgid ]]; then
    pass "no subordinate uid/gid range; skipping AUR/package sudo namespace proof"
    exit 0
  fi
  exec unshare --user --mount \
    --map-users "0:$outer_uid:1" --map-users "1:$subuid:65536" \
    --map-groups "0:$outer_gid:1" --map-groups "1:$subgid:65536" \
    env OMARCHY_AUR_SUDO_SECURITY_NS=1 bash "$0"
fi

[[ $(id -u) == 0 ]] || fail "package sudo proof did not enter its root namespace"

test_tmp=$(mktemp -d)
mount -t tmpfs -o mode=0755,suid tmpfs "$test_tmp"
stub_bin=$test_tmp/bin
test_home=$test_tmp/home
protected_dir=$test_tmp/protected
event_log=$test_tmp/events
token=$test_tmp/sudo-token
installed=$test_tmp/installed
mkdir -p "$stub_bin" "$test_home/.config/yay" "$protected_dir"
touch "$event_log" "$installed"
chown -R 1000:1000 "$test_home"
chown 1000:1000 "$event_log" "$installed"
chmod 0700 "$test_home"
chmod 0755 "$stub_bin" "$protected_dir"
chmod 0600 "$event_log" "$installed"

mounted=()
persistent_pids=()
active_session=""
cleanup() {
  local status=$? pid pid_file index
  trap - EXIT
  if [[ $active_session =~ ^[1-9][0-9]*$ ]]; then
    kill -TERM -- "-$active_session" 2>/dev/null || kill -TERM "$active_session" 2>/dev/null || true
    kill -KILL -- "-$active_session" 2>/dev/null || kill -KILL "$active_session" 2>/dev/null || true
  fi
  for pid_file in "$test_home"/*.pid; do
    [[ -s $pid_file ]] || continue
    persistent_pids+=("$(<"$pid_file")")
  done
  for pid in "${persistent_pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  for (( index=${#mounted[@]}-1; index>=0; index-- )); do
    umount -l "${mounted[index]}" 2>/dev/null || true
  done
  rm -rf "$test_tmp"/* 2>/dev/null || true
  umount -l "$test_tmp" 2>/dev/null || true
  rmdir "$test_tmp" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT

cat >"$test_tmp/sudo.c" <<'C'
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char *required(const char *name) {
  const char *value = getenv(name);
  if (!value || !*value) exit(125);
  return value;
}
static void event(const char *message) {
  int fd = open(required("TEST_EVENT_LOG"), O_WRONLY | O_APPEND);
  if (fd < 0) exit(125);
  dprintf(fd, "%s\n", message);
  close(fd);
}
static int has_token(void) { return access(required("TEST_SUDO_TOKEN"), F_OK) == 0; }
static int create_token(void) {
  int fd = open(required("TEST_SUDO_TOKEN"), O_WRONLY | O_CREAT | O_TRUNC, 0600);
  if (fd < 0) return 125;
  close(fd);
  return 0;
}
int main(int argc, char **argv) {
  int index = 1, no_update = 0, noninteractive = 0;
  if (geteuid() != 0) {
    event("SUDO:no-new-privs-denied");
    return 1;
  }
  if (argc == 2 && strcmp(argv[1], "-h") == 0) {
    puts("usage: sudo [-ABbEHkNnPS] command");
    return 0;
  }
  if (argc == 2 && strcmp(argv[1], "-k") == 0) {
    event("SUDO:invalidate");
    if (unlink(required("TEST_SUDO_TOKEN")) && errno != ENOENT) return 125;
    return 0;
  }
  if (index < argc && strcmp(argv[index], "-N") == 0) { no_update = 1; index++; }
  if (index < argc && strcmp(argv[index], "-n") == 0) { noninteractive = 1; index++; }
  if (index < argc && strcmp(argv[index], "-v") == 0) {
    event(no_update ? "SUDO:validate-no-update" : "SUDO:validate-reusable");
    return no_update ? 0 : 125;
  }
  if (index < argc && strcmp(argv[index], "-V") == 0) {
    event("SUDO:check-no-update");
    return getenv("TEST_SUDO_NO_N") ? 2 : 0;
  }
  if (index < argc && strcmp(argv[index], "--") == 0) index++;
  if (noninteractive && !has_token()) {
    event("SUDO:deny-noninteractive");
    return 1;
  }
  if (!no_update && !noninteractive) {
    event("SUDO:publish-token");
    if (create_token()) return 125;
  } else if (no_update) {
    event("SUDO:grant-no-update");
  }
  if (index >= argc || setgid(0) || setuid(0)) return 125;
  execv(argv[index], &argv[index]);
  return errno == ENOENT ? 127 : 126;
}
C
gcc -O2 -Wall -Wextra -o "$stub_bin/sudo" "$test_tmp/sudo.c"
chown 0:0 "$stub_bin/sudo"
chmod 4755 "$stub_bin/sudo"

cat >"$test_home/payload" <<'PAYLOAD'
package-picker-payload
PAYLOAD
chown 1000:1000 "$test_home/payload"
chmod 0600 "$test_home/payload"

cat >"$test_home/attack" <<'ATTACK'
#!/bin/bash
pid_file=$HOME/attack-${TEST_ATTACK_LABEL:-generic}.pid
printf '%s\n' "$$" >"$pid_file"
if [[ ${TEST_ATTACK_SINGLE_ATTEMPT:-0} == 1 ]]; then
  if /usr/bin/sudo -n -- /usr/bin/install -o 0 -g 0 -m 0600 \
      "$HOME/payload" "$TEST_PROTECTED_TARGET" 2>/dev/null; then
    printf 'ATTACK:root-reused\n' >>"$TEST_EVENT_LOG"
  else
    printf 'ATTACK:first-attempt-denied\n' >>"$TEST_EVENT_LOG"
  fi
  exit 0
fi
for _ in {1..120}; do
  if /usr/bin/sudo -n -- /usr/bin/install -o 0 -g 0 -m 0600 \
      "$HOME/payload" "$TEST_PROTECTED_TARGET" 2>/dev/null; then
    printf 'ATTACK:root-reused\n' >>"$TEST_EVENT_LOG"
    exit 0
  fi
  /usr/bin/sleep 0.005
done
printf 'ATTACK:blocked\n' >>"$TEST_EVENT_LOG"
ATTACK
chmod 0755 "$test_home/attack"

cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
printf -v trace 'PACMAN:%s:' "$(/usr/bin/id -u)"
for argument in "$@"; do printf -v trace '%s <%s>' "$trace" "$argument"; done
printf '%s\n' "$trace" >>"$TEST_EVENT_LOG"
case " $* " in
  *' -Slq '*) printf 'safe-one\nsafe-two\n'; exit 0 ;;
  *' -Sii '*) exit 0 ;;
esac
if [[ ${1:-} == -Q ]]; then
  package=${3:-}
  /usr/bin/grep -Fxq "$package" "$TEST_INSTALLED"
  exit
fi
if [[ ${1:-} == -T ]]; then
  shift
  [[ ${1:-} != -- ]] || shift
  printf '%s\n' "$@"
  exit 127
fi
if [[ " $* " == *' -S '* || " $* " == *' -U '* || " $* " == *' -Rns '* ]]; then
  [[ $(/usr/bin/id -u) == 0 ]] || exit 71
  [[ ${TEST_PACMAN_FAIL:-0} != 1 ]] || exit 72
  if [[ ${TEST_PACMAN_SKIP_INSTALL:-0} != 1 ]]; then
    for argument in "$@"; do
      [[ $argument =~ ^[a-z0-9][a-z0-9@._+:-]*$ ]] || continue
      printf '%s\n' "$argument" >>"$TEST_INSTALLED"
    done
  fi
fi
STUB

cat >"$stub_bin/yay" <<'STUB'
#!/bin/bash
trace=YAY:
for argument in "$@"; do printf -v trace '%s <%s>' "$trace" "$argument"; done
printf '%s\n' "$trace" >>"$TEST_EVENT_LOG"
if [[ " $* " == *' -Slqa '* ]]; then
  [[ ${TEST_START_DISCOVERY_ATTACK:-0} != 1 ]] || \
    /usr/bin/setsid --fork "$HOME/attack" >/dev/null 2>&1
  printf 'safe-aur\nsafe-extra\n'
  exit 0
fi
if [[ " $* " == *' -Qqe '* ]]; then
  [[ ${TEST_START_DISCOVERY_ATTACK:-0} != 1 ]] || \
    /usr/bin/setsid --fork "$HOME/attack" >/dev/null 2>&1
  printf 'safe-one\nsafe-two\n'
  exit 0
fi

[[ ${TEST_YAY_FAIL_BEFORE_BUILD:-0} != 1 ]] || exit 73
/usr/bin/setsid --fork "$HOME/attack" >/dev/null 2>&1
if [[ " $* " != *' --pacman /usr/bin/pacman '* ]]; then
  /usr/bin/sudo -N -- "$HOME/hostile-bin/pacman"
  exit
fi
[[ " $* " == *' --makepkg /usr/bin/omarchy-makepkg-unprivileged '* ]] || exit 74
[[ " $* " == *' --mflags=--nodeps '* ]] || exit 75
# Model a PKGBUILD that directly restores normal PACMAN_AUTH and calls absolute
# sudo. no_new_privs on the fixed makepkg launcher must make setuid ineffective.
targets=(); after_delimiter=0
for argument in "$@"; do
  if (( after_delimiter )); then targets+=("$argument"); fi
  [[ $argument != -- ]] || after_delimiter=1
done
for target in "${targets[@]}"; do
  TEST_MAKEPKG_GENERIC=1 /usr/bin/omarchy-makepkg-unprivileged --nodeps "$target"
done
if [[ ${TEST_YAY_BLOCK:-0} == 1 ]]; then
  printf 'ready\n' >"$TEST_READY"
  trap 'exit 143' TERM
  while :; do /usr/bin/sleep 0.05; done
fi
[[ ${TEST_YAY_BUILD_FAIL:-0} != 1 ]] || exit 76
/usr/bin/sudo -N -- /usr/bin/pacman -S --noconfirm -- "${targets[@]}"
STUB

cat >"$stub_bin/fzf" <<'STUB'
#!/bin/bash
printf 'FZF\n' >>"$TEST_EVENT_LOG"
/usr/bin/cat >/dev/null
[[ ${TEST_START_DISCOVERY_ATTACK:-0} != 1 ]] || \
  /usr/bin/setsid --fork "$HOME/attack" >/dev/null 2>&1
if [[ ${TEST_FZF_BLOCK:-0} == 1 ]]; then
  printf 'ready\n' >"$TEST_READY"
  trap 'exit 143' TERM
  while :; do /usr/bin/sleep 0.05; done
fi
[[ ${TEST_FZF_FAIL:-0} != 1 ]] || exit 77
printf '%b' "${TEST_SELECTION:-}"
STUB

cat >"$stub_bin/makepkg" <<'STUB'
#!/bin/bash
trace=MAKEPKG:
for argument in "$@"; do printf -v trace '%s <%s>' "$trace" "$argument"; done
printf '%s\n' "$trace" >>"$TEST_EVENT_LOG"
/usr/bin/setsid --fork "$HOME/attack" >/dev/null 2>&1
# This is the direct makepkg-internal override: an ordinary sudo call must be
# denied by the kernel-enforced no_new_privs boundary.
if /usr/bin/sudo -- /usr/bin/pacman -S --asdeps -- bypass-dependency; then
  exit 78
fi
[[ ${TEST_MAKEPKG_GENERIC:-0} != 1 ]] || exit 0
if [[ " $* " == *' --printsrcinfo '* ]]; then
  printf 'pkgbase = test-package\n\tmakedepends = dev-dependency>=1\n\tpkgname = test-package\n'
  exit 0
fi
[[ ${TEST_MAKEPKG_FAIL:-0} != 1 ]] || exit 81
/usr/bin/touch "$PWD/dev-package.pkg.tar.zst"
STUB

cat >"$stub_bin/updatedb" <<'STUB'
#!/bin/bash
[[ $(/usr/bin/id -u) == 0 ]] || exit 82
printf 'UPDATEDB:no-update\n' >>"$TEST_EVENT_LOG"
STUB
cat >"$stub_bin/omarchy-show-done" <<'STUB'
#!/bin/bash
printf 'DONE\n' >>"$TEST_EVENT_LOG"
STUB
cat >"$stub_bin/omarchy-pkg-aur-accessible" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod 0755 "$stub_bin"/{pacman,yay,fzf,makepkg,updatedb,omarchy-show-done,omarchy-pkg-aur-accessible}

# Isolate /usr/bin so this test can install the newly added package-owned
# launcher without creating anything on the host. Unvalidated utilities are
# symlinked to a read-only bind of the original tree; every command production
# explicitly validates is copied as a namespace-root-owned regular file.
host_bin=$test_tmp/host-bin
mkdir -p "$host_bin"
mount --bind /usr/bin "$host_bin"
mounted+=("$host_bin")
export TEST_HOST_BIN=$host_bin
mount -t tmpfs -o mode=0755,suid tmpfs /usr/bin
mounted+=(/usr/bin)

host_commands=(
  awk bash cat chmod chown cp dirname env grep head id install ln mkdir mktemp
  mv printf readlink rg rm sed setsid sleep tail touch true uname
)
for command in "${host_commands[@]}"; do
  "$host_bin/ln" -s "$host_bin/$command" "/usr/bin/$command"
done

"$host_bin/rm" -f /usr/bin/rm
cat > /usr/bin/rm <<'STUB'
#!/bin/bash
if [[ " $* " == *' /usr/local/bin/opam '* ]]; then
  printf 'REMOVE-OPAM:%s\n' "$(/usr/bin/id -u)" >>"$TEST_EVENT_LOG"
  [[ ${TEST_RM_FAIL:-0} != 1 ]] || exit 83
  exit 0
fi
exec "$TEST_HOST_BIN/rm" "$@"
STUB
"$host_bin/chown" 0:0 /usr/bin/rm
"$host_bin/chmod" 0755 /usr/bin/rm
for command in realpath stat setpriv git gpg; do
  "$host_bin/cp" -a "$host_bin/$command" "/usr/bin/$command"
  "$host_bin/chown" 0:0 "/usr/bin/$command"
  "$host_bin/chmod" 0755 "/usr/bin/$command"
done
"$host_bin/cp" -a "$stub_bin/sudo" /usr/bin/sudo
"$host_bin/chown" 0:0 /usr/bin/sudo
"$host_bin/chmod" 4755 /usr/bin/sudo
for command in pacman yay makepkg fzf updatedb omarchy-show-done omarchy-pkg-aur-accessible; do
  "$host_bin/cp" -a "$stub_bin/$command" "/usr/bin/$command"
  "$host_bin/chown" 0:0 "/usr/bin/$command"
  "$host_bin/chmod" 0755 "/usr/bin/$command"
done
"$host_bin/cp" -a "$ROOT/bin/omarchy-pkg-aur-add" /usr/bin/omarchy-pkg-aur-add
"$host_bin/cp" -a "$ROOT/bin/omarchy-makepkg-unprivileged" /usr/bin/omarchy-makepkg-unprivileged
"$host_bin/chown" 0:0 /usr/bin/omarchy-pkg-aur-add /usr/bin/omarchy-makepkg-unprivileged
"$host_bin/chmod" 0755 /usr/bin/omarchy-pkg-aur-add /usr/bin/omarchy-makepkg-unprivileged

base_env=(
  HOME="$test_home"
  USER=test LOGNAME=test
  PATH="$test_home/hostile-bin:/usr/bin:/bin"
  TEST_EVENT_LOG="$event_log"
  TEST_SUDO_TOKEN="$token"
  TEST_INSTALLED="$installed"
  TEST_HOST_BIN="$host_bin"
)
mkdir -p "$test_home/hostile-bin"
cat >"$test_home/hostile-bin/yay" <<'STUB'
#!/bin/bash
touch "$HOME/hostile-path-yay-ran"
exit 91
STUB
cat >"$test_home/hostile-bin/sudo" <<'STUB'
#!/bin/bash
touch "$HOME/hostile-path-sudo-ran"
exit 92
STUB
cat >"$test_home/hostile-bin/pacman" <<'STUB'
#!/bin/bash
touch "$HOME/hostile-pacman-ran"
STUB
chmod 0755 "$test_home/hostile-bin"/*
chown -R 1000:1000 "$test_home/hostile-bin"
chmod 0700 "$test_home/hostile-bin"
cat >"$test_home/.config/yay/config.json" <<'JSON'
{"sudobin":"/home/test/hostile-bin/sudo","sudoflags":"","sudoloop":true,"pacmanbin":"/home/test/hostile-bin/pacman","makepkgbin":"/home/test/hostile-bin/makepkg"}
JSON
cat >"$test_home/.config/yay/init.lua" <<'LUA'
-- A real yay init hook is user code. The fixture launches the polling child
-- when yay starts so the test does not depend on a Lua interpreter.
LUA

run_user() {
  setpriv --reuid=1000 --regid=1000 --clear-groups \
    env -i "${base_env[@]}" \
    'BASH_FUNC_yay%%=() { touch "$HOME/exported-yay-ran"; }' \
    'BASH_FUNC_fzf%%=() { touch "$HOME/exported-fzf-ran"; }' \
    "$@"
}

# A backgrounded Bash function gives $! for the wrapper subshell, not for the
# setsid process it waits on. Launch setpriv itself in the background so the
# recorded PID is also the new session/process-group ID and signal tests cannot
# orphan their blocked fixture under the user manager.
start_user_session() {
  setpriv --reuid=1000 --regid=1000 --clear-groups \
    env -i "${base_env[@]}" \
    'BASH_FUNC_yay%%=() { touch "$HOME/exported-yay-ran"; }' \
    'BASH_FUNC_fzf%%=() { touch "$HOME/exported-fzf-ran"; }' \
    "$@" &
  session=$!
  active_session=$session
}

stop_case_attackers() {
  local pid pid_file remaining
  local pids=()

  for pid_file in "$test_home"/attack-*.pid; do
    [[ -s $pid_file ]] || continue
    pid=$(<"$pid_file")
    [[ $pid =~ ^[1-9][0-9]*$ ]] || continue
    pids+=("$pid")
    kill -TERM "$pid" 2>/dev/null || true
  done

  for _ in {1..200}; do
    remaining=0
    for pid in "${pids[@]}"; do
      kill -0 "$pid" 2>/dev/null && remaining=1
    done
    (( remaining )) || break
    sleep 0.005
  done
  for pid in "${pids[@]}"; do
    kill -KILL "$pid" 2>/dev/null || true
  done
  rm -f "$test_home"/attack-*.pid
}

reset_case() {
  local label=$1
  # Detached discovery/build children are intentionally not shell jobs. Drain
  # the previous case before truncating shared logs so a late final denial can
  # never be misattributed to the next unsupported/failure scenario.
  stop_case_attackers
  : >"$event_log"
  : >"$installed"
  chown 1000:1000 "$event_log" "$installed"
  rm -f "$token" "$protected_dir"/* "$test_home"/*-ran "$test_home/ready"
  export TEST_ATTACK_LABEL=$label
  export TEST_PROTECTED_TARGET="$protected_dir/$label"
}

wait_for_attack() {
  for _ in {1..140}; do
    grep -q '^ATTACK:' "$event_log" 2>/dev/null && return 0
    sleep 0.005
  done
  return 1
}

assert_cold() {
  local label=$1
  if ! wait_for_attack; then
    /usr/bin/tail -80 "$event_log" >&2 || true
    fail "$label did not exercise the polling child"
  fi
  [[ ! -e $protected_dir/$label ]] || fail "$label let user code reuse root authority"
  [[ ! -e $token ]] || fail "$label left a reusable sudo timestamp"
  ! grep -q '^SUDO:publish-token$' "$event_log" || fail "$label published a reusable sudo timestamp"
}

set +e
run_user /usr/bin/bash "$ROOT/default/omarchy/sudo-no-update/sudo" -p /usr/bin/true \
  >"$test_tmp/unsafe-wrapper.out" 2>"$test_tmp/unsafe-wrapper.err"
unsafe_wrapper_status=$?
set -e
(( unsafe_wrapper_status == 126 )) ||
  fail "the privileged-Bash exception accepted an ordinary shell with a decoy -p argument"
grep -Fq 'Refusing an unsafe Bash startup' "$test_tmp/unsafe-wrapper.err" ||
  fail "the rejected sudo boundary did not explain its startup failure"
run_user "$ROOT/default/omarchy/sudo-no-update/sudo" -v
grep -Fxq 'SUDO:validate-no-update' "$event_log" ||
  fail "the privileged sudo boundary did not preserve validation mode"
pass "the privileged sudo boundary validates startup and preserves its supported option"

# Generic AUR helper: a pre-existing global timestamp and hostile yay/PATH/
# exported-function configuration are all cold before build code. The fixed
# CLI still completes the legitimate root installation using no-update.
reset_case generic
touch "$token"
chown 0:0 "$token"
umask 000
run_user env TEST_ATTACK_LABEL=generic TEST_PROTECTED_TARGET="$protected_dir/generic" \
  bash "$ROOT/bin/omarchy-pkg-aur-add" safe-aur
assert_cold generic
grep -Fxq safe-aur "$installed" || fail "generic AUR install did not complete"
grep -q 'YAY:.* <--sudo> </usr/bin/sudo>.* <--sudoflags=-N>.* <--sudoloop=false>' "$event_log" ||
  fail "generic helper did not override hostile yay sudo settings"
grep -q 'YAY:.* <--pacman> </usr/bin/pacman>.* <--makepkg> </usr/bin/omarchy-makepkg-unprivileged>' "$event_log" ||
  fail "generic helper did not pin yay's unprivileged package tools"
grep -Fxq 'SUDO:no-new-privs-denied' "$event_log" ||
  fail "direct PKGBUILD sudo override did not reach the kernel boundary"
[[ ! -e $test_home/hostile-path-yay-ran && ! -e $test_home/exported-yay-ran ]] ||
  fail "generic helper used caller command resolution"
pass "generic AUR build cannot reuse pre-existing or later installation authority"

reset_case generic-multi
run_user env TEST_ATTACK_LABEL=generic-multi TEST_PROTECTED_TARGET="$protected_dir/generic-multi" \
  bash "$ROOT/bin/omarchy-pkg-aur-add" safe-aur safe-extra
assert_cold generic-multi
grep -Fxq safe-aur "$installed" && grep -Fxq safe-extra "$installed" ||
  fail "generic multi-package install did not complete"
(( $(grep -c '^SUDO:no-new-privs-denied$' "$event_log") >= 2 )) ||
  fail "each sequential PKGBUILD did not retain no_new_privs"
pass "sequential AUR builds cannot restore privileged makepkg behavior"

# Verification stays fail closed when yay reports success without registering
# the package, and build/install failures still revoke.
reset_case verify
if run_user env TEST_ATTACK_LABEL=verify TEST_PROTECTED_TARGET="$protected_dir/verify" \
    TEST_PACMAN_SKIP_INSTALL=1 bash "$ROOT/bin/omarchy-pkg-aur-add" safe-aur; then
  fail "generic helper accepted an unregistered package"
fi
assert_cold verify
reset_case build-fail
if run_user env TEST_ATTACK_LABEL=build-fail TEST_PROTECTED_TARGET="$protected_dir/build-fail" \
    TEST_YAY_BUILD_FAIL=1 bash "$ROOT/bin/omarchy-pkg-aur-add" safe-aur; then
  fail "generic helper ignored a build failure"
fi
assert_cold build-fail
reset_case install-fail
if run_user env TEST_ATTACK_LABEL=install-fail TEST_PROTECTED_TARGET="$protected_dir/install-fail" \
    TEST_PACMAN_FAIL=1 bash "$ROOT/bin/omarchy-pkg-aur-add" safe-aur; then
  fail "generic helper ignored an install failure"
fi
assert_cold install-fail
pass "AUR build, install, and registration failures remain fail closed"

# Unsupported -N must be detected before yay or other user-controlled build
# machinery starts.
reset_case unsupported
if run_user env TEST_ATTACK_LABEL=unsupported TEST_PROTECTED_TARGET="$protected_dir/unsupported" \
    TEST_SUDO_NO_N=1 bash "$ROOT/bin/omarchy-pkg-aur-add" safe-aur; then
  fail "generic helper ran without sudo no-update support"
fi
! grep -q '^YAY:' "$event_log" || fail "unsupported sudo reached yay build code"
[[ ! -e $token ]] || fail "unsupported sudo left a credential live"
pass "unsupported sudo fails before AUR code"

reset_case generic-signal
touch "$token"; chown 0:0 "$token"
ready=$test_home/ready
set +e
start_user_session /usr/bin/setsid bash -c \
  'exec env TEST_ATTACK_LABEL=generic-signal TEST_PROTECTED_TARGET="$1" TEST_YAY_BLOCK=1 TEST_READY="$2" bash "$3" safe-aur' \
  generic-signal "$protected_dir/generic-signal" "$ready" "$ROOT/bin/omarchy-pkg-aur-add"
set -e
for _ in {1..200}; do [[ -e $ready ]] && break; sleep 0.005; done
[[ -e $ready ]] || fail "generic AUR signal fixture did not become ready"
kill -TERM -- "-$session" 2>/dev/null || kill -TERM "$session"
set +e; wait "$session"; signal_status=$?; set -e
active_session=""
(( signal_status != 0 )) || fail "generic AUR TERM unexpectedly succeeded"
[[ ! -e $token ]] || fail "generic AUR TERM left sudo live"
[[ ! -e $protected_dir/generic-signal ]] || fail "generic AUR signal child reused root"
pass "generic AUR signal cleanup invalidates the credential"

# The updater has its own yay call and must pin the same package tools as the
# generic helper. Without --pacman, the fixture models yay asking sudo to run
# the command selected by the user's configuration.
reset_case aur-update
run_user env TEST_ATTACK_LABEL=aur-update TEST_PROTECTED_TARGET="$protected_dir/aur-update" \
  "$ROOT/bin/omarchy-update-aur-pkgs"
assert_cold aur-update
grep -q 'YAY:.* <--pacman> </usr/bin/pacman>.* <--makepkg> </usr/bin/omarchy-makepkg-unprivileged>' "$event_log" ||
  fail "AUR updater did not pin yay's privileged package tools"
[[ ! -e $test_home/hostile-pacman-ran ]] ||
  fail "AUR updater let user configuration select a root pacman command"
pass "AUR updater pins privileged tools and isolates package builds"

# Official picker: fzf starts the original polling exploit, then returns two
# ordinary selections. Both installs happen in one fixed no-update transaction.
reset_case official-picker
touch "$token"; chown 0:0 "$token"
run_user env TEST_ATTACK_LABEL=official-picker TEST_PROTECTED_TARGET="$protected_dir/official-picker" \
  TEST_START_DISCOVERY_ATTACK=1 TEST_SELECTION=$'safe-one\nsafe-two\n' \
  bash "$ROOT/bin/omarchy-pkg-install"
assert_cold official-picker
grep -q 'PACMAN:0:.* <-S>.* <--> <safe-one> <safe-two>' "$event_log" ||
  fail "official picker did not preserve multi-selection install"
[[ ! -e $test_home/exported-fzf-ran ]] || fail "official picker used an exported fzf function"
pass "official package picker keeps discovery code outside reusable sudo authority"

# AUR picker routes through the hardened generic helper, then updatedb is also
# command-scoped. The discovery child and build child both remain unprivileged.
reset_case aur-picker
run_user env TEST_ATTACK_LABEL=aur-picker TEST_PROTECTED_TARGET="$protected_dir/aur-picker" \
  TEST_START_DISCOVERY_ATTACK=1 TEST_SELECTION=$'safe-aur\n' \
  bash "$ROOT/bin/omarchy-pkg-aur-install"
assert_cold aur-picker
grep -Fxq 'UPDATEDB:no-update' "$event_log" || fail "AUR picker did not run updatedb"
grep -Fxq safe-aur "$installed" || fail "AUR picker did not route through generic install"
pass "AUR picker uses the generic cold build boundary and no-update updatedb"

# Removal discovery has the same fzf extension boundary. Multi-select is
# passed after -- to one no-update pacman transaction; injected selections are
# rejected rather than becoming pacman options.
reset_case remove-picker
run_user env TEST_ATTACK_LABEL=remove-picker TEST_PROTECTED_TARGET="$protected_dir/remove-picker" \
  TEST_START_DISCOVERY_ATTACK=1 TEST_SELECTION=$'safe-one\nsafe-two\n' \
  bash "$ROOT/bin/omarchy-pkg-remove"
assert_cold remove-picker
grep -q 'PACMAN:0:.* <-Rns>.* <--> <safe-one> <safe-two>' "$event_log" ||
  fail "package remover did not preserve safe multi-selection"
reset_case remove-injection
if run_user env TEST_ATTACK_LABEL=remove-injection TEST_PROTECTED_TARGET="$protected_dir/remove-injection" \
    TEST_SELECTION=$'--config\n' bash "$ROOT/bin/omarchy-pkg-remove"; then
  fail "package remover accepted an option-like selection"
fi
! grep -q 'PACMAN:0:.* <-Rns>' "$event_log" || fail "invalid removal selection reached pacman"
[[ ! -e $token ]] || fail "invalid removal selection left sudo live"
pass "package remover keeps discovery cold and rejects option injection"

reset_case remove-fail
if run_user env TEST_ATTACK_LABEL=remove-fail TEST_PROTECTED_TARGET="$protected_dir/remove-fail" \
    TEST_START_DISCOVERY_ATTACK=1 TEST_SELECTION=$'safe-one\n' TEST_PACMAN_FAIL=1 \
    bash "$ROOT/bin/omarchy-pkg-remove"; then
  fail "package remover ignored pacman failure"
fi
assert_cold remove-fail
reset_case remove-empty
run_user env TEST_ATTACK_LABEL=remove-empty TEST_PROTECTED_TARGET="$protected_dir/remove-empty" \
  TEST_SELECTION='' bash "$ROOT/bin/omarchy-pkg-remove"
[[ ! -e $token ]] || fail "empty removal selection left sudo live"
pass "package remover failure and empty selection leave no credential"

# No selection, cancellation, failure, and unsupported sudo all leave the
# picker cold; unsupported support probing precedes fzf execution.
reset_case no-selection
run_user env TEST_ATTACK_LABEL=no-selection TEST_PROTECTED_TARGET="$protected_dir/no-selection" \
  TEST_SELECTION='' bash "$ROOT/bin/omarchy-pkg-install"
[[ ! -e $token ]] || fail "empty picker selection left sudo live"
reset_case picker-fail
if run_user env TEST_ATTACK_LABEL=picker-fail TEST_PROTECTED_TARGET="$protected_dir/picker-fail" \
    TEST_FZF_FAIL=1 bash "$ROOT/bin/omarchy-pkg-install"; then
  fail "picker ignored fzf failure"
fi
[[ ! -e $token ]] || fail "fzf failure left sudo live"
reset_case picker-unsupported
if run_user env TEST_ATTACK_LABEL=picker-unsupported TEST_PROTECTED_TARGET="$protected_dir/picker-unsupported" \
    TEST_SUDO_NO_N=1 bash "$ROOT/bin/omarchy-pkg-install"; then
  fail "picker accepted unsupported sudo"
fi
! grep -q '^FZF$' "$event_log" || fail "picker ran fzf before validating sudo -N"
pass "picker cancellation and failures clean up before publication"

# Signal the whole picker session so both the user-configurable fzf and parent
# receive TERM; the parent EXIT trap must invalidate the pre-existing token.
reset_case picker-signal
touch "$token"; chown 0:0 "$token"
ready=$test_home/ready
set +e
start_user_session /usr/bin/setsid bash -c \
  'exec env TEST_ATTACK_LABEL=picker-signal TEST_PROTECTED_TARGET="$1" TEST_FZF_BLOCK=1 TEST_READY="$2" bash "$3"' \
  picker-signal "$protected_dir/picker-signal" "$ready" "$ROOT/bin/omarchy-pkg-install"
set -e
for _ in {1..200}; do [[ -e $ready ]] && break; sleep 0.005; done
[[ -e $ready ]] || fail "picker signal fixture did not become ready"
kill -TERM -- "-$session" 2>/dev/null || kill -TERM "$session"
set +e; wait "$session"; signal_status=$?; set -e
active_session=""
(( signal_status != 0 )) || fail "picker TERM unexpectedly succeeded"
[[ ! -e $token ]] || fail "picker TERM left sudo live"
pass "picker signal cleanup invalidates the credential"

# The local package development flow discovers dependencies while no_new_privs
# is active, installs a validated batch with -N, then builds without dependency
# installation and uses -N again for pacman -U. It must work before the new
# package-owned launcher has itself been installed.
/usr/bin/rm -f /usr/bin/omarchy-makepkg-unprivileged
[[ ! -e /usr/bin/omarchy-makepkg-unprivileged ]] || fail "could not model pre-launcher release"
reset_case dev
checkout=$test_home/checkout
pkgbuild_root=$test_home/pkgbuilds
mkdir -p "$checkout" "$pkgbuild_root/test-package"
cat >"$pkgbuild_root/test-package/PKGBUILD" <<'PKGBUILD'
pkgname=test-package
pkgver=1
pkgrel=1
arch=(any)
package() { :; }
PKGBUILD
chown -R 1000:1000 "$checkout" "$pkgbuild_root"
run_user env TEST_ATTACK_LABEL=dev TEST_PROTECTED_TARGET="$protected_dir/dev" \
  OMARCHY_PKGBUILDS_DIR="$pkgbuild_root" \
  bash "$ROOT/bin/omarchy-dev-pkg-test" test-package "$checkout"
assert_cold dev
grep -q '^MAKEPKG:.* <--printsrcinfo>' "$event_log" ||
  fail "dev build did not generate dependency metadata under isolation"
grep -q '^MAKEPKG:.* <--nodeps>' "$event_log" ||
  fail "dev build did not enforce a dependency-free build phase"
grep -q 'PACMAN:0:.* <-U>' "$event_log" || fail "dev build did not install the built package"
grep -q 'PACMAN:0:.* <-U>.* <--overwrite=\*>' "$event_log" ||
  fail "dev build did not preserve replacement of legacy conflicting files"
grep -q 'PACMAN:0:.* <-S>.* <dev-dependency>' "$event_log" ||
  fail "dev build did not install validated dependencies as one no-update batch"
grep -Fxq 'SUDO:no-new-privs-denied' "$event_log" ||
  fail "dev PKGBUILD direct sudo override did not reach no_new_privs"
pass "local PKGBUILD dependencies and installation use only no-update sudo"

reset_case dev-bypass
if run_user env TEST_ATTACK_LABEL=dev-bypass TEST_PROTECTED_TARGET="$protected_dir/dev-bypass" \
    OMARCHY_PKGBUILDS_DIR="$pkgbuild_root" \
    bash "$ROOT/bin/omarchy-dev-pkg-test" test-package "$checkout" --config /tmp/evil; then
  fail "dev build accepted a makepkg config override"
fi
! grep -q '^MAKEPKG:' "$event_log" || fail "dev config bypass reached build code"
pass "developer makepkg overrides cannot replace the no-update policy"

# OCaml removal executes user-owned opam first. Its detached child sees a cold
# credential before the final fixed sudo -N rm and after command completion.
cat >"$test_home/hostile-bin/opam" <<'STUB'
#!/bin/bash
# A synchronous child performs and records the first denied attempt. Only then
# do we launch the detached poller whose lifetime crosses the final sudo call.
TEST_ATTACK_SINGLE_ATTEMPT=1 "$HOME/attack"
first_pid=$(/usr/bin/cat "$HOME/attack-${TEST_ATTACK_LABEL:-generic}.pid")
/usr/bin/setsid --fork "$HOME/attack" >/dev/null 2>&1
for _ in {1..200}; do
  detached_pid=$(/usr/bin/cat "$HOME/attack-${TEST_ATTACK_LABEL:-generic}.pid" 2>/dev/null || true)
  [[ $detached_pid != "$first_pid" && $detached_pid =~ ^[1-9][0-9]*$ ]] && break
  /usr/bin/sleep 0.005
done
[[ ${detached_pid:-} != "$first_pid" && ${detached_pid:-} =~ ^[1-9][0-9]*$ ]] || exit 85
if [[ ${TEST_OPAM_BLOCK:-0} == 1 ]]; then
  printf 'ready\n' >"$TEST_READY"
  trap 'exit 143' TERM
  while :; do /usr/bin/sleep 0.05; done
fi
[[ ${TEST_OPAM_FAIL:-0} != 1 ]] || exit 84
STUB
chown 1000:1000 "$test_home/hostile-bin/opam"
chmod 0755 "$test_home/hostile-bin/opam"

reset_case remove-ocaml
touch "$token"; chown 0:0 "$token"
run_user env TEST_ATTACK_LABEL=remove-ocaml TEST_PROTECTED_TARGET="$protected_dir/remove-ocaml" \
  bash "$ROOT/bin/omarchy-remove-dev-env" ocaml
assert_cold remove-ocaml
grep -Fxq 'REMOVE-OPAM:0' "$event_log" || fail "OCaml removal did not complete its fixed root cleanup"
! grep -q '^SUDO:publish-token$' "$event_log" || fail "OCaml removal published a reusable token"
pass "user-owned opam cannot reuse the final OCaml cleanup authorization"

reset_case remove-ocaml-unsupported
if run_user env TEST_ATTACK_LABEL=remove-ocaml-unsupported \
    TEST_PROTECTED_TARGET="$protected_dir/remove-ocaml-unsupported" TEST_SUDO_NO_N=1 \
    bash "$ROOT/bin/omarchy-remove-dev-env" ocaml; then
  fail "OCaml removal accepted unsupported sudo"
fi
! grep -q '^ATTACK:' "$event_log" || fail "unsupported sudo reached user-owned opam"
pass "OCaml removal validates no-update before user code"

reset_case remove-ocaml-fail
if run_user env TEST_ATTACK_LABEL=remove-ocaml-fail TEST_PROTECTED_TARGET="$protected_dir/remove-ocaml-fail" \
    TEST_RM_FAIL=1 bash "$ROOT/bin/omarchy-remove-dev-env" ocaml; then
  fail "OCaml removal ignored fixed root cleanup failure"
fi
assert_cold remove-ocaml-fail

reset_case remove-ocaml-signal
touch "$token"; chown 0:0 "$token"
ready=$test_home/ready
set +e
start_user_session /usr/bin/setsid bash -c \
  'exec env TEST_ATTACK_LABEL=remove-ocaml-signal TEST_PROTECTED_TARGET="$1" TEST_OPAM_BLOCK=1 TEST_READY="$2" bash "$3" ocaml' \
  remove-ocaml-signal "$protected_dir/remove-ocaml-signal" "$ready" "$ROOT/bin/omarchy-remove-dev-env"
set -e
for _ in {1..200}; do [[ -e $ready ]] && break; sleep 0.005; done
[[ -e $ready ]] || fail "OCaml removal signal fixture did not become ready"
kill -TERM -- "-$session" 2>/dev/null || kill -TERM "$session"
set +e; wait "$session"; signal_status=$?; set -e
active_session=""
(( signal_status != 0 )) || fail "OCaml removal TERM unexpectedly succeeded"
[[ ! -e $token ]] || fail "OCaml removal TERM left sudo live"
[[ ! -e $protected_dir/remove-ocaml-signal ]] || fail "OCaml signal child reused root"
pass "OCaml removal failure and signal paths invalidate credentials"
