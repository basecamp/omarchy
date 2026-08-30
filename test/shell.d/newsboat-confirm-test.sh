#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
runtime_dir="$test_tmp/runtime"
launch_log="$test_tmp/launch"
gum_log="$test_tmp/gum"
mkdir -p "$mock_bin" "$runtime_dir"

export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT"
export XDG_RUNTIME_DIR="$runtime_dir"
export NEWSBOAT_CONFIRM_STATE_DIR="$runtime_dir/confirmations"
export NEWSBOAT_CONFIRM_TIMEOUT_SECONDS=2
export CONFIRM_TEST_LAUNCH_LOG="$launch_log"
export CONFIRM_TEST_GUM_LOG="$gum_log"

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$CONFIRM_TEST_LAUNCH_LOG"
if [[ ${CONFIRM_TEST_SKIP_CHILD:-false} == "true" ]]; then
  exit 0
fi
exec /bin/bash -c "$1" </dev/null
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

chmod +x "$mock_bin/omarchy-launch-floating-terminal-with-presentation" "$mock_bin/gum"

export CONFIRM_TEST_GUM_STATUS=0
"$ROOT/bin/omarchy-newsboat-confirm" triage 44 3
grep -Eq '/bin/omarchy-newsboat-confirm --respond [A-Za-z0-9_-]+; exit 130$' "$launch_log" || fail "Newsboat confirmation does not leave the agent terminal"
grep -Fq 'Mark 44 articles as read and leave 3 unread?' "$gum_log" || fail "Newsboat triage confirmation omits the exact effect"
[[ -z $(find "$NEWSBOAT_CONFIRM_STATE_DIR" -type f -print -quit) ]] || fail "an approved Newsboat confirmation leaves reusable state"
pass "Newsboat requires an exact out-of-band triage approval"

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
