#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
oneshot_log="$test_tmp/oneshot"
resume_log="$test_tmp/resume"
source_log="$test_tmp/source"
setup_log="$test_tmp/setup"
setup_marker="$test_tmp/setup-complete"
mkdir -p "$mock_bin"

cat >"$mock_bin/hermes" <<'SH'
#!/bin/bash

if [[ ${1:-} == "setup" ]]; then
  printf '%s\0' "$@" >"$HERMES_TEST_SETUP_LOG"
  [[ ${HERMES_TEST_SETUP_FAIL:-false} == "false" ]] || exit 43
  touch "$HERMES_TEST_SETUP_MARKER"
  exit
fi

if [[ " $* " == *" --oneshot="* ]]; then
  printf '%s\0' "$@" >"$HERMES_TEST_ONESHOT_LOG"
  printf '%s' "${HERMES_SESSION_SOURCE:-}" >"$HERMES_TEST_SOURCE_LOG"

  while (( $# )); do
    if [[ $1 == "--usage-file" ]]; then
      usage=$2
      break
    fi
    shift
  done

  if [[ ${HERMES_TEST_NEEDS_SETUP:-false} == "true" && ! -e $HERMES_TEST_SETUP_MARKER ]]; then
    printf '{"session_id":null,"completed":null,"failed":true,"failure":"No inference provider configured. Run hermes model."}\n' >"$usage"
    exit 1
  fi

  [[ ${HERMES_TEST_ONESHOT_FAIL:-false} == "false" ]] || exit 42
  if [[ ${HERMES_TEST_USAGE_FAIL:-false} == "false" ]]; then
    completed=true
    failed=false
    [[ ${HERMES_TEST_USAGE_INCOMPLETE:-false} == "false" ]] || completed=false
    [[ ${HERMES_TEST_USAGE_FAILED:-false} == "false" ]] || failed=true
    printf '{"session_id":"session-123","completed":%s,"failed":%s}\n' "$completed" "$failed" >"$usage"
  fi
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
export HERMES_TEST_SETUP_LOG="$setup_log"
export HERMES_TEST_SETUP_MARKER="$setup_marker"

sentinel="$test_tmp/hermes-seed-must-stay-literal"
prompt="--help !Crash /quit {!touch $sentinel}"$'\ntrailing\\'
"$ROOT/bin/omarchy-agent-hermes" "$prompt" >/dev/null

mapfile -d '' -t oneshot_args <"$oneshot_log"
(( ${#oneshot_args[@]} == 4 )) || fail "Hermes literal seed has four one-shot arguments"
[[ ${oneshot_args[0]} == "--yolo" ]] || fail "Hermes literal seed enables yolo mode"
[[ ${oneshot_args[1]} == "--usage-file" ]] || fail "Hermes literal seed requests the session report"
usage_file=${oneshot_args[2]}
[[ ${oneshot_args[3]} == "--oneshot=$prompt" ]] || fail "Hermes literal seed binds option-looking prompts as data"
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

for state in INCOMPLETE FAILED; do
  : >"$resume_log"
  if env "HERMES_TEST_USAGE_$state=true" "$ROOT/bin/omarchy-agent-hermes" "${state,,}" >/dev/null 2>&1; then
    fail "Hermes literal seed rejects a reported ${state,,} initial turn"
  fi
  [[ ! -s $resume_log ]] || fail "Hermes literal seed does not resume a reported ${state,,} initial turn"
done
pass "Hermes resumes only completed successful initial turns"

: >"$resume_log"
HERMES_TEST_NEEDS_SETUP=true "$ROOT/bin/omarchy-agent-hermes" setup-first >/dev/null
mapfile -d '' -t setup_args <"$setup_log"
[[ ${setup_args[*]} == "setup" ]] || fail "Hermes runs setup when no inference provider is configured"
mapfile -d '' -t resume_args <"$resume_log"
[[ ${resume_args[*]} == "chat --yolo --tui --resume session-123" ]] ||
  fail "Hermes replays the prompted turn after setup and resumes it"
pass "Hermes completes first-run setup before replaying the prompt"

rm -f "$setup_marker"
: >"$resume_log"
if HERMES_TEST_NEEDS_SETUP=true HERMES_TEST_SETUP_FAIL=true "$ROOT/bin/omarchy-agent-hermes" setup-cancelled >/dev/null 2>&1; then
  fail "Hermes reports a failed first-run setup"
fi
[[ ! -s $resume_log ]] || fail "Hermes does not resume when first-run setup fails"
pass "Hermes stops when first-run setup does not complete"
