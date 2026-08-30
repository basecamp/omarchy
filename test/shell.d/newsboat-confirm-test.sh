#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
sandbox_runtime="$test_tmp/sandbox-runtime"
trap 'chmod 700 "$sandbox_runtime" 2>/dev/null || true; rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
runtime_dir="$test_tmp/runtime"
agent_runtime="$test_tmp/agent-runtime"
launch_log="$test_tmp/launch"
gum_log="$test_tmp/gum"
mkdir -p "$mock_bin" "$runtime_dir" "$sandbox_runtime"

export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT"
export XDG_RUNTIME_DIR="$runtime_dir"
export NEWSBOAT_CONFIRM_STATE_DIR="$runtime_dir/confirmations"
export NEWSBOAT_CONFIRM_TIMEOUT_SECONDS=2
export CONFIRM_TEST_LAUNCH_LOG="$launch_log"
export CONFIRM_TEST_GUM_LOG="$gum_log"

cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$CONFIRM_TEST_LAUNCH_LOG"
case ${1:-}:${2:-} in
  shell:launchNewsboatConfirmation)
    if [[ ${CONFIRM_TEST_SHELL_LAUNCH_STATUS:-0} != 0 ]]; then
      exit "$CONFIRM_TEST_SHELL_LAUNCH_STATUS"
    elif [[ ${CONFIRM_TEST_SHELL_LAUNCH_RESULT:-ok} != "ok" ]]; then
      echo "$CONFIRM_TEST_SHELL_LAUNCH_RESULT"
      exit 0
    elif [[ ${CONFIRM_TEST_SKIP_CHILD:-false} != "true" ]]; then
      "$OMARCHY_PATH/bin/omarchy-newsboat-confirm" --respond "$3" </dev/null &
    fi
    echo ok
    ;;
  shell:newsboatConfirmationStatus) echo "${CONFIRM_TEST_WINDOW_STATUS:-active}" ;;
  shell:cancelNewsboatConfirmation) echo ok ;;
  *) exit 64 ;;
esac
SH

cat >"$mock_bin/gum" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$CONFIRM_TEST_GUM_LOG"
if [[ ${CONFIRM_TEST_GUM_STATUS:-0} == "stdin" ]]; then
  read -r answer || answer=""
  [[ $answer == "yes" ]]
else
  exit "$CONFIRM_TEST_GUM_STATUS"
fi
SH

chmod +x "$mock_bin/omarchy-shell" "$mock_bin/gum"

file_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

export CONFIRM_TEST_GUM_STATUS=0
"$ROOT/bin/omarchy-newsboat-confirm" triage 44 3
grep -Eq '^shell launchNewsboatConfirmation [A-Za-z0-9_-]+$' "$launch_log" || fail "Newsboat confirmation does not leave the agent sandbox through Shell IPC"
grep -Fq 'Mark 44 articles as read and leave 3 unread?' "$gum_log" || fail "Newsboat triage confirmation omits the exact effect"
[[ -z $(find "$NEWSBOAT_CONFIRM_STATE_DIR" -type f -print -quit) ]] || fail "an approved Newsboat confirmation leaves reusable state"
pass "Newsboat requires an exact out-of-band triage approval"

unset NEWSBOAT_CONFIRM_STATE_DIR
export NEWSBOAT_CONFIRM_RUNTIME_DIR="$agent_runtime"
export XDG_RUNTIME_DIR="$sandbox_runtime"
chmod 500 "$sandbox_runtime"
state_root="$agent_runtime/omarchy-newsboat-$UID"
mkdir -p "$state_root"
chmod 755 "$state_root"
: >"$gum_log"
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

: >"$gum_log"
export CONFIRM_TEST_GUM_STATUS=1
set +e
"$ROOT/bin/omarchy-newsboat-confirm" scout 4 >"$test_tmp/declined-output" 2>"$test_tmp/declined-error"
declined_status=$?
set -e
(( declined_status == 1 )) || fail "a declined Newsboat confirmation is not distinguishable from failure" "$declined_status"
grep -Fq 'Add 4 validated feeds to Newsboat?' "$gum_log" || fail "Feed Scout confirmation omits the exact feed count"
grep -Fq 'confirmation was cancelled' "$test_tmp/declined-error" || fail "a declined Newsboat confirmation has no clear result"
[[ -z $(find "$NEWSBOAT_CONFIRM_STATE_DIR" -type f -print -quit) ]] || fail "a declined Newsboat confirmation leaves reusable state"
pass "Newsboat treats the separate prompt's cancel action as no consent"

export CONFIRM_TEST_GUM_STATUS=stdin
set +e
printf 'yes\n' | "$ROOT/bin/omarchy-newsboat-confirm" triage 1 1 >/dev/null 2>"$test_tmp/piped-error"
piped_status=$?
set -e
(( piped_status == 1 )) || fail "agent-terminal stdin can approve the separate Newsboat prompt" "$piped_status"
pass "Newsboat confirmation cannot be answered through the agent command's stdin"

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

grep -Fq 'function launchNewsboatConfirmation(requestId: string): string' "$ROOT/shell/shell.qml" || fail "Omarchy Shell does not expose the narrow Newsboat confirmation bridge"
grep -Fq '!/^[A-Za-z0-9_-]{8,64}$/.test(id)' "$ROOT/shell/shell.qml" || fail "the Shell bridge accepts arbitrary confirmation commands"
grep -Fq 'newsboatConfirmationProcess.command = [' "$ROOT/shell/shell.qml" || fail "the Shell bridge does not use its tracked confirmation process"
pass "Omarchy Shell only brokers opaque Newsboat confirmation IDs"
