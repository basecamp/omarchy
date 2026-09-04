#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command gcc
require_command setpriv
require_command unshare

if [[ ${OMARCHY_REMOVE_DEV_ENV_SECURITY_NS:-0} != "1" ]]; then
  outer_uid=$(id -u)
  outer_gid=$(id -g)
  outer_user=$(id -un)
  subuid_entry=$(awk -F: -v user="$outer_user" -v uid="$outer_uid" '($1 == user || $1 == uid) && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $3 >= 1000 { print $2 ":" $3; exit }' /etc/subuid)
  subgid_entry=$(awk -F: -v user="$outer_user" -v uid="$outer_uid" '($1 == user || $1 == uid) && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $3 >= 1000 { print $2 ":" $3; exit }' /etc/subgid)

  if [[ -z $subuid_entry || -z $subgid_entry ]]; then
    pass "no subordinate uid/gid range covering test user 1000; skipping OCaml sudo namespace proof"
    exit 0
  fi
  IFS=: read -r subuid subuid_count <<<"$subuid_entry"
  IFS=: read -r subgid subgid_count <<<"$subgid_entry"

  exec unshare --user --mount \
    --map-users "0:$outer_uid:1" --map-users "1:$subuid:$subuid_count" \
    --map-groups "0:$outer_gid:1" --map-groups "1:$subgid:$subgid_count" \
    env OMARCHY_REMOVE_DEV_ENV_SECURITY_NS=1 bash "$0"
fi

(( EUID == 0 )) || fail "OCaml sudo proof did not enter its root namespace"

test_tmp=$(mktemp -d)
test_home=$test_tmp/home
stub_bin=$test_home/bin
event_log=$test_tmp/events
token=$test_tmp/sudo-token
protected_target=$test_tmp/root-reused
active_session=""

cleanup() {
  local status=$?
  trap - EXIT

  if [[ $active_session =~ ^[1-9][0-9]*$ ]]; then
    kill -TERM -- "-$active_session" 2>/dev/null || kill -TERM "$active_session" 2>/dev/null || true
    kill -KILL -- "-$active_session" 2>/dev/null || kill -KILL "$active_session" 2>/dev/null || true
  fi

  if [[ -s $test_home/attack.pid ]]; then
    attack_pid=$(<"$test_home/attack.pid")
    kill "$attack_pid" 2>/dev/null || true
  fi

  umount -l /usr/bin/sudo 2>/dev/null || true
  umount -l "$test_tmp" 2>/dev/null || true
  rm -rf "$test_tmp" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT

mount -t tmpfs -o mode=0755,suid tmpfs "$test_tmp"
mkdir -p "$stub_bin"
touch "$event_log"

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

int main(int argc, char **argv) {
  const char *token = required("TEST_SUDO_TOKEN");

  if (geteuid() != 0) return 125;

  if (argc == 2 && strcmp(argv[1], "-k") == 0) {
    event("invalidate");
    if (unlink(token) && errno != ENOENT) return 125;
    return 0;
  }

  if (argc == 3 && strcmp(argv[1], "-N") == 0 && strcmp(argv[2], "-V") == 0) {
    event("probe-no-update");
    return getenv("TEST_SUDO_NO_N") ? 2 : 0;
  }

  if (argc == 6 && strcmp(argv[1], "-N") == 0 && strcmp(argv[2], "--") == 0 &&
      strcmp(argv[3], "/usr/bin/rm") == 0 && strcmp(argv[4], "-f") == 0 &&
      strcmp(argv[5], "/usr/local/bin/opam") == 0) {
    event("remove-opam-no-update");
    return getenv("TEST_RM_FAIL") ? 83 : 0;
  }

  if (argc >= 3 && strcmp(argv[1], "-n") == 0) {
    if (access(token, F_OK) == 0) {
      int fd = open(required("TEST_PROTECTED_TARGET"), O_WRONLY | O_CREAT | O_TRUNC, 0600);
      if (fd < 0) return 125;
      close(fd);
      event("attack-reused-root");
      return 0;
    }
    event("attack-denied");
    return 1;
  }

  event("unexpected-sudo");
  return 124;
}
C

gcc -O2 -Wall -Wextra -o "$test_tmp/sudo" "$test_tmp/sudo.c"
chown 0:0 "$test_tmp/sudo"
chmod 4755 "$test_tmp/sudo"
mount --bind "$test_tmp/sudo" /usr/bin/sudo

cat >"$stub_bin/attack" <<'STUB'
#!/bin/bash

printf '%s\n' "$$" >"$HOME/attack.pid"
for _ in {1..200}; do
  if /usr/bin/sudo -n -- /usr/bin/true 2>/dev/null; then
    exit 0
  fi
  /usr/bin/sleep 0.005
done
STUB

cat >"$stub_bin/opam" <<'STUB'
#!/bin/bash

printf 'opam-ran\n' >>"$TEST_EVENT_LOG"
/usr/bin/setsid --fork "$HOME/bin/attack" >/dev/null 2>&1

if [[ ${TEST_OPAM_BLOCK:-0} == "1" ]]; then
  printf 'ready\n' >"$HOME/ready"
  trap 'exit 143' TERM
  while :; do /usr/bin/sleep 0.05; done
fi
STUB

cat >"$stub_bin/mise" <<'STUB'
#!/bin/bash
printf 'mise:%s\n' "$*" >>"$TEST_EVENT_LOG"
STUB

chmod 0755 "$stub_bin"/*
chown -R 1000:1000 "$test_home"
chown 1000:1000 "$event_log"

base_env=(
  HOME="$test_home"
  USER=test
  LOGNAME=test
  PATH="$stub_bin:/usr/bin:/bin"
  TEST_EVENT_LOG="$event_log"
  TEST_SUDO_TOKEN="$token"
  TEST_PROTECTED_TARGET="$protected_target"
)

run_user() {
  setpriv --reuid=1000 --regid=1000 --clear-groups env -i "${base_env[@]}" "$@"
}

reset_case() {
  if [[ -s $test_home/attack.pid ]]; then
    attack_pid=$(<"$test_home/attack.pid")
    kill "$attack_pid" 2>/dev/null || true
  fi
  : >"$event_log"
  chown 1000:1000 "$event_log"
  rm -f "$token" "$protected_target" "$test_home/attack.pid" "$test_home/ready"
}

wait_for_attack() {
  for _ in {1..240}; do
    grep -q '^attack-' "$event_log" 2>/dev/null && return 0
    sleep 0.005
  done
  return 1
}

assert_ocaml_invalidations() {
  local context=$1 invalidations
  invalidations=$(grep -Fxc 'invalidate' "$event_log" || true)
  (( invalidations == 2 )) || fail "$context did not invalidate sudo credentials before and after OCaml removal (saw $invalidations invalidations)"
}

reset_case
touch "$token"
chown 0:0 "$token"
run_user bash "$ROOT/bin/omarchy-remove-dev-env" ocaml
wait_for_attack || fail "hostile opam did not exercise the detached sudo poller"
[[ ! -e $protected_target ]] || fail "hostile opam reused root authorization"
[[ ! -e $token ]] || fail "OCaml removal left a reusable sudo credential"
assert_ocaml_invalidations "successful OCaml removal"
grep -Fxq 'remove-opam-no-update' "$event_log" || fail "OCaml removal did not use sudo --no-update"
! grep -Fxq 'attack-reused-root' "$event_log" || fail "OCaml removal published reusable authorization"
pass "OCaml removal keeps user-controlled opam outside reusable sudo authorization"

reset_case
if run_user env TEST_SUDO_NO_N=1 bash "$ROOT/bin/omarchy-remove-dev-env" ocaml; then
  fail "OCaml removal accepted sudo without --no-update support"
fi
! grep -Fxq 'opam-ran' "$event_log" || fail "unsupported sudo reached user-controlled opam"
assert_ocaml_invalidations "unsupported sudo exit"
pass "OCaml removal validates --no-update support before running opam"

reset_case
if run_user env TEST_RM_FAIL=1 bash "$ROOT/bin/omarchy-remove-dev-env" ocaml; then
  fail "OCaml removal ignored root cleanup failure"
fi
[[ ! -e $token ]] || fail "failed OCaml cleanup left a reusable sudo credential"
assert_ocaml_invalidations "failed OCaml cleanup"
pass "OCaml cleanup failures propagate and invalidate credentials"

reset_case
touch "$token"
chown 0:0 "$token"
setpriv --reuid=1000 --regid=1000 --clear-groups \
  env -i "${base_env[@]}" TEST_OPAM_BLOCK=1 \
  /usr/bin/setsid bash "$ROOT/bin/omarchy-remove-dev-env" ocaml &
session=$!
active_session=$session

for _ in {1..200}; do
  [[ -e $test_home/ready ]] && break
  sleep 0.005
done
[[ -e $test_home/ready ]] || fail "OCaml signal fixture did not become ready"
kill -TERM -- "-$session" 2>/dev/null || kill -TERM "$session"
set +e
wait "$session"
signal_status=$?
set -e
active_session=""
(( signal_status != 0 )) || fail "terminated OCaml removal unexpectedly succeeded"
[[ ! -e $token ]] || fail "terminated OCaml removal left a reusable sudo credential"
[[ ! -e $protected_target ]] || fail "detached opam child reused root after termination"
assert_ocaml_invalidations "terminated OCaml removal"
pass "OCaml removal invalidates credentials on signals"

reset_case
run_user bash "$ROOT/bin/omarchy-remove-dev-env" node
! grep -Eq '^(invalidate|probe-no-update|unexpected-sudo)$' "$event_log" ||
  fail "non-OCaml removal crossed the sudo boundary"
grep -Fxq 'mise:uninstall node --all' "$event_log" || fail "Node removal did not run"
grep -Fxq 'mise:rm -g node' "$event_log" || fail "Node removal did not clear the global version"
pass "non-OCaml removals do not inspect or invalidate sudo credentials"
