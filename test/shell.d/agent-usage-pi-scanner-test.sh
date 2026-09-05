#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.pi/agent/sessions/project" "$TEST_HOME/.omp/agent/sessions/project"

timestamp="$(date +%Y-%m-%d)T12:00:00Z"

cat >"$TEST_HOME/.pi/agent/sessions/project/pi.jsonl" <<EOF
{"type":"message","id":"pi-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"anthropic","api":"anthropic-messages","model":"claude-pi","usage":{"input":10,"output":4,"cacheRead":3,"cacheWrite":2,"totalTokens":19}}}
{"type":"message","id":"codex-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"openai-codex","model":"gpt-test","usage":{"input":999,"output":999}}}
{"type":"message","id":"kimi-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"kimi-coding","api":"anthropic-messages","model":"k3","usage":{"input":999,"output":999}}}
EOF
cat >"$TEST_HOME/.omp/agent/sessions/project/omp.jsonl" <<EOF
{ "type": "message", "id": "omp-1", "timestamp": "$timestamp", "message": { "role": "assistant", "provider": "anthropic", "model": "claude-omp", "usage": { "input": 20, "output": 5, "cacheRead": 4, "cacheWrite": 1, "totalTokens": 30 } } }
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_DATA_HOME="$TEST_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-pi" --force)

[[ $(jq -r '.id' <<<"$result") == "pi" ]] ||
  fail "Pi collector identifies itself" "$result"
pass "Pi collector identifies itself"

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "4045" ]] ||
  fail "Pi collector counts usage from every configured backend" "$result"
pass "Pi collector counts usage from every configured backend"

[[ $(jq -c '.todayTokensByModel' <<<"$result") == '{"claude-omp":30,"claude-pi":19,"gpt-test":1998,"k3":1998}' ]] ||
  fail "Pi collector keeps today tokens per model" "$result"
pass "Pi collector keeps today tokens per model"

[[ $(jq -c '.modelUsage' <<<"$result") == '{"claude-omp":{"cacheCreationInputTokens":1,"cacheReadInputTokens":4,"inputTokens":20,"outputTokens":5},"claude-pi":{"cacheCreationInputTokens":2,"cacheReadInputTokens":3,"inputTokens":10,"outputTokens":4},"gpt-test":{"cacheCreationInputTokens":0,"cacheReadInputTokens":0,"inputTokens":999,"outputTokens":999},"k3":{"cacheCreationInputTokens":0,"cacheReadInputTokens":0,"inputTokens":999,"outputTokens":999}}' ]] ||
  fail "Pi collector aggregates tokens by model for all providers" "$result"
pass "Pi collector aggregates tokens by model for all providers"
