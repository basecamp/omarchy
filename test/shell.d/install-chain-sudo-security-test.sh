#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

# Prove the privilege boundary in a disposable namespace. The setuid helper
# models sudo's documented per-terminal timestamp: omarchy-pkg-add authenticates
# it, `sudo -k` invalidates it, and the following user-owned mise executable
# only gets root while that credential is still live.
if [[ ${OMARCHY_INSTALL_CHAIN_SECURITY_NS:-} != 1 ]]; then
  outer_uid=$(id -u)
  outer_gid=$(id -g)
  subuid=$(awk -F: -v user="$(id -un)" '$1 == user { print $2; exit }' /etc/subuid)
  subgid=$(awk -F: -v group="$(id -gn)" '$1 == group { print $2; exit }' /etc/subgid)

  if [[ -z $subuid || -z $subgid ]]; then
    pass "no subordinate uid/gid range; skipping install-chain namespace proof"
    exit 0
  fi

  exec unshare --user --mount \
    --map-users "0:$outer_uid:1" --map-users "1:$subuid:65536" \
    --map-groups "0:$outer_gid:1" --map-groups "1:$subgid:65536" \
    env OMARCHY_INSTALL_CHAIN_SECURITY_NS=1 bash "$0"
fi

[[ $(id -u) == 0 ]] || fail "install-chain proof entered its root namespace"

test_tmp=$(mktemp -d)
mount -t tmpfs -o mode=0755 tmpfs "$test_tmp"
chmod 0755 "$test_tmp"
cleanup() {
  umount /usr/bin/omarchy-install-gaming-gpu-lib32 2>/dev/null || true
  umount /usr/bin/omarchy-pkg-add 2>/dev/null || true
  umount /usr/bin/omarchy-pkg-missing 2>/dev/null || true
  umount /usr/bin/pacman 2>/dev/null || true
  umount /usr/bin/curl 2>/dev/null || true
  umount /usr/bin/sudo 2>/dev/null || true
  rm -rf "$test_tmp"/*
  umount "$test_tmp"
  rmdir "$test_tmp"
}
trap cleanup EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
root_dir="$test_tmp/root"
token="$test_tmp/sudo-token"
victim="$root_dir/90-dev-tool.rules"
mkdir -p "$stub_bin" "$test_home" "$root_dir"
chown 1000:1000 "$test_home"
chmod 0700 "$test_home"
chmod 0755 "$stub_bin" "$root_dir"

cat >"$test_tmp/sudo.c" <<'C'
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *token(void) {
  const char *value = getenv("TEST_SUDO_TOKEN");
  if (!value || !*value) exit(125);
  return value;
}

static void log_event(const char *event) {
  const char *path = getenv("TEST_EVENT_LOG");
  int fd;
  if (!path || !*path) return;
  fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
  if (fd < 0) return;
  dprintf(fd, "%s\n", event);
  close(fd);
}

int main(int argc, char **argv) {
  struct stat st;
  int index = 1, no_update = 0;
  if (argc == 2 && strcmp(argv[1], "-h") == 0) {
    puts("usage: sudo [-ABbEHkNnPS] command");
    return 0;
  }
  if (argc == 2 && strcmp(argv[1], "--authenticate-for-test") == 0) {
    int fd = open(token(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return 125;
    close(fd);
    log_event("AUTH");
    return 0;
  }
  if (argc == 2 && strcmp(argv[1], "-k") == 0) {
    if (unlink(token()) < 0 && errno != ENOENT) return 125;
    log_event("REVOKE");
    return 0;
  }
  if (index < argc && strcmp(argv[index], "-N") == 0) {
    no_update = 1;
    index++;
  }
  if (index < argc && strcmp(argv[index], "--") == 0) index++;
  if (no_update) {
    log_event("AUTH_NO_UPDATE");
    if (index < argc && strcmp(argv[index], "/usr/bin/sed") == 0) {
      log_event("PRIVILEGED_CONFIG_NO_UPDATE");
      return 0;
    }
    if (index < argc && strcmp(argv[index], "/usr/bin/pacman") == 0) {
      log_event("PACKAGE_NO_UPDATE");
      return 0;
    }
    if (index < argc && strcmp(argv[index], "/usr/bin/true") == 0) return 0;
    return 125;
  }
  if (index < argc && strcmp(argv[index], "/usr/bin/pacman") == 0 && stat(token(), &st) < 0) {
    int fd = open(token(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return 125;
    close(fd);
    log_event("PACKAGE_REFRESHED");
    return 0;
  }
  if (stat(token(), &st) < 0 || st.st_uid != 0) {
    log_event("DENIED");
    fputs("sudo: a password is required\n", stderr);
    return 1;
  }
  if (argc >= 2 && strcmp(argv[1], "/usr/bin/sed") == 0) {
    log_event("PRIVILEGED_CONFIG");
    return 0;
  }
  log_event("PRIVILEGED_EXEC");
  if (argc < 2 || setuid(0) < 0) return 125;
  execvp(argv[1], &argv[1]);
  return 125;
}
C
gcc -O2 -Wall -Wextra -o "$stub_bin/sudo" "$test_tmp/sudo.c"
chown 0:0 "$stub_bin/sudo"
chmod 4755 "$stub_bin/sudo"
mount --bind "$stub_bin/sudo" /usr/bin/sudo

for installer_source in \
  "$ROOT/bin/omarchy-install-dev-env" \
  "$ROOT/bin/omarchy-install-gaming-geforce-now" \
  "$ROOT/bin/omarchy-install-gaming-battlenet"; do
  grep -Eq 'omarchy_(security|install_security)_(revoke_sudo_timestamp|finish_privileged_phase|prepare_cold_command_scoped_sudo)' "$installer_source" ||
    fail "${installer_source##*/} no longer uses the shared trusted invalidation boundary"
  grep -Eq 'omarchy_security_install_(sudo_cleanup|signal_exit)_traps|trap cleanup' "$installer_source" ||
    fail "${installer_source##*/} no longer invalidates on exit and signals"
done
grep -qF '/usr/bin/sudo -k' "$ROOT/bin/omarchy-security-functions" ||
  fail "shared security functions no longer pin sudo invalidation to /usr/bin"
grep -qF 'omarchy_security_sudo_supports_no_update' "$ROOT/bin/omarchy-install-security-functions" ||
  fail "install security functions no longer enforce command-scoped sudo support"
! grep -Eq '^[[:space:]]*(source|\.)[[:space:]]+.*\.bashrc' "$ROOT/bin/omarchy-install-dev-env" ||
  fail "development installer reintroduced execution of user-owned shell configuration"
pass "installer sources retain fixed-path invalidation and cleanup boundaries"

cat >"$stub_bin/omarchy-pkg-missing" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
[[ ${1:-} == -Q ]]
STUB
chmod 0755 "$stub_bin/omarchy-pkg-missing" "$stub_bin/pacman"
mount --bind "$stub_bin/omarchy-pkg-missing" /usr/bin/omarchy-pkg-missing
mount --bind "$stub_bin/pacman" /usr/bin/pacman

pkg_event_log="$test_tmp/pkg-add-events"
: >"$pkg_event_log"
chown 1000:1000 "$pkg_event_log"
setpriv --reuid 1000 --regid 1000 --clear-groups \
  env HOME="$test_home" TEST_EVENT_LOG="$pkg_event_log" TEST_SUDO_TOKEN="$token" \
    OMARCHY_SUDO_NO_UPDATE=1 "$ROOT/bin/omarchy-pkg-add" audit-package
grep -qxF PACKAGE_NO_UPDATE "$pkg_event_log" ||
  fail "real package helper did not use sudo --no-update"
[[ ! -e $token ]] || fail "real no-update package helper published a timestamp"

mutation_dir="$test_tmp/pkg-add-without-no-update"
mkdir -p "$mutation_dir"
cp "$ROOT/bin/omarchy-security-functions" "$ROOT/bin/omarchy-install-security-functions" "$mutation_dir/"
sed 's|/usr/bin/sudo "${sudo_args\[@\]}" --|/usr/bin/sudo --|' \
  "$ROOT/bin/omarchy-pkg-add" >"$mutation_dir/omarchy-pkg-add"
chmod 0755 "$mutation_dir/omarchy-pkg-add"
: >"$pkg_event_log"
setpriv --reuid 1000 --regid 1000 --clear-groups \
  env HOME="$test_home" TEST_EVENT_LOG="$pkg_event_log" TEST_SUDO_TOKEN="$token" \
    OMARCHY_SUDO_NO_UPDATE=1 "$mutation_dir/omarchy-pkg-add" audit-package
grep -qxF PACKAGE_REFRESHED "$pkg_event_log" ||
  fail "removing command-scoped sudo did not reproduce credential publication"
[[ -e $token ]] || fail "mutated package helper did not leave reusable authorization"
TEST_EVENT_LOG="$pkg_event_log" TEST_SUDO_TOKEN="$token" /usr/bin/sudo -k
pass "removing command-scoped sudo reproduces the install-chain credential leak"

pkg_bash_env="$test_home/pkg-add-bash-env"
pkg_bash_env_marker="$test_home/pkg-add-bash-env-ran"
cat >"$pkg_bash_env" <<'STUB'
: >"$TEST_PKG_BASH_ENV_RAN"
unset BASH_ENV
set -o privileged
set -- audit-package
STUB
chown 1000:1000 "$pkg_bash_env"
: >"$pkg_event_log"
if setpriv --reuid 1000 --regid 1000 --clear-groups \
  env HOME="$test_home" BASH_ENV="$pkg_bash_env" TEST_PKG_BASH_ENV_RAN="$pkg_bash_env_marker" \
    TEST_EVENT_LOG="$pkg_event_log" TEST_SUDO_TOKEN="$token" \
    /usr/bin/bash "$ROOT/bin/omarchy-pkg-add" -p >/dev/null 2>&1; then
  fail "package helper accepted a decoy post-script -p"
fi
[[ -e $pkg_bash_env_marker && ! -s $pkg_event_log && ! -e $token ]] ||
  fail "unsafe package-helper startup reached sudo"
pass "real package helper binds privileged startup and command-scoped sudo"

cat >"$stub_bin/trusted-pkg-add" <<'STUB'
#!/bin/bash
printf 'PACKAGE:%s\n' "$*" >>"$TEST_EVENT_LOG"
[[ ${OMARCHY_SUDO_NO_UPDATE:-0} == 1 ]] || exit 98
if [[ ${PKG_NO_AUTH:-0} != 1 ]]; then
  /usr/bin/sudo -N -- /usr/bin/true
fi
[[ ${PKG_FAIL:-0} != 1 ]] || exit 42
STUB

cat >"$stub_bin/omarchy-pkg-add" <<'STUB'
#!/bin/bash
printf 'UNTRUSTED:path-package-wrapper\n' >>"$TEST_EVENT_LOG"
/usr/bin/sudo --authenticate-for-test
/usr/bin/sudo /usr/bin/install -o root -g root -m 0600 "$HOME/payload" "$TEST_ROOT_VICTIM"
STUB

cat >"$stub_bin/attempt-root" <<'STUB'
#!/bin/bash
tool=$1
printf 'UNTRUSTED:%s\n' "$tool" >>"$TEST_EVENT_LOG"
if [[ ! -e $TEST_ATTACK_DONE ]]; then
  if sudo /usr/bin/install -o root -g root -m 0600 "$HOME/payload" "$TEST_ROOT_VICTIM"; then
    : >"$TEST_ATTACK_DONE"
  fi
fi
if [[ ${TOOL_BLOCK:-} == "$tool" ]]; then
  : >"$TOOL_READY"
  trap 'exit 143' TERM
  trap 'exit 130' INT
  while :; do sleep 0.05; done
fi
[[ ${TOOL_FAIL:-} != "$tool" ]] || exit 43
exit 0
STUB

for tool in mise composer opam; do
  cat >"$stub_bin/$tool" <<STUB
#!/bin/bash
exec "$stub_bin/attempt-root" "$tool"
STUB
done

cat >"$stub_bin/curl" <<'STUB'
#!/bin/bash
cat <<'REMOTE'
printf 'UNTRUSTED:remote-script\n' >>"$TEST_EVENT_LOG"
sudo /usr/bin/install -o root -g root -m 0600 "$HOME/payload" "$TEST_ROOT_VICTIM" >/dev/null 2>&1 || :
[[ ${TOOL_FAIL:-} != remote-script ]] || exit 43
REMOTE
STUB

cat >"$stub_bin/omarchy-launch-browser" <<'STUB'
#!/bin/bash
printf 'BROWSER\n' >>"$TEST_EVENT_LOG"
STUB

chmod 0755 "$stub_bin/"*
chmod 4755 "$stub_bin/sudo"
mount --bind "$stub_bin/trusted-pkg-add" /usr/bin/omarchy-pkg-add

cat >"$test_home/payload" <<'PAYLOAD'
RUN+="/tmp/dev-tool-payload"
PAYLOAD
chown 1000:1000 "$test_home/payload"
chmod 0600 "$test_home/payload"

cat >"$test_home/.bashrc" <<'BASHRC'
printf 'UNTRUSTED:bashrc\n' >>"$TEST_EVENT_LOG"
sudo /usr/bin/install -o root -g root -m 0600 "$HOME/payload" "$TEST_ROOT_VICTIM" >/dev/null 2>&1 || :
BASHRC
chown 1000:1000 "$test_home/.bashrc"

run_dev_env() {
  local branch="$1" expected_status="${2:-0}"
  shift 2 || true
  local event_log="$test_tmp/events-$branch" output="$test_tmp/out-$branch" error="$test_tmp/err-$branch"
  victim="$root_dir/90-$branch.rules"
  : >"$event_log"
  chown 1000:1000 "$event_log"
  rm -f "$victim" "$test_home/attack-done" "$token"
  if [[ ${PRECREATE_TOKEN:-0} == 1 ]]; then
    : >"$token"
    chown 0:0 "$token"
  fi

  set +e
  setpriv --reuid 1000 --regid 1000 --clear-groups \
    env HOME="$test_home" PATH="$stub_bin:/usr/bin:/bin" \
      TEST_ATTACK_DONE="$test_home/attack-done" TEST_EVENT_LOG="$event_log" \
      TEST_ROOT_VICTIM="$victim" TEST_SUDO_TOKEN="$token" "$@" \
      "$ROOT/bin/omarchy-install-dev-env" "$branch" >"$output" 2>"$error"
  status=$?
  set -e

  if ((status != expected_status)); then
    sed -n '1,160p' "$output" >&2
    sed -n '1,160p' "$error" >&2
    fail "$branch development environment returned $status instead of $expected_status"
  fi
  [[ ! -e $victim && ! -e $test_home/attack-done ]] ||
    fail "$branch user-level tooling reused cached root authority"
  [[ ! -e $token ]] || fail "$branch left the modeled sudo timestamp live"

  awk '
    /^REVOKE$/ { live=0; next }
    /^(AUTH|PRIVILEGED_CONFIG|PRIVILEGED_EXEC)$/ { live=1; next }
    /^UNTRUSTED:/ && live { exit 1 }
  ' "$event_log" || fail "$branch crossed from privileged work into untrusted code before revocation"
}

# Invert the original exploit: the package helper authenticates, but the real
# Ruby flow must revoke that credential before the user-owned mise executable.
run_dev_env ruby 0
grep -q '^AUTH_NO_UPDATE$' "$test_tmp/events-ruby" || fail "Ruby package setup did not use command-scoped sudo authentication"
grep -q '^UNTRUSTED:mise$' "$test_tmp/events-ruby" || fail "Ruby legitimate user tooling did not run"
grep -q '^DENIED$' "$test_tmp/events-ruby" || fail "Ruby tool did not receive an authentication-required result"
pass "user-owned Ruby tooling cannot reuse the package install credential"

# Exercise every branch, including the PHP/Laravel/Symfony mix. A malicious
# bashrc would record an event if install_php sourced it.
branches=(node bun deno go php laravel symfony python elixir phoenix rust java zig ocaml dotnet clojure scala)
for branch in "${branches[@]}"; do
  run_dev_env "$branch" 0
done
if grep -q '^UNTRUSTED:bashrc$' "$test_tmp"/events-*; then
  fail "PHP setup executes the user-owned bashrc inside its privileged phase"
fi
grep -q '^UNTRUSTED:composer$' "$test_tmp/events-laravel" || fail "Laravel Composer phase did not run"
grep -q '^AUTH_NO_UPDATE$' "$test_tmp/events-clojure" || fail "Clojure prerequisite did not use command-scoped authentication"
for branch in php laravel symfony; do
  config_authorizations=$(grep -c '^PRIVILEGED_CONFIG_NO_UPDATE$' "$test_tmp/events-$branch")
  (( config_authorizations == 1 )) ||
    fail "$branch did not consolidate PHP configuration into one command-scoped authorization" "count=$config_authorizations"
done
pass "all development branches keep user and downloaded code beyond the sudo boundary"

# A pre-existing timestamp is intentionally revoked by the documented command
# contract, even when the prerequisite helper does not refresh it.
PRECREATE_TOKEN=1 run_dev_env ruby 0 PKG_NO_AUTH=1
grep -q '^UNTRUSTED:mise$' "$test_tmp/events-ruby" || fail "already-installed prerequisite skipped legitimate Ruby flow"
pass "already-installed prerequisites cannot hand a pre-existing timestamp to user tooling"

# Package and tool failures must both run the EXIT revocation path.
run_dev_env ruby 42 PKG_FAIL=1
! grep -q '^UNTRUSTED:' "$test_tmp/events-ruby" || fail "package failure continued into user tooling"
run_dev_env ruby 43 TOOL_FAIL=mise
pass "development package and user-tool failures invalidate cached authorization"

dev_signal_events="$test_tmp/events-dev-signal"
dev_signal_ready="$test_home/dev-signal-ready"
dev_session_pid_file="$test_home/dev-session-pid"
: >"$dev_signal_events"
chown 1000:1000 "$dev_signal_events"
rm -f "$dev_signal_ready" "$dev_session_pid_file" "$token" "$root_dir/90-dev-signal.rules"
(
  exec setsid --fork --wait setpriv --reuid 1000 --regid 1000 --clear-groups \
    env HOME="$test_home" PATH="$stub_bin:/usr/bin:/bin" TEST_EVENT_LOG="$dev_signal_events" \
      TEST_ATTACK_DONE="$test_home/attack-done" TEST_ROOT_VICTIM="$root_dir/90-dev-signal.rules" \
      TEST_SUDO_TOKEN="$token" TOOL_BLOCK=mise TOOL_READY="$dev_signal_ready" \
      SESSION_PID_FILE="$dev_session_pid_file" \
      bash -c 'printf "%s\n" "$$" >"$SESSION_PID_FILE"; exec "$1" ruby' bash \
      "$ROOT/bin/omarchy-install-dev-env"
) >"$test_tmp/out-dev-signal" 2>"$test_tmp/err-dev-signal" &
dev_signal_runner=$!
for _ in {1..300}; do [[ -e $dev_signal_ready && -s $dev_session_pid_file ]] && break; sleep 0.01; done
[[ -e $dev_signal_ready && -s $dev_session_pid_file ]] || fail "development HUP probe never reached mise"
dev_session_pid=$(<"$dev_session_pid_file")
[[ $dev_session_pid =~ ^[0-9]+$ ]] || fail "development HUP probe did not report its session leader"
kill -HUP -- "-$dev_session_pid"
if wait "$dev_signal_runner"; then fail "HUP-interrupted development installer reports success"; fi
[[ ! -e $token && ! -e $root_dir/90-dev-signal.rules ]] || fail "development HUP path retained or reused root authority"
pass "development HUP cancellation invalidates cached authorization"

cat >"$test_tmp/curl-absolute" <<'STUB'
#!/bin/bash
output=
while (($#)); do
  case "$1" in
  --output)
    output=$2
    shift 2
    ;;
  *) shift ;;
  esac
done
[[ -n $output ]]
printf 'INSTALLER_PATH:%s\n' "$output" >>"$TEST_EVENT_LOG"
printf 'DOWNLOAD_MODE:%s:%s:%s\n' "$(stat -c %u "$output")" "$(stat -c %a "$output")" "$(stat -c %h "$output")" >>"$TEST_EVENT_LOG"
[[ ${GFN_CURL_FAIL:-0} != 1 ]] || exit 45
cat >"$output" <<'INSTALLER'
#!/bin/bash
printf 'UNTRUSTED:geforce-installer\n' >>"$TEST_EVENT_LOG"
printf 'INSTALLER_CWD:%s\n' "$PWD" >>"$TEST_EVENT_LOG"
sudo /usr/bin/install -o root -g root -m 0600 "$HOME/payload" "$TEST_ROOT_VICTIM" >/dev/null 2>&1 || :
printf 'INSTALLER_RAN\n' >>"$TEST_EVENT_LOG"
if [[ ${GFN_BLOCK:-0} == 1 ]]; then
  : >"$GFN_READY"
  trap 'exit 143' TERM
  trap 'exit 130' INT
  while :; do sleep 0.05; done
fi
[[ ${GFN_INSTALLER_FAIL:-0} != 1 ]] || exit 44
INSTALLER
STUB
chmod 0755 "$test_tmp/curl-absolute"
mount --bind "$test_tmp/curl-absolute" /usr/bin/curl

run_gfn() {
  local label="$1" expected_status="$2"
  shift 2
  local event_log="$test_tmp/events-gfn-$label" output="$test_tmp/out-gfn-$label" error="$test_tmp/err-gfn-$label"
  victim="$root_dir/90-gfn-$label.rules"
  : >"$event_log"
  chown 1000:1000 "$event_log"
  rm -f "$victim" "$test_home/attack-done" "$token"
  if [[ ${PRECREATE_TOKEN:-0} == 1 ]]; then
    : >"$token"
    chown 0:0 "$token"
  fi

  set +e
  setpriv --reuid 1000 --regid 1000 --clear-groups \
    env HOME="$test_home" PATH="$stub_bin:/usr/bin:/bin" \
      TEST_ATTACK_DONE="$test_home/attack-done" TEST_EVENT_LOG="$event_log" \
      TEST_ROOT_VICTIM="$victim" TEST_SUDO_TOKEN="$token" "$@" \
      "$ROOT/bin/omarchy-install-gaming-geforce-now" >"$output" 2>"$error"
  status=$?
  set -e

  if ((status != expected_status)); then
    sed -n '1,160p' "$output" >&2
    sed -n '1,160p' "$error" >&2
    fail "GeForce $label returned $status instead of $expected_status"
  fi
  [[ ! -e $victim && ! -e $test_home/attack-done && ! -e $token ]] ||
    fail "GeForce $label retained or reused cached root authority"
  installer_path=$(awk -F: '/^INSTALLER_PATH:/ { sub(/^INSTALLER_PATH:/, ""); print; exit }' "$event_log")
  [[ -z $installer_path || ! -e $installer_path ]] || fail "GeForce $label left its downloaded executable behind"
}

run_gfn success 0
grep -q '^AUTH_NO_UPDATE$' "$test_tmp/events-gfn-success" || fail "GeForce package setup did not use command-scoped authentication"
grep -q '^UNTRUSTED:geforce-installer$' "$test_tmp/events-gfn-success" || fail "GeForce downloaded installer did not run"
grep -q '^DENIED$' "$test_tmp/events-gfn-success" || fail "GeForce installer did not receive an authentication-required result"
grep -q '^DOWNLOAD_MODE:1000:600:1$' "$test_tmp/events-gfn-success" || fail "GeForce download was not private from first creation"
grep -q '^INSTALLER_CWD:/tmp$' "$test_tmp/events-gfn-success" || fail "GeForce installer no longer runs from /tmp"
grep -q '^BROWSER$' "$test_tmp/events-gfn-success" || fail "GeForce success no longer launches the browser"
pass "downloaded GeForce installer cannot reuse the Flatpak package credential"

PRECREATE_TOKEN=1 run_gfn installed-prerequisite 0 PKG_NO_AUTH=1
run_gfn package-failure 42 PKG_FAIL=1
run_gfn download-failure 45 GFN_CURL_FAIL=1
run_gfn installer-failure 44 GFN_INSTALLER_FAIL=1
pass "GeForce prerequisite, package, download, and installer outcomes revoke and clean up"

# Signal the whole terminal-style process group so the foreground downloaded
# child and its waiting shell are interrupted together.
signal_events="$test_tmp/events-gfn-signal"
signal_ready="$test_home/gfn-signal-ready"
session_pid_file="$test_home/gfn-session-pid"
: >"$signal_events"
chown 1000:1000 "$signal_events"
rm -f "$signal_ready" "$session_pid_file" "$token" "$root_dir/90-gfn-signal.rules"
(
  exec setsid --fork --wait setpriv --reuid 1000 --regid 1000 --clear-groups \
    env HOME="$test_home" PATH="$stub_bin:/usr/bin:/bin" TEST_EVENT_LOG="$signal_events" \
      TEST_ATTACK_DONE="$test_home/attack-done" TEST_ROOT_VICTIM="$root_dir/90-gfn-signal.rules" \
      TEST_SUDO_TOKEN="$token" GFN_BLOCK=1 GFN_READY="$signal_ready" SESSION_PID_FILE="$session_pid_file" \
      bash -c 'printf "%s\n" "$$" >"$SESSION_PID_FILE"; exec "$1"' bash \
      "$ROOT/bin/omarchy-install-gaming-geforce-now"
) >"$test_tmp/out-gfn-signal" 2>"$test_tmp/err-gfn-signal" &
signal_runner=$!
for _ in {1..300}; do [[ -e $signal_ready && -s $session_pid_file ]] && break; sleep 0.01; done
[[ -e $signal_ready && -s $session_pid_file ]] || fail "GeForce signal probe never reached the downloaded installer"
session_pid=$(<"$session_pid_file")
[[ $session_pid =~ ^[0-9]+$ ]] || fail "GeForce signal probe did not report its session leader"
kill -TERM -- "-$session_pid"
if wait "$signal_runner"; then fail "TERM-interrupted GeForce installer reports success"; fi
[[ ! -e $token && ! -e $root_dir/90-gfn-signal.rules ]] || fail "GeForce signal path retained or reused root authority"
signal_installer=$(awk -F: '/^INSTALLER_PATH:/ { sub(/^INSTALLER_PATH:/, ""); print; exit }' "$signal_events")
[[ -n $signal_installer && ! -e $signal_installer ]] || fail "GeForce signal path left its executable behind"
pass "GeForce TERM cancellation invalidates sudo and removes the downloaded executable"

cat >"$stub_bin/battlenet-package-helper" <<'STUB'
#!/bin/bash
printf 'PACKAGE:%s:%s\n' "${0##*/}" "$*" >>"$TEST_EVENT_LOG"
[[ ${OMARCHY_SUDO_NO_UPDATE:-0} == 1 ]] || exit 98
if [[ ${PKG_NO_AUTH:-0} != 1 ]]; then
  /usr/bin/sudo -N -- /usr/bin/true
fi
if [[ ${BATTLENET_PKG_BLOCK:-0} == 1 ]]; then
  : >"$BATTLENET_READY"
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  while :; do sleep 0.05; done
fi
[[ ${PKG_FAIL:-0} != 1 ]] || exit 42
STUB
chmod 0755 "$stub_bin/battlenet-package-helper"
cat >"$stub_bin/battlenet-path-wrapper" <<'STUB'
#!/bin/bash
printf 'UNTRUSTED:path-package-wrapper\n' >>"$TEST_EVENT_LOG"
/usr/bin/sudo --authenticate-for-test
/usr/bin/sudo /usr/bin/install -o root -g root -m 0600 "$HOME/payload" "$TEST_ROOT_VICTIM"
STUB
chmod 0755 "$stub_bin/battlenet-path-wrapper"
ln -sf battlenet-path-wrapper "$stub_bin/omarchy-pkg-add"
ln -sf battlenet-path-wrapper "$stub_bin/omarchy-install-gaming-gpu-lib32"
umount /usr/bin/omarchy-pkg-add
mount --bind "$stub_bin/battlenet-package-helper" /usr/bin/omarchy-pkg-add
mount --bind "$stub_bin/battlenet-package-helper" /usr/bin/omarchy-install-gaming-gpu-lib32

cat >"$stub_bin/curl" <<'STUB'
#!/bin/bash
output=
while (($#)); do
  case "$1" in
    --output)
      output=$2
      shift 2
      ;;
    *) shift ;;
  esac
done
printf 'UNTRUSTED:battlenet-download\n' >>"$TEST_EVENT_LOG"
[[ ${BATTLENET_CURL_FAIL:-0} != 1 ]] || exit 45
[[ -n $output ]]
printf 'harmless Battle.net fixture\n' >"$output"
STUB

cat >"$stub_bin/umu-run" <<'STUB'
#!/bin/bash
printf 'UNTRUSTED:umu-run\n' >>"$TEST_EVENT_LOG"
if sudo /usr/bin/install -o root -g root -m 0600 "$HOME/payload" "$TEST_ROOT_VICTIM"; then
  : >"$TEST_ATTACK_DONE"
fi
: >"$BATTLENET_UMU_RAN"
STUB
chmod 0755 "$stub_bin/curl" "$stub_bin/umu-run"

run_battlenet() {
  local label="$1" expected_status="$2"
  shift 2
  local event_log="$test_tmp/events-battlenet-$label" output="$test_tmp/out-battlenet-$label" error="$test_tmp/err-battlenet-$label"
  local umu_ran="$test_home/battlenet-umu-$label"
  victim="$root_dir/90-battlenet-$label.rules"
  : >"$event_log"
  chown 1000:1000 "$event_log"
  rm -rf "$test_home/Games/battlenet"
  rm -f "$victim" "$test_home/attack-done" "$token" "$umu_ran"
  if [[ ${PRECREATE_TOKEN:-0} == 1 ]]; then
    : >"$token"
    chown 0:0 "$token"
  fi

  set +e
  setpriv --reuid 1000 --regid 1000 --clear-groups \
    env HOME="$test_home" PATH="$stub_bin:/usr/bin:/bin" OMARCHY_PATH="$ROOT" \
      TEST_ATTACK_DONE="$test_home/attack-done" TEST_EVENT_LOG="$event_log" \
      TEST_ROOT_VICTIM="$victim" TEST_SUDO_TOKEN="$token" BATTLENET_UMU_RAN="$umu_ran" "$@" \
      "$ROOT/bin/omarchy-install-gaming-battlenet" >"$output" 2>"$error"
  status=$?
  set -e

  if ((status != expected_status)); then
    sed -n '1,160p' "$output" >&2
    sed -n '1,160p' "$error" >&2
    fail "Battle.net $label returned $status instead of $expected_status"
  fi
  if ((expected_status == 0)); then
    for _ in {1..300}; do [[ -e $umu_ran ]] && break; sleep 0.01; done
    [[ -e $umu_ran ]] || fail "Battle.net $label detached umu-run did not execute"
  fi
  [[ ! -e $victim && ! -e $test_home/attack-done && ! -e $token ]] ||
    fail "Battle.net $label retained or reused cached root authority"

  awk '
    /^REVOKE$/ { live=0; next }
    /^(AUTH|PRIVILEGED_CONFIG|PRIVILEGED_EXEC)$/ { live=1; next }
    /^UNTRUSTED:/ && live { exit 1 }
  ' "$event_log" || fail "Battle.net $label crossed into downloaded code before revocation"
}

run_battlenet success 0
grep -q '^AUTH_NO_UPDATE$' "$test_tmp/events-battlenet-success" || fail "Battle.net package setup did not use command-scoped authentication"
grep -q '^UNTRUSTED:umu-run$' "$test_tmp/events-battlenet-success" || fail "Battle.net detached umu-run did not run"
grep -q '^DENIED$' "$test_tmp/events-battlenet-success" || fail "Battle.net umu-run did not receive an authentication-required result"
pass "detached Battle.net vendor execution cannot reuse package-helper authorization"

PRECREATE_TOKEN=1 run_battlenet installed-prerequisite 0 PKG_NO_AUTH=1
run_battlenet package-failure 42 PKG_FAIL=1
run_battlenet download-failure 45 BATTLENET_CURL_FAIL=1
pass "Battle.net prerequisite, package, and download outcomes revoke sudo"

battlenet_signal_events="$test_tmp/events-battlenet-signal"
battlenet_signal_ready="$test_home/battlenet-signal-ready"
battlenet_session_pid_file="$test_home/battlenet-session-pid"
: >"$battlenet_signal_events"
chown 1000:1000 "$battlenet_signal_events"
rm -f "$battlenet_signal_ready" "$battlenet_session_pid_file" "$token" "$root_dir/90-battlenet-signal.rules"
(
  exec setsid --fork --wait setpriv --reuid 1000 --regid 1000 --clear-groups \
    env HOME="$test_home" PATH="$stub_bin:/usr/bin:/bin" OMARCHY_PATH="$ROOT" \
      TEST_EVENT_LOG="$battlenet_signal_events" TEST_ATTACK_DONE="$test_home/attack-done" \
      TEST_ROOT_VICTIM="$root_dir/90-battlenet-signal.rules" TEST_SUDO_TOKEN="$token" \
      BATTLENET_PKG_BLOCK=1 BATTLENET_READY="$battlenet_signal_ready" \
      SESSION_PID_FILE="$battlenet_session_pid_file" \
      bash -c 'printf "%s\n" "$$" >"$SESSION_PID_FILE"; exec "$1"' bash \
      "$ROOT/bin/omarchy-install-gaming-battlenet"
) >"$test_tmp/out-battlenet-signal" 2>"$test_tmp/err-battlenet-signal" &
battlenet_signal_runner=$!
for _ in {1..300}; do [[ -e $battlenet_signal_ready && -s $battlenet_session_pid_file ]] && break; sleep 0.01; done
[[ -e $battlenet_signal_ready && -s $battlenet_session_pid_file ]] || fail "Battle.net signal probe never reached its package helper"
battlenet_session_pid=$(<"$battlenet_session_pid_file")
[[ $battlenet_session_pid =~ ^[0-9]+$ ]] || fail "Battle.net signal probe did not report its session leader"
kill -TERM -- "-$battlenet_session_pid"
if wait "$battlenet_signal_runner"; then fail "TERM-interrupted Battle.net installer reports success"; fi
[[ ! -e $token && ! -e $root_dir/90-battlenet-signal.rules ]] || fail "Battle.net signal path retained or reused root authority"
pass "Battle.net TERM cancellation invalidates cached authorization"
