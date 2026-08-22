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
printf '%s\0' "$@" >"$OMARCHY_TEST_HERMES_LOG"
printf 'Portal crashed in its rendering worker.\n'
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
grep -Fq 'Press Enter to close' "$output" ||
  fail "Hermes crash diagnosis explains how to close the result"

printf '\n' >&"${DIAGNOSIS[1]}"
wait "$diagnosis_pid"

mapfile -d '' -t hermes_args <"$hermes_log"
[[ ${hermes_args[*]} == "-z Crash facts" ]] ||
  fail "Hermes crash diagnosis invokes one-shot mode with the complete prompt" "${hermes_args[*]}"
pass "Hermes one-shot diagnosis remains visible until Enter"
