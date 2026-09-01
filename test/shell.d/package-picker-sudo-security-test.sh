#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command unshare
require_command setpriv
require_command gcc

if [[ ${OMARCHY_PACKAGE_PICKER_SECURITY_NS:-0} != 1 ]]; then
  outer_uid=$(id -u)
  outer_gid=$(id -g)
  subuid=$(awk -F: -v user="$(id -un)" '$1 == user { print $2; exit }' /etc/subuid)
  subgid=$(awk -F: -v group="$(id -gn)" '$1 == group { print $2; exit }' /etc/subgid)
  if [[ -z $subuid || -z $subgid ]]; then
    pass "no subordinate uid/gid range; skipping package-picker namespace proof"
    exit 0
  fi
  exec unshare --user --mount     --map-users "0:$outer_uid:1" --map-users "1:$subuid:65536"     --map-groups "0:$outer_gid:1" --map-groups "1:$subgid:65536"     env OMARCHY_PACKAGE_PICKER_SECURITY_NS=1 bash "$0"
fi

[[ $(id -u) == 0 ]] || fail "package-picker proof did not enter its root namespace"

test_tmp=$(mktemp -d)
mount -t tmpfs -o mode=0755,suid tmpfs "$test_tmp"
stub_bin=$test_tmp/bin
script_dir=$test_tmp/scripts
test_home=$test_tmp/home
protected_dir=$test_tmp/protected
event_log=$test_tmp/events
token=$test_tmp/sudo-token
target=$protected_dir/published
mkdir -p "$stub_bin" "$script_dir" "$test_home" "$protected_dir"
touch "$event_log"
chown -R 1000:1000 "$test_home" "$event_log"
chmod 0700 "$test_home"
chmod 0755 "$stub_bin" "$script_dir" "$protected_dir"
chmod 0600 "$event_log"

cleanup() {
  local status=$? pid_file
  trap - EXIT
  for pid_file in "$test_home"/*.pid; do
    [[ -s $pid_file ]] || continue
    kill "$(<"$pid_file")" 2>/dev/null || true
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

static int token_exists(void) {
  return access(required("TEST_SUDO_TOKEN"), F_OK) == 0;
}

static int create_token(void) {
  int fd = open(required("TEST_SUDO_TOKEN"), O_WRONLY | O_CREAT | O_TRUNC, 0600);
  if (fd < 0) return 125;
  close(fd);
  return 0;
}

int main(int argc, char **argv) {
  int index = 1, no_update = 0, noninteractive = 0;

  if (argc == 2 && strcmp(argv[1], "-h") == 0) {
    if (getenv("TEST_SUDO_NO_N")) puts("usage: sudo [-ABbEHknPS] command");
    else puts("usage: sudo [-ABbEHkNnPS] command");
    return 0;
  }
  if (argc == 2 && strcmp(argv[1], "-k") == 0) {
    event("SUDO:invalidate");
    if (unlink(required("TEST_SUDO_TOKEN")) && errno != ENOENT) return 125;
    return 0;
  }
  if (index < argc && strcmp(argv[index], "-N") == 0) {
    no_update = 1;
    index++;
  }
  if (index < argc && strcmp(argv[index], "-n") == 0) {
    noninteractive = 1;
    index++;
  }
  if (index < argc && strcmp(argv[index], "--") == 0) index++;

  if (noninteractive && !token_exists()) {
    event("SUDO:deny-noninteractive");
    return 1;
  }
  if (no_update) {
    event("SUDO:grant-no-update");
  } else if (!noninteractive) {
    event("SUDO:publish-token");
    if (create_token()) return 125;
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
printf '%s\n' "$$" >"$HOME/attack-${TEST_ATTACK_LABEL}.pid"
for _ in {1..300}; do
  if "$TEST_SUDO" -n -- /usr/bin/install -o 0 -g 0 -m 0600       "$HOME/payload" "$TEST_PROTECTED_TARGET" 2>/dev/null; then
    printf 'ATTACK:root-reused\n' >>"$TEST_EVENT_LOG"
    : >"$HOME/attack-${TEST_ATTACK_LABEL}.done"
    exit 0
  fi
  /usr/bin/sleep 0.005
done
printf 'ATTACK:blocked\n' >>"$TEST_EVENT_LOG"
: >"$HOME/attack-${TEST_ATTACK_LABEL}.done"
ATTACK
chmod 0755 "$test_home/attack"
chown 1000:1000 "$test_home/attack"

cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
if [[ ${1:-} == -Slq ]]; then
  printf 'safe-package\n'
  exit 0
fi
printf 'PACMAN:%s' "$(/usr/bin/id -u)" >>"$TEST_EVENT_LOG"
printf ' <%s>' "$@" >>"$TEST_EVENT_LOG"
printf '\n' >>"$TEST_EVENT_LOG"
[[ ${TEST_PACMAN_DELAY:-0} != 1 ]] || /usr/bin/sleep 0.15
[[ ${TEST_PACMAN_FAIL:-0} != 1 ]] || exit 77
STUB

cat >"$stub_bin/yay" <<'STUB'
#!/bin/bash
if [[ ${1:-} == -Qqe ]]; then
  printf 'safe-package\n'
  exit 0
fi
exit 1
STUB

cat >"$stub_bin/fzf" <<'STUB'
#!/bin/bash
printf 'FZF\n' >>"$TEST_EVENT_LOG"
/usr/bin/cat >/dev/null
if [[ ${TEST_START_ATTACK:-0} == 1 ]]; then
  "$HOME/attack" >/dev/null 2>&1 &
fi
printf '%s\n' "${TEST_SELECTION:-safe-package}"
STUB

cat >"$stub_bin/omarchy-show-done" <<'STUB'
#!/bin/bash
printf 'DONE\n' >>"$TEST_EVENT_LOG"
STUB
chmod 0755 "$stub_bin/pacman" "$stub_bin/yay" "$stub_bin/fzf" "$stub_bin/omarchy-show-done"

sed -e "s#/usr/bin/sudo#$stub_bin/sudo#g"   "$ROOT/bin/omarchy-security-functions" >"$script_dir/omarchy-security-functions"
sed   -e "s#/usr/bin/sudo#$stub_bin/sudo#g"   -e "s#/usr/bin/pacman#$stub_bin/pacman#g"   -e "s#/usr/bin/fzf#$stub_bin/fzf#g"   -e "s#/usr/bin/omarchy-show-done#$stub_bin/omarchy-show-done#g"   "$ROOT/bin/omarchy-pkg-install" >"$script_dir/omarchy-pkg-install"
sed   -e "s#/usr/bin/sudo#$stub_bin/sudo#g"   -e "s#/usr/bin/pacman#$stub_bin/pacman#g"   -e "s#/usr/bin/fzf#$stub_bin/fzf#g"   -e "s#/usr/bin/yay#$stub_bin/yay#g"   -e "s#/usr/bin/omarchy-show-done#$stub_bin/omarchy-show-done#g"   "$ROOT/bin/omarchy-pkg-remove" >"$script_dir/omarchy-pkg-remove"
chmod 0755 "$script_dir"/*

run_picker() {
  local script=$1 label=$2 expected_status=$3
  shift 3
  : >"$event_log"
  rm -f "$token" "$target" "$test_home/attack-$label.done" "$test_home/attack-$label.pid"
  set +e
  setpriv --reuid=1000 --regid=1000 --clear-groups     env -i HOME="$test_home" PATH=/usr/bin:/bin       TEST_ATTACK_LABEL="$label" TEST_EVENT_LOG="$event_log"       TEST_PROTECTED_TARGET="$target" TEST_SUDO="$stub_bin/sudo"       TEST_SUDO_TOKEN="$token" "$@" "$script"
  picker_status=$?
  set -e
  (( picker_status == expected_status )) ||
    fail "$label returned $picker_status instead of $expected_status"
}

wait_for_attack() {
  local label=$1
  for _ in {1..400}; do
    [[ -e $test_home/attack-$label.done ]] && return
    /usr/bin/sleep 0.005
  done
  fail "$label attack child did not finish"
}

run_picker "$script_dir/omarchy-pkg-install" install 0   TEST_START_ATTACK=1 TEST_SELECTION=safe-package
wait_for_attack install
[[ ! -e $target && ! -e $token ]] ||
  fail "repository picker discovery reused or retained sudo authority"
grep -Fxq 'SUDO:grant-no-update' "$event_log" ||
  fail "repository picker did not use command-scoped sudo"
grep -Fq 'PACMAN:0 <-S> <--noconfirm> <--> <safe-package>' "$event_log" ||
  fail "repository picker did not pass a validated selection after --"
pass "repository picker keeps configurable discovery outside reusable sudo authority"

run_picker "$script_dir/omarchy-pkg-remove" remove 0   TEST_START_ATTACK=1 TEST_SELECTION=safe-package
wait_for_attack remove
[[ ! -e $target && ! -e $token ]] ||
  fail "package remover discovery reused or retained sudo authority"
grep -Fq 'PACMAN:0 <-Rns> <--noconfirm> <--> <safe-package>' "$event_log" ||
  fail "package remover did not pass a validated selection after --"
pass "package remover keeps configurable discovery outside reusable sudo authority"

mutated=$script_dir/omarchy-pkg-install-mutated
sed "s#$stub_bin/sudo -N --#$stub_bin/sudo --#"   "$script_dir/omarchy-pkg-install" >"$mutated"
chmod 0755 "$mutated"
run_picker "$mutated" mutation 0   TEST_START_ATTACK=1 TEST_SELECTION=safe-package TEST_PACMAN_DELAY=1
wait_for_attack mutation
[[ -f $target ]] ||
  fail "removing the -N guard did not restore the repository-picker exploit"
grep -Fxq 'package-picker-payload' "$target" ||
  fail "mutated picker did not publish the modeled attacker payload"
pass "command-scoped sudo is mutation-tested as the load-bearing guard"

run_picker "$script_dir/omarchy-pkg-install" invalid 2   TEST_SELECTION=--config
[[ ! -e $target && ! -e $token ]] ||
  fail "invalid package selection reached privileged publication"
! grep -q '^PACMAN:0' "$event_log" ||
  fail "option-shaped package selection reached pacman"
pass "picker rejects option-shaped selections before sudo"

run_picker "$script_dir/omarchy-pkg-install" unsupported 1   TEST_SUDO_NO_N=1 TEST_SELECTION=safe-package
! grep -q '^FZF$' "$event_log" ||
  fail "unsupported sudo reached configurable picker code"
[[ ! -e $token ]] || fail "unsupported sudo left a credential live"
pass "unsupported command-scoped sudo fails before discovery"

run_picker "$script_dir/omarchy-pkg-install" failure 77   TEST_START_ATTACK=1 TEST_SELECTION=safe-package TEST_PACMAN_FAIL=1
wait_for_attack failure
[[ ! -e $target && ! -e $token ]] ||
  fail "failed package transaction exposed reusable sudo authority"
pass "transaction failure leaves discovery children unprivileged"

bash_env=$test_home/picker-bash-env
cat >"$bash_env" <<'BASH_ENV'
if [[ $0 == "$TEST_PICKER_SCRIPT" ]]; then
  "$HOME/attack" >/dev/null 2>&1 &
fi
BASH_ENV
chown 1000:1000 "$bash_env"
run_picker "$script_dir/omarchy-pkg-install" startup 0   BASH_ENV="$bash_env" TEST_PICKER_SCRIPT="$script_dir/omarchy-pkg-install"   TEST_SELECTION=safe-package
wait_for_attack startup
[[ ! -e $target && ! -e $token ]] ||
  fail "BASH_ENV child reused later package authorization"
pass "startup and picker children cannot reuse the later no-update grant"
