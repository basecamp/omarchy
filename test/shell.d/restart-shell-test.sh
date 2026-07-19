#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

wrapper_root="$test_tmp/wrapper-root"
wrapper_bin="$test_tmp/wrapper-bin"
mkdir -p "$wrapper_root/shell" "$wrapper_bin"
touch "$wrapper_root/shell/shell.qml"

cat >"$wrapper_bin/qs" <<'SH'
#!/bin/bash

if [[ ${OMARCHY_TEST_QS_HANG:-0} == 1 ]]; then
  sleep 5
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

restart_root="$test_tmp/restart-root"
restart_bin="$restart_root/bin"
restart_state="$test_tmp/restart-pids"
restart_log="$test_tmp/restart.log"
ipc_log="$test_tmp/ipc.log"
runtime_dir="$test_tmp/runtime"
mkdir -p "$restart_root/shell" "$restart_bin" "$runtime_dir"
touch "$restart_root/shell/shell.qml"
ln -s "$ROOT/bin/omarchy-shell" "$restart_bin/omarchy-shell"
ln -s "$ROOT/bin/omarchy-cmd-missing" "$restart_bin/omarchy-cmd-missing"

cat >"$restart_bin/omarchy-hyprland-launch" <<'SH'
#!/bin/bash

bash -c "$1"
SH

cat >"$restart_bin/qs" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$OMARCHY_TEST_IPC_LOG"

case "$*" in
  *'shell ping')
    grep -Fx '303' "$OMARCHY_TEST_QS_STATE" >/dev/null && printf 'ok\n'
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
    printf 'stopped:%s\n' "$pid" >>"$OMARCHY_TEST_QS_LOG"
    awk 'NR > 1' "$OMARCHY_TEST_QS_STATE" >"$OMARCHY_TEST_QS_STATE.next"
    mv "$OMARCHY_TEST_QS_STATE.next" "$OMARCHY_TEST_QS_STATE"
    ;;
  *' -n -p '*)
    printf '303\n' >"$OMARCHY_TEST_QS_STATE"
    ;;
esac
SH

cat >"$restart_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ ${1:-} == "-j" && ${2:-} == "monitors" ]]; then
  if [[ ${OMARCHY_TEST_SESSION_LOCKED:-0} == 1 ]]; then
    printf '[{"activeWorkspace":{"name":"LOCK"}}]\n'
  else
    printf '[]\n'
  fi
fi
SH

chmod +x "$restart_bin/qs" "$restart_bin/quickshell" "$restart_bin/hyprctl" "$restart_bin/omarchy-hyprland-launch"

printf '101\n202\n' >"$restart_state"

PATH="$restart_bin:$PATH" \
OMARCHY_PATH="$restart_root" \
XDG_RUNTIME_DIR="$runtime_dir" \
OMARCHY_TEST_QS_STATE="$restart_state" \
OMARCHY_TEST_QS_LOG="$restart_log" \
OMARCHY_TEST_IPC_LOG="$ipc_log" \
  timeout 5 "$ROOT/bin/omarchy-restart-shell"

grep -F 'stopped:101' "$restart_log" >/dev/null || fail "restart stops the first matching shell instance"
grep -F 'stopped:202' "$restart_log" >/dev/null || fail "restart stops duplicate matching shell instances"
[[ $(<"$restart_state") == 303 ]] || fail "restart leaves exactly one fresh shell instance"
[[ $(grep -c '^-n -p ' "$restart_log") == 1 ]] || fail "restart launches one fresh shell process"
grep -F 'shell ping' "$ipc_log" >/dev/null || fail "restart waits for fresh shell IPC readiness"
pass "restart replaces duplicate shell instances"

: >"$restart_log"
printf '404\n' >"$restart_state"

locked_error=$(PATH="$restart_bin:$PATH" \
  OMARCHY_PATH="$restart_root" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  OMARCHY_TEST_SESSION_LOCKED=1 \
  OMARCHY_TEST_QS_STATE="$restart_state" \
  OMARCHY_TEST_QS_LOG="$restart_log" \
  OMARCHY_TEST_IPC_LOG="$ipc_log" \
  "$ROOT/bin/omarchy-restart-shell" 2>&1) && fail "restart refuses while the shell lock is active"

[[ $locked_error == "Refusing to restart Omarchy shell while the session is locked." ]] || fail "locked restart explains why it was refused" "$locked_error"
[[ $(<"$restart_state") == 404 ]] || fail "locked restart preserves the running shell"
[[ ! -s $restart_log ]] || fail "locked restart does not stop or launch Quickshell"
pass "restart preserves the shell while its lock is active"
