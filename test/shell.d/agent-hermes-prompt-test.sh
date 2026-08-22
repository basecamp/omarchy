#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
hermes_log="$test_tmp/hermes-args"
output="$test_tmp/output"
mkdir -p "$mock_bin"

cat >"$mock_bin/hermes" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_HERMES_LOG"
if [[ " $* " == *" --resume "* ]]; then
  printf 'Follow-up answer.\n'
else
  printf 'session_id: mock-session-123\nPortal crashed in its rendering worker.\n'
fi
SH
chmod +x "$mock_bin/hermes"

export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_TEST_HERMES_LOG="$hermes_log"

coproc DIAGNOSIS { omarchy-agent-hermes-prompt "Crash facts" >"$output" 2>&1; }
diagnosis_pid=$DIAGNOSIS_PID

for _ in $(seq 1 100); do
  grep -Fq 'Portal crashed in its rendering worker.' "$output" && break
  sleep 0.01
done

grep -Fq 'Portal crashed in its rendering worker.' "$output" ||
  fail "Hermes crash diagnosis prints its result"
kill -0 "$diagnosis_pid" 2>/dev/null ||
  fail "Hermes crash diagnosis keeps the terminal open after the result"
grep -Fq 'Ask a follow-up, or press Enter to close' "$output" ||
  fail "Hermes crash diagnosis invites a typed follow-up"

printf 'why did it crash?\n' >&"${DIAGNOSIS[1]}"

for _ in $(seq 1 100); do
  grep -Fq 'Follow-up answer.' "$output" && break
  sleep 0.01
done

grep -Fq 'Follow-up answer.' "$output" ||
  fail "Hermes crash diagnosis answers a typed follow-up"
kill -0 "$diagnosis_pid" 2>/dev/null ||
  fail "Hermes crash diagnosis stays open after the follow-up"

printf '\n' >&"${DIAGNOSIS[1]}"
wait "$diagnosis_pid"

mapfile -d '' -t hermes_args <"$hermes_log"
[[ ${hermes_args[*]} == "chat -q Crash facts -Q --yolo chat -q why did it crash? -Q --yolo --resume mock-session-123" ]] ||
  fail "Hermes crash diagnosis resumes the same session for follow-ups" "${hermes_args[*]}"
pass "Hermes crash diagnosis accepts typed follow-ups in the same session"
