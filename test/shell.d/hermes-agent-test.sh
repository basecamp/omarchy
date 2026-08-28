#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
oneshot_log="$test_tmp/oneshot"
resume_log="$test_tmp/resume"
source_log="$test_tmp/source"
mkdir -p "$mock_bin"

cat >"$mock_bin/hermes" <<'SH'
#!/bin/bash

if [[ " $* " == *" --oneshot "* ]]; then
  printf '%s\0' "$@" >"$HERMES_TEST_ONESHOT_LOG"
  printf '%s' "${HERMES_SESSION_SOURCE:-}" >"$HERMES_TEST_SOURCE_LOG"

  while (( $# )); do
    if [[ $1 == "--usage-file" ]]; then
      usage=$2
      break
    fi
    shift
  done

  [[ ${HERMES_TEST_ONESHOT_FAIL:-false} == "false" ]] || exit 42
  [[ ${HERMES_TEST_USAGE_FAIL:-false} == "false" ]] && printf '{"session_id":"session-123"}\n' >"$usage"
  printf '%s\n' response
  exit
fi

printf '%s\0' "$@" >"$HERMES_TEST_RESUME_LOG"
SH

chmod +x "$mock_bin/hermes"

export PATH="$mock_bin:$PATH"
export HERMES_TEST_ONESHOT_LOG="$oneshot_log"
export HERMES_TEST_RESUME_LOG="$resume_log"
export HERMES_TEST_SOURCE_LOG="$source_log"

sentinel="$test_tmp/hermes-seed-must-stay-literal"
prompt="!Crash /quit {!touch $sentinel}"$'\ntrailing\\'
"$ROOT/bin/omarchy-agent-hermes" "$prompt" >/dev/null

mapfile -d '' -t oneshot_args <"$oneshot_log"
(( ${#oneshot_args[@]} == 5 )) || fail "Hermes literal seed has five one-shot arguments"
[[ ${oneshot_args[0]} == "--yolo" ]] || fail "Hermes literal seed enables yolo mode"
[[ ${oneshot_args[1]} == "--usage-file" ]] || fail "Hermes literal seed requests the session report"
usage_file=${oneshot_args[2]}
[[ ${oneshot_args[3]} == "--oneshot" && ${oneshot_args[4]} == "$prompt" ]] ||
  fail "Hermes literal seed remains one argument"
[[ ! -e $usage_file ]] || fail "Hermes literal seed removes its session report"
[[ ! -e $sentinel ]] || fail "Hermes literal seed never executes prompt interpolation"
[[ ! -s $source_log ]] || fail "Hermes literal seed preserves native CLI session metadata"

mapfile -d '' -t resume_args <"$resume_log"
[[ ${resume_args[*]} == "chat --yolo --tui --resume session-123" ]] ||
  fail "Hermes literal seed resumes the exact completed session"
pass "Hermes sends initial prompts literally and resumes their exact session"

: >"$resume_log"
if HERMES_TEST_ONESHOT_FAIL=true "$ROOT/bin/omarchy-agent-hermes" failure >/dev/null 2>&1; then
  fail "Hermes literal seed reports a failed initial turn"
fi
[[ ! -s $resume_log ]] || fail "Hermes literal seed does not resume a failed initial turn"
pass "Hermes does not resume after a failed initial turn"

: >"$resume_log"
if HERMES_TEST_USAGE_FAIL=true "$ROOT/bin/omarchy-agent-hermes" missing-session >/dev/null 2>&1; then
  fail "Hermes literal seed requires a recorded session ID"
fi
[[ ! -s $resume_log ]] || fail "Hermes literal seed does not guess which session to resume"
pass "Hermes resumes only the session recorded by the initial turn"
