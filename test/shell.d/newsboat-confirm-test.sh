#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
sandbox_runtime="$test_tmp/sandbox-runtime"
trap 'if [[ -f ${bridge_pid_file:-} ]]; then kill "$(<"$bridge_pid_file")" 2>/dev/null || true; fi; chmod 700 "$sandbox_runtime" 2>/dev/null || true; rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
runtime_dir="$test_tmp/runtime"
agent_runtime="$test_tmp/agent-runtime"
launch_log="$test_tmp/launch"
descriptor_log="$test_tmp/descriptor"
bridge_pid_file="$test_tmp/bridge-pid"
bridge_fifo="$test_tmp/bridge-input"
real_ps=$(command -v ps)
mkdir -p "$mock_bin" "$runtime_dir" "$sandbox_runtime"
mkfifo "$bridge_fifo"

export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT"
export XDG_RUNTIME_DIR="$runtime_dir"
export NEWSBOAT_CONFIRM_STATE_DIR="$runtime_dir/confirmations"
export NEWSBOAT_CONFIRM_TIMEOUT_SECONDS=2
export CONFIRM_TEST_LAUNCH_LOG="$launch_log"
export CONFIRM_TEST_DESCRIPTOR_LOG="$descriptor_log"
export CONFIRM_TEST_BRIDGE_PID_FILE="$bridge_pid_file"
export CONFIRM_TEST_BRIDGE_FIFO="$bridge_fifo"
export CONFIRM_TEST_REAL_PS="$real_ps"

cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$CONFIRM_TEST_LAUNCH_LOG"
if [[ ${1:-} == "-q" ]]; then
  shift
fi
case ${1:-}:${2:-} in
  shell:launchNewsboatConfirmation)
    if [[ ${CONFIRM_TEST_SHELL_LAUNCH_STATUS:-0} != 0 ]]; then
      exit "$CONFIRM_TEST_SHELL_LAUNCH_STATUS"
    elif [[ ${CONFIRM_TEST_SHELL_LAUNCH_RESULT:-ok} != "ok" ]]; then
      echo "$CONFIRM_TEST_SHELL_LAUNCH_RESULT"
      exit 0
    elif [[ ${CONFIRM_TEST_SKIP_CHILD:-false} != "true" ]]; then
      if [[ ${CONFIRM_TEST_HANG_CHILD:-false} == "true" ]]; then
        exec 9<>"$CONFIRM_TEST_BRIDGE_FIFO"
        "$OMARCHY_PATH/bin/omarchy-newsboat-confirm" --bridge "$3" "$4" <&9 >>"$CONFIRM_TEST_DESCRIPTOR_LOG" &
        echo "$!" >"$CONFIRM_TEST_BRIDGE_PID_FILE"
        exec 9>&-
      else
        printf '%s\n' "${CONFIRM_TEST_DECISION:-approved}" | \
          "$OMARCHY_PATH/bin/omarchy-newsboat-confirm" --bridge "$3" "$4" >>"$CONFIRM_TEST_DESCRIPTOR_LOG" &
      fi
    fi
    echo ok
    ;;
  shell:newsboatConfirmationStatus) echo "${CONFIRM_TEST_WINDOW_STATUS:-active}" ;;
  shell:cancelNewsboatConfirmation)
    if [[ -f $CONFIRM_TEST_BRIDGE_PID_FILE ]]; then
      kill "$(<"$CONFIRM_TEST_BRIDGE_PID_FILE")" 2>/dev/null || true
    fi
    echo ok
    ;;
  *) exit 64 ;;
esac
SH

cat >"$mock_bin/ps" <<'SH'
#!/bin/bash
if [[ ${CONFIRM_TEST_REAL_PARENT:-false} == "true" ]]; then
  exec "$CONFIRM_TEST_REAL_PS" "$@"
elif [[ ${1:-} == "-o" && ${2:-} == "comm=" && ${3:-} == "-p" ]]; then
  echo quickshell
else
  exec "$CONFIRM_TEST_REAL_PS" "$@"
fi
SH

cat >"$mock_bin/mv" <<'SH'
#!/bin/bash
destination=""
for argument in "$@"; do destination="$argument"; done
if [[ -n ${CONFIRM_TEST_MV_FAIL_PREFIX:-} && $destination == "$CONFIRM_TEST_MV_FAIL_PREFIX"* ]]; then
  exit 73
fi
exec /bin/mv "$@"
SH

chmod +x "$mock_bin/omarchy-shell" "$mock_bin/ps" "$mock_bin/mv"

file_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

"$ROOT/bin/omarchy-newsboat-confirm" triage 44 3
grep -Eq "^shell launchNewsboatConfirmation $NEWSBOAT_CONFIRM_STATE_DIR [A-Za-z0-9_-]+$" "$launch_log" || fail "Newsboat confirmation does not give Shell its private state directory"
grep -Fxq '{"kind":"triage","read":44,"leave":3}' "$descriptor_log" || fail "Newsboat triage confirmation omits the exact effect"
[[ -z $(find "$NEWSBOAT_CONFIRM_STATE_DIR" -type f -print -quit) ]] || fail "an approved Newsboat confirmation leaves reusable state"
pass "Newsboat requires an exact out-of-band triage approval"

unset NEWSBOAT_CONFIRM_STATE_DIR
export NEWSBOAT_CONFIRM_RUNTIME_DIR="$agent_runtime"
export XDG_RUNTIME_DIR="$sandbox_runtime"
chmod 500 "$sandbox_runtime"
state_root="$agent_runtime/omarchy-newsboat-$UID"
mkdir -p "$state_root"
chmod 755 "$state_root"
: >"$descriptor_log"
"$ROOT/bin/omarchy-newsboat-confirm" triage 2 1
confirm_state_dir="$agent_runtime/omarchy-newsboat-$UID/confirmations"
[[ -d $confirm_state_dir ]] || fail "Newsboat confirmation relies on the agent's read-only XDG runtime"
[[ $(file_mode "$state_root") == 700 ]] || fail "Newsboat confirmation leaves its shared runtime visible to other users"
[[ -z $(find "$confirm_state_dir" -type f -print -quit) ]] || fail "sandbox-compatible confirmation leaves reusable state"
[[ -z $(find "$sandbox_runtime" -mindepth 1 -print -quit) ]] || fail "Newsboat confirmation writes inside the agent's XDG runtime"
pass "Newsboat confirmation works when the agent's XDG runtime is read-only"
chmod 700 "$sandbox_runtime"
unset NEWSBOAT_CONFIRM_RUNTIME_DIR
export XDG_RUNTIME_DIR="$runtime_dir"
export NEWSBOAT_CONFIRM_STATE_DIR="$runtime_dir/confirmations"

: >"$descriptor_log"
export CONFIRM_TEST_DECISION=declined
set +e
"$ROOT/bin/omarchy-newsboat-confirm" scout 4 >"$test_tmp/declined-output" 2>"$test_tmp/declined-error"
declined_status=$?
set -e
(( declined_status == 1 )) || fail "a declined Newsboat confirmation is not distinguishable from failure" "$declined_status"
grep -Fxq '{"kind":"scout","count":4}' "$descriptor_log" || fail "Feed Scout confirmation omits the exact feed count"
grep -Fq 'confirmation was cancelled' "$test_tmp/declined-error" || fail "a declined Newsboat confirmation has no clear result"
[[ -z $(find "$NEWSBOAT_CONFIRM_STATE_DIR" -type f -print -quit) ]] || fail "a declined Newsboat confirmation leaves reusable state"
pass "Newsboat treats the separate prompt's cancel action as no consent"

set +e
printf 'yes\n' | "$ROOT/bin/omarchy-newsboat-confirm" triage 1 1 >/dev/null 2>"$test_tmp/piped-error"
piped_status=$?
set -e
(( piped_status == 1 )) || fail "agent-terminal stdin can approve the separate Newsboat prompt" "$piped_status"
pass "Newsboat confirmation cannot be answered through the agent command's stdin"
unset CONFIRM_TEST_DECISION

real_confirmation_dir="$NEWSBOAT_CONFIRM_STATE_DIR"
symlink_target="$test_tmp/confirmation-symlink-target"
mkdir -p "$symlink_target"
rm -rf "$real_confirmation_dir"
/bin/ln -s "$symlink_target" "$real_confirmation_dir"
if "$ROOT/bin/omarchy-newsboat-confirm" scout 1 >/dev/null 2>"$test_tmp/symlink-state-error"; then
  fail "Newsboat confirmation accepts a symlinked state directory"
fi
grep -Fq 'state may not be a symlink' "$test_tmp/symlink-state-error" || fail "symlinked confirmation state has no clear rejection"
[[ -z $(find "$symlink_target" -type f -print -quit) ]] || fail "symlinked confirmation state receives request files"
rm -f "$real_confirmation_dir"
mkdir -p "$real_confirmation_dir"
pass "Newsboat confirmation rejects symlinked private state"

publish_failure_id=publishAB12
printf '%s\n' '{"version":1,"kind":"scout","count":1}' >"$NEWSBOAT_CONFIRM_STATE_DIR/request.$publish_failure_id"
export CONFIRM_TEST_MV_FAIL_PREFIX="$NEWSBOAT_CONFIRM_STATE_DIR/response."
set +e
printf 'approved\n' | "$ROOT/bin/omarchy-newsboat-confirm" --bridge "$NEWSBOAT_CONFIRM_STATE_DIR" "$publish_failure_id" >/dev/null 2>"$test_tmp/publish-failure-error"
publish_failure_status=$?
set -e
unset CONFIRM_TEST_MV_FAIL_PREFIX
(( publish_failure_status == 73 )) || fail "a failed confirmation response publication hides its status" "$publish_failure_status"
[[ ! -e $NEWSBOAT_CONFIRM_STATE_DIR/response.$publish_failure_id ]] || fail "failed confirmation response publication creates a visible decision"
[[ -z $(find "$NEWSBOAT_CONFIRM_STATE_DIR" -type f -name '.response.*' -print -quit) ]] || fail "failed confirmation response publication leaves temporary state"
rm -f "$NEWSBOAT_CONFIRM_STATE_DIR/request.$publish_failure_id"
pass "Newsboat confirmation cleans a response that cannot publish"

mkdir -p "$NEWSBOAT_CONFIRM_STATE_DIR"
direct_request_id=directAB12
printf '%s\n' '{"version":1,"kind":"triage","read":1,"leave":1}' >"$NEWSBOAT_CONFIRM_STATE_DIR/request.$direct_request_id"
export CONFIRM_TEST_REAL_PARENT=true
set +e
printf 'approved\n' | "$ROOT/bin/omarchy-newsboat-confirm" --bridge "$NEWSBOAT_CONFIRM_STATE_DIR" "$direct_request_id" >/dev/null 2>"$test_tmp/direct-bridge-error"
direct_bridge_status=$?
set -e
unset CONFIRM_TEST_REAL_PARENT
(( direct_bridge_status == 2 )) || fail "an agent process can open the private Shell bridge" "$direct_bridge_status"
grep -Fq 'only be opened by Omarchy Shell' "$test_tmp/direct-bridge-error" || fail "the private bridge rejection has no clear result"
[[ ! -e $NEWSBOAT_CONFIRM_STATE_DIR/response.$direct_request_id ]] || fail "a direct bridge call can publish approval"
rm -f "$NEWSBOAT_CONFIRM_STATE_DIR/request.$direct_request_id"
pass "Newsboat keeps approval writes inside the Shell-owned process"

export CONFIRM_TEST_DECISION=invalid
set +e
"$ROOT/bin/omarchy-newsboat-confirm" scout 2 >/dev/null 2>"$test_tmp/invalid-decision-error"
invalid_decision_status=$?
set -e
unset CONFIRM_TEST_DECISION
(( invalid_decision_status == 2 )) || fail "an invalid Shell decision does not fail closed" "$invalid_decision_status"
grep -Fq 'failed without changing anything' "$test_tmp/invalid-decision-error" || fail "an invalid Shell decision hides its safe outcome"
[[ -z $(find "$NEWSBOAT_CONFIRM_STATE_DIR" -type f -print -quit) ]] || fail "an invalid Shell decision leaves reusable state"
pass "Newsboat rejects invalid decisions from the Shell bridge"

export CONFIRM_TEST_SHELL_LAUNCH_RESULT=busy
set +e
"$ROOT/bin/omarchy-newsboat-confirm" scout 1 >/dev/null 2>"$test_tmp/launch-error"
launch_status=$?
set -e
unset CONFIRM_TEST_SHELL_LAUNCH_RESULT
(( launch_status == 2 )) || fail "a rejected Shell launch waits for an invisible confirmation" "$launch_status"
grep -Fq 'Could not open the Newsboat confirmation window: busy' "$test_tmp/launch-error" || fail "a rejected Shell launch hides its safe outcome"
[[ -z $(find "$NEWSBOAT_CONFIRM_STATE_DIR" -type f -print -quit) ]] || fail "a rejected Shell launch leaves reusable state"
pass "Newsboat confirmation fails immediately when Shell cannot open its window"

export CONFIRM_TEST_SKIP_CHILD=true CONFIRM_TEST_WINDOW_STATUS=inactive
set +e
"$ROOT/bin/omarchy-newsboat-confirm" scout 1 >/dev/null 2>"$test_tmp/closed-error"
closed_status=$?
set -e
unset CONFIRM_TEST_WINDOW_STATUS
(( closed_status == 2 )) || fail "a vanished Newsboat confirmation window keeps waiting" "$closed_status"
grep -Fq 'window closed without changing anything' "$test_tmp/closed-error" || fail "a vanished confirmation window hides its safe outcome"
[[ -z $(find "$NEWSBOAT_CONFIRM_STATE_DIR" -type f -print -quit) ]] || fail "a vanished confirmation window leaves reusable state"
pass "Newsboat confirmation detects a window that never appears"

export CONFIRM_TEST_SKIP_CHILD=true
export NEWSBOAT_CONFIRM_TIMEOUT_SECONDS=1
set +e
"$ROOT/bin/omarchy-newsboat-confirm" scout 1 >/dev/null 2>"$test_tmp/timeout-error"
timeout_status=$?
set -e
(( timeout_status == 2 )) || fail "a missing Newsboat confirmation response does not fail closed" "$timeout_status"
grep -Fq 'timed out without changing anything' "$test_tmp/timeout-error" || fail "a Newsboat confirmation timeout hides the safe outcome"
[[ -z $(find "$NEWSBOAT_CONFIRM_STATE_DIR" -type f -print -quit) ]] || fail "a timed-out Newsboat confirmation leaves reusable state"
pass "Newsboat confirmation fails closed when its separate window cannot answer"
unset CONFIRM_TEST_SKIP_CHILD

export CONFIRM_TEST_HANG_CHILD=true
set +e
"$ROOT/bin/omarchy-newsboat-confirm" scout 1 >/dev/null 2>"$test_tmp/hung-error"
hung_status=$?
set -e
unset CONFIRM_TEST_HANG_CHILD
(( hung_status == 2 )) || fail "a hung Shell bridge does not time out safely" "$hung_status"
[[ -z $(find "$NEWSBOAT_CONFIRM_STATE_DIR" -type f -print -quit) ]] || fail "cancelling a hung Shell bridge recreates stale response state"
for _ in {1..20}; do
  kill -0 "$(<"$CONFIRM_TEST_BRIDGE_PID_FILE")" 2>/dev/null || break
  sleep 0.1
done
bridge_state=$("$CONFIRM_TEST_REAL_PS" -o stat= -p "$(<"$CONFIRM_TEST_BRIDGE_PID_FILE")" 2>/dev/null || true)
if [[ -n $bridge_state && $bridge_state != *Z* ]]; then
  fail "cancelling a hung Shell bridge leaves its responder running"
fi
rm -f "$CONFIRM_TEST_BRIDGE_PID_FILE"
pass "Newsboat cleanup cannot race a cancelled Shell bridge response"

grep -Fq 'function launchNewsboatConfirmation(stateDir: string, requestId: string): string' "$ROOT/shell/shell.qml" || fail "Omarchy Shell does not expose the narrow Newsboat confirmation bridge"
grep -Fq 'return newsboatConfirmation.launch(stateDir, requestId)' "$ROOT/shell/shell.qml" || fail "the Shell bridge drops the request state directory"
grep -Fq 'confirmationProcess.command = [root.omarchyPath + "/bin/omarchy-newsboat-confirm", "--bridge", nextDir, nextId]' "$ROOT/shell/NewsboatConfirmation.qml" || fail "the native surface does not use the request-owned confirmation state"
grep -Fq '!/^[A-Za-z0-9_-]{8,64}$/.test(nextId)' "$ROOT/shell/NewsboatConfirmation.qml" || fail "the Shell bridge accepts arbitrary confirmation commands"
grep -Fq '!nextDir.startsWith("/")' "$ROOT/shell/NewsboatConfirmation.qml" || fail "the Shell bridge accepts a relative confirmation state directory"
grep -Fq 'WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive' "$ROOT/shell/NewsboatConfirmation.qml" || fail "the native confirmation does not own keyboard focus"
grep -Fq 'property int selectedIndex: 0' "$ROOT/shell/NewsboatConfirmation.qml" || fail "the native confirmation does not default to Cancel"
grep -Fq 'confirmationProcess.write(decision + "\n")' "$ROOT/shell/NewsboatConfirmation.qml" || fail "the native surface does not return its private decision to the waiting helper"
if grep -Fq 'omarchy-launch-floating-terminal-with-presentation' "$ROOT/shell/shell.qml"; then
  fail "Newsboat confirmation still opens an oversized terminal"
fi
if grep -Fq 'approved' "$ROOT/shell/shell.qml"; then
  fail "the public Shell IPC surface can approve a Newsboat mutation"
fi
pass "Omarchy Shell only brokers opaque Newsboat confirmation IDs"
