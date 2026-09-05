#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command unshare
require_command setpriv
require_command cc

if [[ ${OMARCHY_DEBUG_SUDO_SECURITY_NS:-0} != 1 ]]; then
  outer_uid=$(id -u)
  outer_gid=$(id -g)
  subuid=$(awk -F: -v user="$(id -un)" '$1 == user { print $2; exit }' /etc/subuid)
  subgid=$(awk -F: -v user="$(id -un)" '$1 == user { print $2; exit }' /etc/subgid)
  if [[ -z $subuid || -z $subgid ]]; then
    pass "no subordinate uid/gid range; skipping debug sudo proof"
    exit 0
  fi
  exec unshare --user --mount \
    --map-users "0:$outer_uid:1" --map-users "1:$subuid:65536" \
    --map-groups "0:$outer_gid:1" --map-groups "1:$subgid:65536" \
    env OMARCHY_DEBUG_SUDO_SECURITY_NS=1 bash "$0"
fi

[[ $(id -u) == 0 ]] || fail "debug proof did not enter its root namespace"

test_tmp=$(mktemp -d)
mount -t tmpfs -o mode=0755,suid tmpfs "$test_tmp"
stub_bin="$test_tmp/bin"
script_dir="$test_tmp/scripts"
test_home="$test_tmp/home"
root_dir="$test_tmp/root"
event_log="$test_tmp/events"
token="$test_tmp/sudo-token"
victim="$root_dir/published"
armed="$test_tmp/waiter-armed"
mkdir -p "$stub_bin" "$script_dir" "$test_home/runtime" "$root_dir"
touch "$event_log"
chown -R 1000:1000 "$test_home" "$event_log"
chmod 0700 "$test_home" "$test_home/runtime"
chmod 0755 "$test_tmp" "$stub_bin" "$script_dir" "$root_dir"
chmod 0600 "$event_log"

cleanup() {
  local status=$?
  trap - EXIT
  rm -f "$armed"
  [[ ! -s $test_home/waiter.pid ]] || kill "$(<"$test_home/waiter.pid")" 2>/dev/null || true
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

static const char *need(const char *name) {
  const char *value = getenv(name);
  if (!value || !*value) exit(125);
  return value;
}

static void event(const char *message) {
  int fd = open(need("TEST_EVENT_LOG"), O_WRONLY | O_APPEND);
  if (fd < 0 || dprintf(fd, "%s\n", message) < 0) exit(125);
  close(fd);
}

int main(int argc, char **argv) {
  const char *token = need("TEST_SUDO_TOKEN");
  int index = 1, no_update = 0, noninteractive = 0, fd;
  if (argc == 2 && !strcmp(argv[1], "-h")) {
    if (getenv("TEST_SUDO_NO_N")) puts("usage: sudo [-ABbEHknPS] command");
    else puts("usage: sudo [-ABbEHkNnPS] command");
    return 0;
  }
  if (argc == 2 && !strcmp(argv[1], "-k")) {
    event("invalidate");
    if (unlink(token) && errno != ENOENT) return 121;
    fd = open(need("TEST_WAITER_ARMED"), O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return 122;
    close(fd);
    return 0;
  }
  if (index < argc && !strcmp(argv[index], "-N")) { no_update = 1; index++; }
  if (index < argc && !strcmp(argv[index], "-n")) { noninteractive = 1; index++; }
  if (index < argc && !strcmp(argv[index], "--")) index++;
  if (noninteractive && access(token, F_OK)) return 1;
  if (no_update) {
    event("grant-no-update");
  } else if (!noninteractive) {
    event("publish-token");
    fd = open(token, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return 123;
    close(fd);
    usleep(200000);
  }
  if (index >= argc || setgid(0) || setuid(0)) return 124;
  if (!strcmp(argv[index], "/usr/bin/dmesg")) {
    puts("modeled kernel log");
    return 0;
  }
  execv(argv[index], &argv[index]);
  return 126;
}
C
cc -O2 -Wall -Wextra -o "$stub_bin/sudo" "$test_tmp/sudo.c"
chown 0:0 "$stub_bin/sudo"
chmod 4755 "$stub_bin/sudo"

cat >"$stub_bin/inxi" <<'STUB'
#!/bin/bash
: >"$TEST_COLLECTOR_RAN"
printf 'harmless inxi output\n'
STUB
cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
case "$*" in
  '-Q omarchy-dev') printf 'omarchy-dev audit\n' ;;
  '-Qqe'|'-Sql') : ;;
  *) exit 1 ;;
esac
STUB
for command in journalctl expac; do
  printf '#!/bin/bash\nexit 0\n' >"$stub_bin/$command"
done
chmod 0755 "$stub_bin/inxi" "$stub_bin/pacman" "$stub_bin/journalctl" "$stub_bin/expac"

sed "s#/usr/bin/sudo#$stub_bin/sudo#g" \
  "$ROOT/bin/omarchy-security-functions" >"$script_dir/omarchy-security-functions"
sed "s#/usr/bin/sudo#$stub_bin/sudo#g" \
  "$ROOT/bin/omarchy-debug" >"$script_dir/omarchy-debug"
chmod 0755 "$script_dir/omarchy-security-functions" "$script_dir/omarchy-debug"

printf 'debug-payload\n' >"$test_home/payload"
chown 1000:1000 "$test_home/payload"
chmod 0600 "$test_home/payload"

start_waiter() {
  rm -f "$victim" "$test_home/reused" "$test_home/waiter.pid"
  setpriv --reuid=1000 --regid=1000 --clear-groups \
    env -i HOME="$test_home" TEST_SUDO="$stub_bin/sudo" \
      TEST_SUDO_TOKEN="$token" TEST_EVENT_LOG="$event_log" TEST_WAITER_ARMED="$armed" \
      TEST_PAYLOAD="$test_home/payload" TEST_VICTIM="$victim" \
      bash -c '
        echo $$ >"$HOME/waiter.pid"
        while [[ ! -e $TEST_WAITER_ARMED ]]; do /usr/bin/sleep 0.005; done
        while [[ -e $TEST_WAITER_ARMED ]]; do
          if "$TEST_SUDO" -n -- /usr/bin/install -o 0 -g 0 -m 0600 "$TEST_PAYLOAD" "$TEST_VICTIM" 2>/dev/null; then
            : >"$HOME/reused"
            exit 0
          fi
          /usr/bin/sleep 0.005
        done
      ' &
}

run_debug() {
  local command=$1
  shift
  setpriv --reuid=1000 --regid=1000 --clear-groups \
    env -i HOME="$test_home" XDG_RUNTIME_DIR="$test_home/runtime" \
      PATH="$stub_bin:/usr/bin:/bin" TEST_SUDO_TOKEN="$token" \
      TEST_EVENT_LOG="$event_log" TEST_WAITER_ARMED="$armed" \
      TEST_COLLECTOR_RAN="$test_home/collector" "$@" "$command" --print >/dev/null
}

: >"$event_log"
: >"$token"
chown 1000:1000 "$token"
rm -f "$armed" "$test_home/collector"
start_waiter
run_debug "$script_dir/omarchy-debug"
rm -f "$armed"
wait "$(<"$test_home/waiter.pid")" 2>/dev/null || true
[[ -e $test_home/collector && ! -e $victim && ! -e $test_home/reused && ! -e $token ]] ||
  fail "debug collector reused or retained sudo authorization"
grep -qxF grant-no-update "$event_log" || fail "debug dmesg did not use sudo --no-update"
[[ $(grep -c '^invalidate$' "$event_log") -ge 3 ]] || fail "debug did not invalidate at entry, after dmesg, and cleanup"
pass "debug starts cold and keeps collectors outside command-scoped dmesg authorization"

: >"$event_log"
rm -f "$token" "$armed" "$test_home/collector"
mutant="$script_dir/omarchy-debug-mutant"
sed "s#$stub_bin/sudo -N --#$stub_bin/sudo --#" "$script_dir/omarchy-debug" >"$mutant"
chmod 0755 "$mutant"
start_waiter
run_debug "$mutant"
rm -f "$armed"
wait "$(<"$test_home/waiter.pid")" 2>/dev/null || true
[[ -e $test_home/reused && -e $victim ]] || fail "removing -N did not restore the modeled credential race"
pass "sudo --no-update is mutation-tested as the load-bearing race guard"

: >"$event_log"
rm -f "$token" "$armed" "$test_home/collector" "$victim"
if run_debug "$script_dir/omarchy-debug" TEST_SUDO_NO_N=1; then
  fail "debug accepted sudo without --no-update support"
fi
[[ ! -e $test_home/collector && ! -e $token && ! -e $victim ]] ||
  fail "unsupported sudo reached user-resolved collectors"
pass "unsupported sudo fails before user-resolved collection"

bash_env="$test_home/bash-env"
startup_marker="$test_home/bash-env-ran"
printf ': >"$TEST_STARTUP_MARKER"\nset -o privileged\n' >"$bash_env"
if setpriv --reuid=1000 --regid=1000 --clear-groups \
  env -i HOME="$test_home" PATH="$stub_bin:/usr/bin:/bin" BASH_ENV="$bash_env" \
    TEST_STARTUP_MARKER="$startup_marker" TEST_SUDO_TOKEN="$token" \
    TEST_EVENT_LOG="$event_log" TEST_WAITER_ARMED="$armed" \
    /usr/bin/bash "$script_dir/omarchy-debug" -p --print >/dev/null 2>&1; then
  fail "debug accepted an ordinary Bash launch with a decoy -p"
fi
[[ -e $startup_marker && ! -e $token && ! -e $victim ]] ||
  fail "unsafe Bash startup reached the privileged debug workflow"
pass "privileged Bash startup suppresses BASH_ENV before the first command"
