#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
restart_pid_one=""
restart_pid_two=""

cleanup() {
  [[ -n $restart_pid_one ]] && kill "$restart_pid_one" 2>/dev/null || true
  [[ -n $restart_pid_two ]] && kill "$restart_pid_two" 2>/dev/null || true
  [[ -n $restart_pid_one ]] && wait "$restart_pid_one" 2>/dev/null || true
  [[ -n $restart_pid_two ]] && wait "$restart_pid_two" 2>/dev/null || true
  rm -rf "$test_tmp"
}
trap cleanup EXIT

wrapper_root="$test_tmp/wrapper-root"
wrapper_bin="$test_tmp/wrapper-bin"
mkdir -p "$wrapper_root/shell" "$wrapper_bin"
touch "$wrapper_root/shell/shell.qml"

cat >"$wrapper_bin/qs" <<'SH'
#!/bin/bash

[[ -n ${OMARCHY_TEST_QS_ARGS:-} ]] && printf '%s\n' "$*" >"$OMARCHY_TEST_QS_ARGS"

if [[ ${OMARCHY_TEST_QS_HANG:-0} == 1 ]]; then
  sleep 5
elif [[ ${OMARCHY_TEST_QS_STARTING:-0} == 1 ]]; then
  printf 'Not ready to accept queries yet.\n'
else
  printf 'ok\n'
fi
SH
chmod +x "$wrapper_bin/qs"

wrapper_error=$(PATH="$wrapper_bin:$PATH" \
  OMARCHY_PATH="$wrapper_root" \
  OMARCHY_SHELL_IPC_TIMEOUT=0.1s \
  OMARCHY_TEST_QS_HANG=1 \
  "$ROOT/bin/omarchy-shell" shell ping 2>&1) && fail "hung shell IPC returns a failure"
[[ $wrapper_error == "omarchy-shell is not responding" ]] || fail "hung shell IPC reports that the shell is unresponsive" "$wrapper_error"
pass "shell IPC calls time out when Quickshell is unresponsive"

# A starting shell answers on stdout and exits 0, so a ping reads it as up.
wrapper_error=$(PATH="$wrapper_bin:$PATH" \
  OMARCHY_PATH="$wrapper_root" \
  OMARCHY_TEST_QS_STARTING=1 \
  "$ROOT/bin/omarchy-shell" shell ping 2>&1) && fail "a starting shell answers IPC calls with a failure"
[[ $wrapper_error == "omarchy-shell is not ready" ]] || fail "a starting shell reports that it is not ready" "$wrapper_error"
pass "shell IPC calls fail while Quickshell is still starting"

PATH="$wrapper_bin:$PATH" \
OMARCHY_PATH="$wrapper_root" \
OMARCHY_TEST_QS_STARTING=1 \
  "$ROOT/bin/omarchy-shell" -q shell ping >/dev/null 2>&1 ||
  fail "quiet best-effort IPC calls tolerate a starting shell"
pass "quiet best-effort IPC calls tolerate a starting shell"

wrapper_args="$test_tmp/wrapper-args"
PATH="$wrapper_bin:$PATH" \
OMARCHY_PATH="$wrapper_root" \
OMARCHY_TEST_QS_ARGS="$wrapper_args" \
  "$ROOT/bin/omarchy-shell" shell ping >/dev/null

grep -F -- 'ipc -n -p' "$wrapper_args" >/dev/null || fail "shell IPC targets the newest live Quickshell instance"
pass "shell IPC targets the newest live Quickshell instance"

restart_root="$test_tmp/restart-root"
restart_bin="$restart_root/bin"
restart_state="$test_tmp/restart-pids"
restart_log="$test_tmp/restart.log"
restart_env_log="$test_tmp/restart-env.log"
dispatch_log="$test_tmp/dispatch.log"
ipc_log="$test_tmp/ipc.log"
runtime_dir="$test_tmp/runtime"
mkdir -p "$restart_root/shell" "$restart_bin" "$runtime_dir"
touch "$restart_root/shell/shell.qml"
ln -s "$ROOT/bin/omarchy-shell" "$restart_bin/omarchy-shell"
ln -s "$ROOT/bin/omarchy-launch-shell" "$restart_bin/omarchy-launch-shell"
ln -s "$ROOT/bin/omarchy-cmd-missing" "$restart_bin/omarchy-cmd-missing"
ln -s "$ROOT/bin/omarchy-hyprland-session-locked" "$restart_bin/omarchy-hyprland-session-locked"

cat >"$restart_bin/qs" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$OMARCHY_TEST_IPC_LOG"

case "$*" in
  *'shell ping')
    [[ $* == *"-p $OMARCHY_TEST_SESSION_PATH/shell"* ]] &&
      grep -Fx '303' "$OMARCHY_TEST_QS_STATE" >/dev/null &&
      printf 'ok\n'
    ;;
  *'lock lock')
    touch "$OMARCHY_TEST_QS_STATE.locked"
    printf 'ok\n'
    ;;
  *'lock status')
    if [[ -f $OMARCHY_TEST_QS_STATE.locked ]]; then
      printf '{"secure": true, "requested": true}\n'
    else
      printf '{"secure": false, "requested": false}\n'
    fi
    ;;
esac
SH

cat >"$restart_bin/quickshell" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$OMARCHY_TEST_QS_LOG"

case " $* " in
  *' kill -p '*)
    pid=$(head -n 1 "$OMARCHY_TEST_QS_STATE")
    [[ $pid =~ ^[0-9]+$ ]] || exit 1

    # Stock Quickshell 0.3.0 returns before the instance exits. A second kill
    # during that shutdown is the update-time crash reproduced by this test.
    if [[ -f $OMARCHY_TEST_QS_STATE.pending.$pid ]]; then
      touch "$OMARCHY_TEST_QS_STATE.crashed"
      exit 134
    fi

    touch "$OMARCHY_TEST_QS_STATE.pending.$pid"
    (sleep 0.1; kill "$pid" 2>/dev/null) &
    ;;
  *' -n -p '*)
    printf '%s\n' "${OMARCHY_TEST_TRANSIENT_ENV-unset}" >"$OMARCHY_TEST_QS_ENV_LOG"

    if [[ ${OMARCHY_TEST_QS_LONG_RUNNING:-0} == 1 ]]; then
      stop_shell() {
        awk -v pid="$PPID" '$0 != pid' "$OMARCHY_TEST_QS_STATE" >"$OMARCHY_TEST_QS_STATE.$$.next"
        mv "$OMARCHY_TEST_QS_STATE.$$.next" "$OMARCHY_TEST_QS_STATE"
        exit 0
      }
      trap stop_shell TERM INT
      while true; do sleep 1; done
    fi

    printf '303\n' >"$OMARCHY_TEST_QS_STATE"
    ;;
esac
SH

cat >"$restart_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ ${1:-} == "-j" && ${2:-} == "monitors" ]]; then
  # Hyprland reports an active session lock as a reason the monitor cannot hand
  # a client the whole screen, not as a workspace.
  if [[ ${OMARCHY_TEST_SESSION_LOCKED:-0} == 1 ]]; then
    printf '[{"name":"eDP-1","solitaryBlockedBy":["WINDOWED","LOCK","CANDIDATE"]}]\n'
  else
    printf '[{"name":"eDP-1","solitaryBlockedBy":["WINDOWED","CANDIDATE"]}]\n'
  fi
elif [[ ${1:-} == "dispatch" && ${2:-} == hl.dsp.exec_cmd* ]]; then
  printf '%s\n' "${2:-}" >>"$OMARCHY_TEST_DISPATCH_LOG"
  OMARCHY_PATH="$OMARCHY_TEST_SESSION_PATH" \
    env -u OMARCHY_TEST_TRANSIENT_ENV -u OMARCHY_TEST_QS_LONG_RUNNING omarchy-launch-shell
  printf 'ok\n'
elif [[ ${1:-} == "dispatch" ]]; then
  exit 1
fi
SH

# Keep the test hermetic where journald has no usable stream socket.
cat >"$restart_bin/systemd-cat" <<'SH'
#!/bin/bash

while (( $# > 0 )); do
  [[ $1 == "--" ]] && { shift; break; }
  shift
done
exec "$@"
SH

cat >"$restart_bin/systemctl" <<'SH'
#!/bin/bash

if [[ ${1:-} == "--user" && ${2:-} == "show-environment" ]]; then
  printf 'OMARCHY_PATH=%s\n' "$OMARCHY_TEST_SESSION_PATH"
elif [[ ${1:-} == "--user" && ${2:-} == "try-restart" ]]; then
  exit 0
else
  exit 1
fi
SH

chmod +x "$restart_bin/qs" "$restart_bin/quickshell" "$restart_bin/hyprctl" "$restart_bin/systemd-cat" "$restart_bin/systemctl"

PATH="$restart_bin:$PATH" \
OMARCHY_PATH="$restart_root" \
OMARCHY_TEST_QS_LONG_RUNNING=1 \
OMARCHY_TEST_QS_STATE="$restart_state" \
OMARCHY_TEST_QS_LOG="$restart_log" \
OMARCHY_TEST_QS_ENV_LOG="$restart_env_log" \
  /bin/bash "$restart_bin/omarchy-launch-shell" &
restart_pid_one=$!
PATH="$restart_bin:$PATH" \
OMARCHY_PATH="$restart_root" \
OMARCHY_TEST_QS_LONG_RUNNING=1 \
OMARCHY_TEST_QS_STATE="$restart_state" \
OMARCHY_TEST_QS_LOG="$restart_log" \
OMARCHY_TEST_QS_ENV_LOG="$restart_env_log" \
  /bin/bash "$restart_bin/omarchy-launch-shell" &
restart_pid_two=$!
printf '%s\n%s\n' "$restart_pid_one" "$restart_pid_two" >"$restart_state"
sleep 0.1
: >"$restart_log"

caller_root="$test_tmp/caller-root"
mkdir -p "$caller_root/shell"
touch "$caller_root/shell/shell.qml"

PATH="$restart_bin:$PATH" \
OMARCHY_PATH="$caller_root" \
XDG_RUNTIME_DIR="$runtime_dir" \
OMARCHY_TEST_QS_STATE="$restart_state" \
OMARCHY_TEST_QS_LOG="$restart_log" \
OMARCHY_TEST_QS_ENV_LOG="$restart_env_log" \
OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" \
OMARCHY_TEST_IPC_LOG="$ipc_log" \
OMARCHY_TEST_SESSION_PATH="$restart_root" \
OMARCHY_TEST_TRANSIENT_ENV=leaked \
  timeout 5 "$ROOT/bin/omarchy-restart-shell"

if kill -0 "$restart_pid_one" 2>/dev/null; then
  fail "restart stops the first matching shell instance"
fi
if kill -0 "$restart_pid_two" 2>/dev/null; then
  fail "restart stops duplicate matching shell instances"
fi
wait "$restart_pid_one" 2>/dev/null || true
wait "$restart_pid_two" 2>/dev/null || true
restart_pid_one=""
restart_pid_two=""
[[ $(<"$restart_state") == 303 ]] || fail "restart leaves exactly one fresh shell instance"
[[ $(grep -c '^-n -p ' "$restart_log") == 1 ]] || fail "restart launches one fresh shell process"
[[ ! -f $restart_state.crashed ]] || fail "restart does not send a second stop request while stock Quickshell is shutting down"
if grep -F "kill -p $restart_root/shell --any-display" "$restart_log" >/dev/null; then
  fail "restart does not depend on Quickshell's version-specific kill command"
fi
[[ $(<"$restart_env_log") == "unset" ]] || fail "restart uses the Hyprland session environment for the fresh shell"
grep -F 'hl.dsp.exec_cmd("omarchy-launch-shell")' "$dispatch_log" >/dev/null || fail "restart launches the fresh shell through Hyprland"
grep -F "ipc -n -p $restart_root/shell call -- shell ping" "$ipc_log" >/dev/null || fail "restart checks readiness in the session checkout"
pass "restart replaces duplicate shell instances from the session checkout"

: >"$restart_log"
printf '303\n' >"$restart_state"
touch "$restart_state.locked"

locked_error=$(PATH="$restart_bin:$PATH" \
  OMARCHY_PATH="$restart_root" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  OMARCHY_TEST_SESSION_LOCKED=1 \
  OMARCHY_TEST_QS_STATE="$restart_state" \
  OMARCHY_TEST_QS_LOG="$restart_log" \
  OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" \
  OMARCHY_TEST_IPC_LOG="$ipc_log" \
  OMARCHY_TEST_SESSION_PATH="$restart_root" \
  "$ROOT/bin/omarchy-restart-shell" 2>&1) && fail "restart refuses while the shell lock is active"

[[ $locked_error == "Refusing to restart Omarchy shell while the session is locked." ]] || fail "locked restart explains why it was refused" "$locked_error"
[[ $(<"$restart_state") == 303 ]] || fail "locked restart preserves the running shell"
[[ ! -s $restart_log ]] || fail "locked restart does not stop or launch Quickshell"
pass "restart preserves the shell while its lock is active"

# A LOCK session without an active locker — dead shell or a crash-handler
# relaunch holding no lock — is the failsafe: restart must proceed,
# re-acquire the session lock, and wait for it to report secure.
PATH="$restart_bin:$PATH" \
OMARCHY_PATH="$restart_root" \
OMARCHY_TEST_QS_LONG_RUNNING=1 \
OMARCHY_TEST_QS_STATE="$restart_state" \
OMARCHY_TEST_QS_LOG="$restart_log" \
OMARCHY_TEST_QS_ENV_LOG="$restart_env_log" \
  /bin/bash "$restart_bin/omarchy-launch-shell" &
restart_pid_one=$!
printf '%s\n' "$restart_pid_one" >"$restart_state"
sleep 0.1
rm -f "$restart_state.locked"
: >"$restart_log"
: >"$ipc_log"

PATH="$restart_bin:$PATH" \
OMARCHY_PATH="$restart_root" \
XDG_RUNTIME_DIR="$runtime_dir" \
OMARCHY_TEST_SESSION_LOCKED=1 \
OMARCHY_TEST_QS_STATE="$restart_state" \
OMARCHY_TEST_QS_LOG="$restart_log" \
OMARCHY_TEST_QS_ENV_LOG="$restart_env_log" \
OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" \
OMARCHY_TEST_IPC_LOG="$ipc_log" \
OMARCHY_TEST_SESSION_PATH="$restart_root" \
  timeout 5 "$ROOT/bin/omarchy-restart-shell" || fail "locked restart recovers when the lock client is dead"

if kill -0 "$restart_pid_one" 2>/dev/null; then
  fail "dead-lock recovery stops the stale shell instance"
fi
wait "$restart_pid_one" 2>/dev/null || true
restart_pid_one=""
[[ $(<"$restart_state") == 303 ]] || fail "dead-lock recovery leaves one fresh shell instance"
grep -F "ipc -n -p $restart_root/shell call -- lock lock" "$ipc_log" >/dev/null || fail "dead-lock recovery re-acquires the session lock"
grep -F "ipc -n -p $restart_root/shell call -- lock status" "$ipc_log" >/dev/null || fail "dead-lock recovery waits for the lock to become secure"
pass "restart recovers a locked session whose lock client died"
