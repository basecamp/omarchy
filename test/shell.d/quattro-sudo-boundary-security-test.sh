#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command gcc

if [[ ${OMARCHY_QUATTRO_SECURITY_NS:-} != 1 ]]; then
  outer_uid=$(id -u)
  outer_gid=$(id -g)
  subuid=$(awk -F: -v user="$(id -un)" '$1 == user { print $2; exit }' /etc/subuid)
  subgid=$(awk -F: -v group="$(id -gn)" '$1 == group { print $2; exit }' /etc/subgid)

  if [[ -z $subuid || -z $subgid ]]; then
    pass "no subordinate uid/gid range; skipping Quattro sudo-boundary proof"
    exit 0
  fi

  exec unshare --user --mount \
    --map-users "0:$outer_uid:1" --map-users "1:$subuid:65536" \
    --map-groups "0:$outer_gid:1" --map-groups "1:$subgid:65536" \
    env OMARCHY_QUATTRO_SECURITY_NS=1 bash "$0"
fi

[[ $(id -u) == 0 ]] || fail "Quattro sudo-boundary proof entered its root namespace"

test_tmp=$(mktemp -d)
mount -t tmpfs -o mode=0755 tmpfs "$test_tmp"
cleanup() {
  umount /usr/share/omarchy/default/omarchy 2>/dev/null || true
  umount /usr/share/omarchy/bin 2>/dev/null || true
  umount /usr/bin/lspci 2>/dev/null || true
  umount /usr/bin/id 2>/dev/null || true
  umount /usr/bin/getent 2>/dev/null || true
  umount /usr/bin/pacman-conf 2>/dev/null || true
  umount /usr/bin/pacman 2>/dev/null || true
  umount /usr/bin/gum 2>/dev/null || true
  umount /usr/bin/systemctl 2>/dev/null || true
  umount /usr/bin/sudo 2>/dev/null || true
  rm -rf "$test_tmp"/*
  umount "$test_tmp" 2>/dev/null || umount -l "$test_tmp"
  rmdir "$test_tmp"
}
trap cleanup EXIT
chmod 0755 "$test_tmp"

stub_bin="$test_tmp/bin"
package_bin="$test_tmp/package-bin"
package_defaults="$test_tmp/package-defaults"
user_home="$test_tmp/user-home"
user_state="$test_tmp/user-state"
root_state="$test_tmp/root-state"
mkdir -p "$stub_bin" "$package_bin" "$package_defaults/sudo-no-update" \
  "$user_home/.local/bin" "$user_state" "$root_state"
chmod 0755 "$stub_bin" "$package_bin"
chown -R 1000:1000 "$user_home" "$user_state"
chmod 0700 "$user_home" "$user_state" "$root_state"

token="$root_state/global-sudo-token"
trace="$user_state/sudo-trace"
reboot_marker="$user_state/reboot-requested"
child_pid_file="$user_state/detached-child-pid"
payload="$user_state/payload"
protected_target="$root_state/user-tool-payload"
: >"$trace"
printf '%s\n' 'ATTACKER USER TOOL' >"$payload"
chown 1000:1000 "$trace" "$payload"
chmod 0666 "$trace"
chmod 0600 "$payload"

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
  if (!value || !*value) _exit(125);
  return value;
}

static void record(const char *event) {
  int fd = open(required_env("TEST_SUDO_TRACE"), O_WRONLY | O_APPEND);
  if (fd < 0) _exit(125);
  dprintf(fd, "%s\n", event);
  close(fd);
}

static int valid(void) {
  struct stat st;
  return stat(required_env("TEST_SUDO_TOKEN"), &st) == 0 && st.st_uid == 0;
}

static int validate(void) {
  int fd = open(required_env("TEST_SUDO_TOKEN"), O_WRONLY | O_CREAT | O_TRUNC, 0600);
  if (fd < 0) return 125;
  close(fd);
  record("VALIDATE");
  return 0;
}

int main(int argc, char **argv) {
  int noninteractive = 0;
  int no_update = 0;
  int command_index = 1;

  if (argc == 2 && strcmp(argv[1], "-v") == 0) return validate();
  if (argc == 2 && strcmp(argv[1], "-h") == 0) {
    puts("usage: sudo [-N] command");
    return 0;
  }
  if (argc == 2 && strcmp(argv[1], "-k") == 0) {
    record("INVALIDATE");
    return unlink(required_env("TEST_SUDO_TOKEN")) == 0 || errno == ENOENT ? 0 : 125;
  }

  if (argc > 1 && strcmp(argv[1], "-n") == 0) {
    noninteractive = 1;
    command_index = 2;
  } else if (argc > 1 && strcmp(argv[1], "-N") == 0) {
    no_update = 1;
    command_index = 2;
    record("NO_UPDATE_AUTH");
  }
  if (argc > command_index && strcmp(argv[command_index], "--") == 0) command_index++;
  if (noninteractive && argc == 3 && strcmp(argv[2], "true") == 0) {
    if (valid()) {
      record("KEEPALIVE_OK");
      return 0;
    }
    record("KEEPALIVE_DENIED");
    return 1;
  }

  if (noninteractive && argc > command_index && strcmp(argv[command_index], "/usr/bin/install") == 0) {
    if (!valid()) {
      record("USER_SUDO_DENIED");
      return 1;
    }
    record("USER_SUDO_REUSED");
    if (setgid(0) < 0 || setuid(0) < 0) return 125;
    execv(argv[command_index], &argv[command_index]);
    return 125;
  }

  if (!noninteractive && !no_update) {
    if (validate() != 0) return 125;
    record("ROOT_AUTHENTICATED");
  }

  if (!noninteractive && !no_update && argc > command_index && strcmp(argv[command_index], "/usr/bin/install") == 0) {
    record("USER_SUDO_AUTHENTICATED");
    if (setgid(0) < 0 || setuid(0) < 0) return 125;
    execv(argv[command_index], &argv[command_index]);
    return 125;
  }

  if (argc > command_index && strcmp(argv[command_index], "/usr/bin/gpg") == 0) {
    puts("pub:::::::::");
    puts("fpr:::::::::40DFB630FF42BCFFB047046CF0134EE680CAC571:");
    return 0;
  }
  if (argc > command_index && strcmp(argv[command_index], "/usr/bin/snapper") == 0) {
    if (!no_update) {
      record("SNAPPER_REUSABLE_AUTH");
      return 125;
    }
    if (argc > command_index + 2 && strcmp(argv[command_index + 1], "--csvout") == 0 &&
        strcmp(argv[command_index + 2], "list-configs") == 0) {
      record("SNAPPER_LIST_NO_UPDATE");
      puts("Config,Subvolume");
      puts("root,/");
      return 0;
    }
    if (argc > command_index + 3 && strcmp(argv[command_index + 1], "-c") == 0 &&
        strcmp(argv[command_index + 3], "create") == 0) {
      record("SNAPPER_CREATE_NO_UPDATE");
      return 0;
    }
    if (argc > command_index + 3 && strcmp(argv[command_index + 1], "-c") == 0 &&
        strcmp(argv[command_index + 3], "cleanup") == 0) {
      record("SNAPPER_CLEANUP_NO_UPDATE");
      return 0;
    }
    return 125;
  }
  if (argc > command_index && strcmp(argv[command_index], "test") == 0) {
    execv("/usr/bin/test", &argv[command_index]);
    return 125;
  }
  const char *fail_command = getenv("TEST_FAIL_ROOT_COMMAND");
  if (argc > command_index && fail_command && *fail_command && strcmp(argv[command_index], fail_command) == 0) {
    record("ROOT_FAILURE");
    return 42;
  }

  if (argc > command_index && (strcmp(argv[command_index], "env") == 0 || strcmp(argv[command_index], "/usr/bin/env") == 0)) {
    for (int i = command_index + 1; i < argc; i++) {
      if (strcmp(argv[i], "/usr/share/omarchy/bin/omarchy-apply-lock") == 0) {
        record("ROOT_SCRIPT_EXEC");
        if (setgid(0) < 0 || setuid(0) < 0) return 125;
        execv("/usr/bin/env", &argv[command_index]);
        return 125;
      }
    }
  }

  if (argc > command_index && (strcmp(argv[command_index], "tee") == 0 || strcmp(argv[command_index], "/usr/bin/tee") == 0)) {
    char buffer[4096];
    while (read(STDIN_FILENO, buffer, sizeof(buffer)) > 0) {}
  } else if (argc > command_index && (strcmp(argv[command_index], "install") == 0 || strcmp(argv[command_index], "/usr/bin/install") == 0)) {
    for (int i = command_index + 1; i < argc; i++) {
      if (strcmp(argv[i], "/dev/stdin") == 0) {
        char buffer[4096];
        while (read(STDIN_FILENO, buffer, sizeof(buffer)) > 0) {}
        break;
      }
    }
  }

  record(no_update ? "ROOT_NO_UPDATE_OPERATION" : "ROOT_OPERATION");
  return 0;
}
C
gcc -O2 -Wall -Wextra -o "$test_tmp/sudo" "$test_tmp/sudo.c"
chown 0:0 "$test_tmp/sudo"
chmod 4755 "$test_tmp/sudo"

cat >"$test_tmp/hostile-preload.c" <<'C'
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *required_env(const char *name) {
  const char *value = getenv(name);
  if (!value || !*value) _exit(125);
  return value;
}

static int sudo_ticket_valid(void) {
  pid_t pid = fork();
  int status = 0;
  if (pid < 0) return 0;
  if (pid == 0) {
    execl("/usr/bin/sudo", "sudo", "-n", "true", NULL);
    _exit(125);
  }
  if (waitpid(pid, &status, 0) != pid) return 0;
  return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

__attribute__((constructor)) static void spawn_waiter(void) {
  int marker = open(required_env("TEST_LD_PRELOAD_RAN"), O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (marker < 0) return;
  close(marker);

  pid_t child = fork();
  if (child < 0) return;
  if (child == 0) {
    unsetenv("LD_PRELOAD");
    unsetenv("LD_LIBRARY_PATH");
    while (access(required_env("TEST_LD_PRELOAD_ARMED"), F_OK) == 0) {
      if (sudo_ticket_valid()) {
        int reused = open(required_env("TEST_LD_PRELOAD_REUSED_SUDO"), O_WRONLY | O_CREAT, 0600);
        if (reused >= 0) close(reused);
        execl("/usr/bin/sudo", "sudo", "-n", "/usr/bin/install", "-o", "0", "-g", "0", "-m", "0600",
          required_env("TEST_PAYLOAD"), required_env("TEST_PROTECTED_TARGET"), NULL);
        _exit(125);
      }
      usleep(10000);
    }
    _exit(0);
  }

  int pid_file = open(required_env("TEST_LD_PRELOAD_PID_FILE"), O_WRONLY | O_CREAT | O_TRUNC, 0600);
  if (pid_file >= 0) {
    dprintf(pid_file, "%ld\n", (long)child);
    close(pid_file);
  }
}
C
gcc -shared -fPIC -O2 -Wall -Wextra -o "$test_tmp/hostile-preload.so" "$test_tmp/hostile-preload.c"
chmod 0755 "$test_tmp/hostile-preload.so"

cat >"$test_tmp/systemctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_REBOOT_TRACE"
: >"$TEST_REBOOT_MARKER"
STUB
chmod 0755 "$test_tmp/systemctl"

cat >"$test_tmp/gum" <<'STUB'
#!/bin/bash
exit "${TEST_GUM_STATUS:-1}"
STUB
chmod 0755 "$test_tmp/gum"

cat >"$stub_bin/getent" <<STUB
#!/bin/bash
if [[ \${1:-} == passwd && \${2:-} == quattro-audit ]]; then
  printf '%s\n' 'quattro-audit:x:4242:4242:Quattro Audit:$user_home:/bin/bash'
  exit 0
fi
exit 2
STUB

cat >"$stub_bin/id" <<'STUB'
#!/bin/bash
if [[ ${1:-} == -u && ${2:-} == quattro-audit ]]; then
  echo 4242
  exit 0
fi
exit 2
STUB

cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
[[ ${1:-} == -Qq ]] && exit 1
exit 0
STUB

cat >"$stub_bin/pacman-conf" <<'STUB'
#!/bin/bash
printf '%s\n' 'PackageRequired DatabaseOptional PackageTrustedOnly DatabaseTrustedOnly'
STUB

cat >"$stub_bin/lspci" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod 0755 "$stub_bin"/*

cat >"$package_bin/omarchy-audit-command" <<'STUB'
#!/bin/bash
set -e
command_name=${0##*/}

case "$command_name" in
  omarchy-apply-lock)
    : >"$TEST_APPLY_LOCK_RAN"
    if command -v fprintd-list >/dev/null 2>&1; then
      fprintd-list
    fi
    ;;
  omarchy-update-aur-pkgs)
    [[ ${OMARCHY_SUDO_NO_UPDATE:-} == 1 ]] || exit 99
    : >"$TEST_AUR_RAN"
    sudo /usr/bin/install -o 0 -g 0 -m 0600 "$TEST_PAYLOAD" "$TEST_PROTECTED_TARGET" || true
    if [[ -e $TEST_PROTECTED_TARGET ]]; then
      : >"$TEST_USER_REUSED_SUDO"
    fi
    ;;
  omarchy-migrate)
    [[ ${1:-} == --pending ]] && exit 1
    : >"$TEST_MIGRATIONS_RAN"
    if /usr/bin/sudo -n /usr/bin/install -o 0 -g 0 -m 0600 "$TEST_PAYLOAD" "$TEST_PROTECTED_TARGET"; then
      : >"$TEST_USER_REUSED_SUDO"
    fi
    ;;
  omarchy-update-mise)
    : >"$TEST_MISE_RAN"
    if /usr/bin/sudo -n /usr/bin/install -o 0 -g 0 -m 0600 "$TEST_PAYLOAD" "$TEST_PROTECTED_TARGET"; then
      : >"$TEST_USER_REUSED_SUDO"
    fi
    (
      while [[ ! -e $TEST_REBOOT_MARKER ]]; do sleep 0.01; done
      if /usr/bin/sudo -n /usr/bin/install -o 0 -g 0 -m 0600 "$TEST_PAYLOAD" "$TEST_PROTECTED_TARGET"; then
        : >"$TEST_DETACHED_REUSED_SUDO"
      fi
    ) &
    echo $! >"$TEST_DETACHED_PID_FILE"
    ;;
  omarchy-update-available)
    exit 1
    ;;
esac
exit 0
STUB
chmod 0755 "$package_bin/omarchy-audit-command"

cat >"$package_defaults/sudo-no-update/sudo" <<'STUB'
#!/bin/bash
exec /usr/bin/sudo -N -- "$@"
STUB
chmod 0755 "$package_defaults/sudo-no-update/sudo"

for command in \
  omarchy-apply-lock \
  omarchy-bar \
  omarchy-migrate \
  omarchy-refresh-applications \
  omarchy-restart-terminal \
  omarchy-theme-set \
  omarchy-theme-set-browser \
  omarchy-update-aur-pkgs \
  omarchy-update-available \
  omarchy-update-mise; do
  ln -s omarchy-audit-command "$package_bin/$command"
done

cat >"$user_home/.local/bin/preauth-waiter" <<'STUB'
#!/bin/bash
: >"$TEST_PREAUTH_COMMAND_RAN"
(
  while ! /usr/bin/sudo -n true >/dev/null 2>&1; do /usr/bin/sleep 0.01; done
  if /usr/bin/sudo -n /usr/bin/install -o 0 -g 0 -m 0600 "$TEST_PAYLOAD" "$TEST_PROTECTED_TARGET"; then
    : >"$TEST_PREAUTH_REUSED_SUDO"
  fi
) &
exec "/usr/bin/${0##*/}" "$@"
STUB
chmod 0755 "$user_home/.local/bin/preauth-waiter"
ln -s preauth-waiter "$user_home/.local/bin/grep"
ln -s preauth-waiter "$user_home/.local/bin/pacman"

cat >"$user_home/.local/bin/fprintd-list" <<'STUB'
#!/bin/bash
: >"$TEST_ROOT_PATH_EXEC"
/usr/bin/install -o 0 -g 0 -m 0600 "$TEST_PAYLOAD" "$TEST_PROTECTED_TARGET"
STUB
chmod 0755 "$user_home/.local/bin/fprintd-list"

bash_env="$user_home/malicious-bash-env"
cat >"$bash_env" <<'STUB'
: >"$TEST_BASH_ENV_RAN"
unset BASH_ENV
(
  while [[ -e $TEST_BASH_ENV_ARMED ]] && ! /usr/bin/sudo -n true >/dev/null 2>&1; do /usr/bin/sleep 0.01; done
  if [[ -e $TEST_BASH_ENV_ARMED ]] && /usr/bin/sudo -n /usr/bin/install -o 0 -g 0 -m 0600 "$TEST_PAYLOAD" "$TEST_PROTECTED_TARGET"; then
    : >"$TEST_BASH_ENV_REUSED_SUDO"
  fi
) &
echo $! >"$TEST_BASH_ENV_PID_FILE"
set -o privileged
STUB
chmod 0644 "$bash_env"

mount --bind "$test_tmp/sudo" /usr/bin/sudo
mount --bind "$test_tmp/systemctl" /usr/bin/systemctl
mount --bind "$test_tmp/gum" /usr/bin/gum
mount --bind "$stub_bin/pacman" /usr/bin/pacman
mount --bind "$stub_bin/pacman-conf" /usr/bin/pacman-conf
mount --bind "$stub_bin/getent" /usr/bin/getent
mount --bind "$stub_bin/id" /usr/bin/id
mount --bind "$stub_bin/lspci" /usr/bin/lspci
mount --bind "$package_bin" /usr/share/omarchy/bin
mount --bind "$package_defaults" /usr/share/omarchy/default/omarchy

export TEST_SUDO_TOKEN="$token"
export TEST_SUDO_TRACE="$trace"
export TEST_REBOOT_MARKER="$reboot_marker"
export TEST_REBOOT_TRACE="$user_state/reboot-trace"
export TEST_GUM_STATUS=1
export TEST_AUR_RAN="$user_state/aur-ran"
export TEST_APPLY_LOCK_RAN="$user_state/apply-lock-ran"
export TEST_MIGRATIONS_RAN="$user_state/migrations-ran"
export TEST_MISE_RAN="$user_state/mise-ran"
export TEST_PAYLOAD="$payload"
export TEST_PROTECTED_TARGET="$protected_target"
export TEST_USER_REUSED_SUDO="$user_state/user-reused-sudo"
export TEST_DETACHED_REUSED_SUDO="$user_state/detached-reused-sudo"
export TEST_DETACHED_PID_FILE="$child_pid_file"
export TEST_PREAUTH_COMMAND_RAN="$user_state/preauth-command-ran"
export TEST_PREAUTH_REUSED_SUDO="$user_state/preauth-reused-sudo"
export TEST_ROOT_PATH_EXEC="$root_state/user-path-executed-as-root"
export TEST_EXPORTED_FUNCTION_RAN="$user_state/exported-function-ran"
export TEST_EXPORTED_FUNCTION_REUSED_SUDO="$user_state/exported-function-reused-sudo"
export TEST_BASH_ENV_RAN="$user_state/bash-env-ran"
export TEST_BASH_ENV_REUSED_SUDO="$user_state/bash-env-reused-sudo"
export TEST_BASH_ENV_PID_FILE="$user_state/bash-env-pid"
export TEST_BASH_ENV_ARMED="$user_state/bash-env-armed"
export TEST_LD_PRELOAD_RAN="$user_state/ld-preload-ran"
export TEST_LD_PRELOAD_REUSED_SUDO="$user_state/ld-preload-reused-sudo"
export TEST_LD_PRELOAD_PID_FILE="$user_state/ld-preload-pid"
export TEST_LD_PRELOAD_ARMED="$user_state/ld-preload-armed"

grep -qF '/usr/bin/sudo -N -- "$@"' "$ROOT/bin/omarchy-upgrade-to-quattro" ||
  fail "Quattro no longer uses option-terminated sudo --no-update commands"

# A clean PATH is not sufficient: Bash imports exported functions before it
# starts reading the upgrader. This one would run on the first bare pacman call
# during the privileged phase if the upgrader did not isolate its interpreter.
pacman() {
  : >"$TEST_EXPORTED_FUNCTION_RAN"
  if /usr/bin/sudo -n /usr/bin/install -o 0 -g 0 -m 0600 "$TEST_PAYLOAD" "$TEST_PROTECTED_TARGET"; then
    : >"$TEST_EXPORTED_FUNCTION_REUSED_SUDO"
  fi
  /usr/bin/pacman "$@"
}
export -f pacman

# An ordinary explicit Bash evaluates BASH_ENV before the upgrader's first
# line. It must fail closed and never open sudo; supported invocations use -p,
# which suppresses both BASH_ENV and the exported function above.
: >"$TEST_BASH_ENV_ARMED"
set +e
setpriv --reuid 1000 --regid 1000 --clear-groups \
  env HOME="$user_home" USER=quattro-audit LOGNAME=quattro-audit BASH_ENV="$bash_env" \
  PATH="$user_home/.local/bin:/usr/bin:/bin" \
  /usr/bin/setsid /usr/bin/bash "$ROOT/bin/omarchy-upgrade-to-quattro" \
    --yes --reboot --channel stable --user quattro-audit \
  >"$test_tmp/nonprivileged-bash-out" 2>"$test_tmp/nonprivileged-bash-err"
nonprivileged_bash_status=$?
set -e
((nonprivileged_bash_status != 0)) || fail "an upgrade launched without bash -p fails closed"
[[ -e $TEST_BASH_ENV_RAN ]] || fail "the malicious BASH_ENV precondition was exercised"
[[ ! -e $token && ! -e $protected_target && ! -e $TEST_BASH_ENV_REUSED_SUDO ]] ||
  fail "a rejected non-privileged Bash invocation opened or reused sudo"
if [[ -f $TEST_BASH_ENV_PID_FILE ]]; then
  bash_env_child=$(cat "$TEST_BASH_ENV_PID_FILE")
  rm -f "$TEST_BASH_ENV_ARMED"
  /usr/bin/sleep 0.05
  /usr/bin/kill -KILL -- "$bash_env_child" 2>/dev/null || true
fi
rm -f "$TEST_BASH_ENV_RAN" "$TEST_BASH_ENV_REUSED_SUDO" "$TEST_BASH_ENV_PID_FILE" "$TEST_BASH_ENV_ARMED"

# Checking merely for any "-p" argv element is vacuous: BASH_ENV can enable
# privileged mode, replace the script arguments, and leave a decoy -p after
# the script pathname. The gate must bind -p to argv[1], where Bash options
# occur before startup files are evaluated.
argv_bash_env="$user_home/argv-position-bash-env"
argv_bash_env_marker="$user_state/argv-position-bash-env-ran"
cat >"$argv_bash_env" <<'STUB'
: >"$TEST_ARGV_BASH_ENV_RAN"
unset BASH_ENV
set -o privileged
set -- --yes --reboot --channel stable --user quattro-audit
STUB
chmod 0644 "$argv_bash_env"
: >"$trace"
set +e
setpriv --reuid 1000 --regid 1000 --clear-groups \
  env HOME="$user_home" USER=quattro-audit LOGNAME=quattro-audit \
  BASH_ENV="$argv_bash_env" TEST_ARGV_BASH_ENV_RAN="$argv_bash_env_marker" \
  TEST_FAIL_ROOT_COMMAND=pacman PATH="$user_home/.local/bin:/usr/bin:/bin" \
  /usr/bin/bash "$ROOT/bin/omarchy-upgrade-to-quattro" -p \
  >"$test_tmp/argv-position-out" 2>"$test_tmp/argv-position-err"
argv_position_status=$?
set -e
((argv_position_status != 0)) || fail "a decoy post-script -p passed the interpreter gate"
[[ -e $argv_bash_env_marker ]] || fail "the argv-position BASH_ENV precondition was exercised"
[[ ! -s $trace && ! -e $token && ! -e $protected_target ]] ||
  fail "a decoy post-script -p reached privileged Quattro work"
rm -f "$argv_bash_env_marker"

# LD_PRELOAD constructors run before the first Bash script line, so interpreter
# gates cannot prevent this detached waiter. The updater must remain safe even
# while the hostile constructor is demonstrably active: sudo -N authorizes root
# commands without ever creating the global token it is waiting to reuse.
: >"$TEST_LD_PRELOAD_ARMED"
: >"$trace"
set +e
setpriv --reuid 1000 --regid 1000 --clear-groups \
  env HOME="$user_home" USER=quattro-audit LOGNAME=quattro-audit \
  LD_PRELOAD="$test_tmp/hostile-preload.so" \
  TEST_FAIL_ROOT_COMMAND=pacman \
  PATH="$user_home/.local/bin:/usr/bin:/bin" \
  /usr/bin/bash -p "$ROOT/bin/omarchy-upgrade-to-quattro" \
    --yes --reboot --channel stable --user quattro-audit \
  >"$test_tmp/ld-preload-out" 2>"$test_tmp/ld-preload-err"
ld_preload_status=$?
set -e
((ld_preload_status != 0)) || fail "the LD_PRELOAD proof reached its injected root failure"
[[ -e $TEST_LD_PRELOAD_RAN ]] || fail "the hostile LD_PRELOAD constructor ran before the upgrader"
grep -q '^NO_UPDATE_AUTH$' "$trace" || fail "the LD_PRELOAD proof exercised sudo --no-update authorization"
[[ ! -e $token && ! -e $protected_target && ! -e $TEST_LD_PRELOAD_REUSED_SUDO ]] ||
  fail "the hostile LD_PRELOAD waiter received a reusable sudo timestamp"
rm -f "$TEST_LD_PRELOAD_ARMED"
if [[ -f $TEST_LD_PRELOAD_PID_FILE ]]; then
  ld_preload_child=$(cat "$TEST_LD_PRELOAD_PID_FILE")
  /usr/bin/sleep 0.05
  /usr/bin/kill -KILL -- "$ld_preload_child" 2>/dev/null || true
fi
rm -f "$TEST_LD_PRELOAD_RAN" "$TEST_LD_PRELOAD_REUSED_SUDO" "$TEST_LD_PRELOAD_PID_FILE"

# Mutation: replacing command-scoped sudo with ordinary sudo must recreate the
# credential window observed on the vulnerable upgrader. The same hostile
# pre-script constructor should then consume it before the injected failure.
mutated_upgrader="$test_tmp/omarchy-upgrade-with-reusable-sudo"
sed 's|/usr/bin/sudo -N -- "\$@"|/usr/bin/sudo -- "\$@"|' \
  "$ROOT/bin/omarchy-upgrade-to-quattro" >"$mutated_upgrader"
chmod 0755 "$mutated_upgrader"
: >"$TEST_LD_PRELOAD_ARMED"
: >"$trace"
rm -f "$protected_target" "$TEST_LD_PRELOAD_RAN" "$TEST_LD_PRELOAD_REUSED_SUDO" "$TEST_LD_PRELOAD_PID_FILE"
set +e
setpriv --reuid 1000 --regid 1000 --clear-groups \
  env HOME="$user_home" USER=quattro-audit LOGNAME=quattro-audit \
  LD_PRELOAD="$test_tmp/hostile-preload.so" \
  TEST_FAIL_ROOT_COMMAND=pacman \
  PATH="$user_home/.local/bin:/usr/bin:/bin" \
  /usr/bin/bash -p "$mutated_upgrader" \
    --yes --reboot --channel stable --user quattro-audit \
  >"$test_tmp/mutation-out" 2>"$test_tmp/mutation-err"
mutation_status=$?
set -e
(( mutation_status != 0 )) || fail "the reusable-sudo mutation reached its injected root failure"
for _ in {1..300}; do
  [[ -e $protected_target ]] && break
  /usr/bin/sleep 0.01
done
[[ -e $protected_target && -e $TEST_LD_PRELOAD_REUSED_SUDO ]] ||
  fail "removing sudo --no-update did not recreate detached credential reuse"
rm -f "$TEST_LD_PRELOAD_ARMED" "$token" "$protected_target"
if [[ -f $TEST_LD_PRELOAD_PID_FILE ]]; then
  mutation_child=$(cat "$TEST_LD_PRELOAD_PID_FILE")
  /usr/bin/kill -KILL -- "$mutation_child" 2>/dev/null || true
fi
rm -f "$TEST_LD_PRELOAD_RAN" "$TEST_LD_PRELOAD_REUSED_SUDO" "$TEST_LD_PRELOAD_PID_FILE"
pass "removing sudo --no-update recreates the Quattro credential leak"

# A privileged-stage failure must invalidate
# even a credential that predated this invocation, without entering user code.
setpriv --reuid 1000 --regid 1000 --clear-groups /usr/bin/sudo -v
set +e
setpriv --reuid 1000 --regid 1000 --clear-groups \
  env HOME="$user_home" USER=quattro-audit LOGNAME=quattro-audit \
  BASH_ENV="$bash_env" \
  TEST_FAIL_ROOT_COMMAND=pacman \
  PATH="$user_home/.local/bin:/usr/bin:/bin" \
  /usr/bin/bash -p "$ROOT/bin/omarchy-upgrade-to-quattro" \
    --yes --reboot --channel stable --user quattro-audit \
  >"$test_tmp/failure-out" 2>"$test_tmp/failure-err"
failure_status=$?
set -e
((failure_status != 0)) || fail "an injected privileged-stage failure reports failure"
[[ ! -e $token ]] || fail "failure cleanup left the global sudo timestamp valid"
[[ ! -e $TEST_MIGRATIONS_RAN && ! -e $TEST_MISE_RAN ]] ||
  fail "a privileged-stage failure crossed into user tooling"
[[ ! -e $TEST_PREAUTH_COMMAND_RAN && ! -e $TEST_PREAUTH_REUSED_SUDO && ! -e $protected_target ]] ||
  fail "caller-controlled PATH ran before the privileged boundary" \
    "command=$([[ -e $TEST_PREAUTH_COMMAND_RAN ]] && echo yes || echo no) reuse=$([[ -e $TEST_PREAUTH_REUSED_SUDO ]] && echo yes || echo no) target=$([[ -e $protected_target ]] && echo yes || echo no)"
[[ ! -e $TEST_EXPORTED_FUNCTION_RAN && ! -e $TEST_EXPORTED_FUNCTION_REUSED_SUDO ]] ||
  fail "an inherited Bash function ran during the privileged phase"
[[ ! -e $TEST_BASH_ENV_RAN && ! -e $TEST_BASH_ENV_REUSED_SUDO ]] ||
  fail "BASH_ENV ran in a supported privileged-shell invocation"
grep -q '^INVALIDATE$' "$trace" || fail "failure cleanup invalidated sudo"

# Retry from another already-valid global ticket. The successful upgrade must
# revoke it at its explicit boundary, not merely stop its own refresher.
: >"$trace"
rm -f "$reboot_marker" "$child_pid_file" "$TEST_AUR_RAN" "$TEST_APPLY_LOCK_RAN" \
  "$TEST_MIGRATIONS_RAN" "$TEST_MISE_RAN" "$TEST_USER_REUSED_SUDO" \
  "$TEST_DETACHED_REUSED_SUDO" "$TEST_PREAUTH_COMMAND_RAN" "$TEST_PREAUTH_REUSED_SUDO" \
  "$TEST_EXPORTED_FUNCTION_RAN" "$TEST_EXPORTED_FUNCTION_REUSED_SUDO"
setpriv --reuid 1000 --regid 1000 --clear-groups /usr/bin/sudo -v

set +e
setpriv --reuid 1000 --regid 1000 --clear-groups \
  env HOME="$user_home" USER=quattro-audit LOGNAME=quattro-audit \
  BASH_ENV="$bash_env" \
  PATH="$user_home/.local/bin:/usr/bin:/bin" \
  /usr/bin/bash -p "$ROOT/bin/omarchy-upgrade-to-quattro" \
    --yes --reboot --channel stable --user quattro-audit \
  >"$test_tmp/upgrade-out" 2>"$test_tmp/upgrade-err"
upgrade_status=$?
set -e

if [[ -f $child_pid_file ]]; then
  detached_pid=$(cat "$child_pid_file")
  for _ in {1..300}; do
    kill -0 "$detached_pid" 2>/dev/null || break
    sleep 0.01
  done
  kill "$detached_pid" 2>/dev/null || true
fi

if ((upgrade_status != 0)); then
  cat "$test_tmp/upgrade-out" >&2
  cat "$test_tmp/upgrade-err" >&2
  fail "the isolated real Quattro orchestration completed" "status=$upgrade_status"
fi
[[ -e $TEST_APPLY_LOCK_RAN && -e $TEST_AUR_RAN && -e $TEST_MIGRATIONS_RAN && -e $TEST_MISE_RAN ]] ||
  fail "the real orchestration did not reach its root script and user update phases"
[[ -e $reboot_marker ]] || fail "automatic reboot reached the unprivileged systemctl path"
[[ ! -e $token ]] || fail "the Quattro upgrade left the global sudo timestamp valid"
[[ ! -e $TEST_PREAUTH_COMMAND_RAN && ! -e $TEST_PREAUTH_REUSED_SUDO ]] ||
  fail "the upgrader executed a caller-controlled PATH command before opening sudo"
[[ ! -e $TEST_EXPORTED_FUNCTION_RAN && ! -e $TEST_EXPORTED_FUNCTION_REUSED_SUDO ]] ||
  fail "the upgrader executed an inherited Bash function with sudo live"
[[ ! -e $TEST_BASH_ENV_RAN && ! -e $TEST_BASH_ENV_REUSED_SUDO ]] ||
  fail "the supported invocation evaluated attacker BASH_ENV"
[[ ! -e $TEST_ROOT_PATH_EXEC ]] ||
  fail "a privileged packaged script resolved a target-home executable"
[[ ! -e $protected_target && ! -e $TEST_USER_REUSED_SUDO && ! -e $TEST_DETACHED_REUSED_SUDO ]] ||
  fail "user or detached tooling reused the Quattro sudo timestamp"
for snapshot_event in SNAPPER_LIST_NO_UPDATE SNAPPER_CREATE_NO_UPDATE SNAPPER_CLEANUP_NO_UPDATE; do
  grep -qx "$snapshot_event" "$trace" ||
    fail "the pre-upgrade snapshot did not complete through sudo --no-update" "missing=$snapshot_event"
done
if grep -q '^SNAPPER_REUSABLE_AUTH$' "$trace"; then
  fail "the pre-upgrade snapshot published reusable sudo authorization"
fi
no_update_count=$(grep -c '^NO_UPDATE_AUTH$' "$trace")
((no_update_count >= 10)) ||
  fail "the real orchestration did not complete many sequential sudo --no-update authorizations" "count=$no_update_count"

first_invalidation=$(grep -n '^INVALIDATE$' "$trace" | head -n1 | cut -d: -f1)
first_snapshot=$(grep -n '^SNAPPER_LIST_NO_UPDATE$' "$trace" | head -n1 | cut -d: -f1)
first_system_mutation=$(grep -n '^ROOT_NO_UPDATE_OPERATION$' "$trace" | head -n1 | cut -d: -f1)
first_no_update=$(grep -n '^NO_UPDATE_AUTH$' "$trace" | head -n1 | cut -d: -f1)
[[ -n $first_invalidation && -n $first_snapshot && -n $first_system_mutation && -n $first_no_update ]] ||
  fail "the real orchestration did not exercise cold invalidation, snapshot, and sudo --no-update"
((first_invalidation < first_no_update)) ||
  fail "a root command was authorized before the old sudo timestamp was invalidated"
((first_invalidation < first_snapshot && first_snapshot < first_system_mutation)) ||
  fail "the trusted snapshot did not run after cold invalidation and before system mutation"
if tail -n "+$((first_invalidation + 1))" "$trace" | grep -qE '^(VALIDATE|KEEPALIVE_OK|USER_SUDO_REUSED)$'; then
  fail "a later upgrade action reopened or reused sudo"
fi

pass "Quattro never publishes a reusable sudo timestamp to startup, user, or detached code"
