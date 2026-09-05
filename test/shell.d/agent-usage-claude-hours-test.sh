#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

projects="$TEST_HOME/.claude/projects/example"
mkdir -p "$projects"

# Two fixed UTC timestamps; expected weekday/hour derive from the same TZ
# the collector uses, so the assert is exact on any runner.
T1="2026-08-28T12:00:00Z"
T2="2026-08-28T14:30:00Z"
W1=$(date -d "$T1" +%w)   # 0=Sunday, matching the emitted contract
H1=$(date -d "$T1" +%H)
W2=$(date -d "$T2" +%w)
H2=$(date -d "$T2" +%H)

cat >"$projects/session.jsonl" <<EOF
{"timestamp":"$T1","type":"assistant","sessionId":"session-1","uuid":"e1","message":{"id":"m1","role":"assistant","model":"claude-test","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}}}
{"timestamp":"$T2","type":"assistant","sessionId":"session-1","uuid":"e2","message":{"id":"m2","role":"assistant","model":"claude-test","usage":{"input_tokens":7,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":3}}}
{"timestamp":"$T2","type":"assistant","sessionId":"session-1","uuid":"e3","message":{"id":"m3","role":"assistant","model":"claude-test","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_DATA_HOME="$TEST_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-claude" --force)

[[ $(jq -r '.usageByHour | length' <<<"$result") == "2" ]] ||
  fail "usageByHour emits two distinct weekday-hour buckets" "$result"
pass "usageByHour emits two distinct weekday-hour buckets"

[[ $(jq -c '[.usageByHour[] | [.weekday, .hour, .tokens]]' <<<"$result") == "[[$W1,$H1,15],[$W2,$H2,10]]" ]] ||
  fail "buckets carry local weekday/hour and summed tokens, sorted" "$result"
pass "buckets carry local weekday/hour and summed tokens, sorted"

[[ $(jq -r '[.usageByHour[].tokens] | add' <<<"$result") == "25" ]] ||
  fail "hour buckets sum to the record's total (one reality)" "$result"
pass "hour buckets sum to the record's total (one reality)"

jq -e '.usageByHour | all((.tokens | floor) == .tokens) and all(.tokens > 0)' <<<"$result" >/dev/null ||
  fail "every bucket is a positive integer (zero and fractional cells absent)"
pass "every bucket is a positive integer (zero and fractional cells absent)"

pass "collector runs cleanly on a synthetic transcript"
