#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# Local session files: two turns. The first today (grok-4.5, two chunks whose
# cumulative totalTokens peak at 1200), the second two days ago under another
# model. events.jsonl maps each turn start to its model id.
now_ms=$(( $(date +%s) * 1000 ))
old_ms=$(( ($(date +%s) - 2 * 86400) * 1000 ))
SESSION="$TEST_HOME/.grok/sessions/project/session-aaa"
mkdir -p "$SESSION"
cat >"$SESSION/events.jsonl" <<EOF
{"ts":"$(date -u -d "@$((now_ms / 1000))" +%Y-%m-%dT%H:%M:%SZ)","type":"turn_started","turn_number":0,"model_id":"grok-4.5","schema_version":"1.0"}
{"ts":"$(date -u -d "@$((old_ms / 1000))" +%Y-%m-%dT%H:%M:%SZ)","type":"turn_started","turn_number":1,"model_id":"grok-3","schema_version":"1.0"}
EOF
cat >"$SESSION/updates.jsonl" <<EOF
{"timestamp":$now_ms,"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_thought_chunk"},"_meta":{"totalTokens":1000,"promptId":"p1","turnStartMs":$now_ms,"streamStartMs":$now_ms,"updateType":"AgentThoughtChunk","chunkId":1}}}
{"timestamp":$((now_ms + 100)),"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk"},"_meta":{"totalTokens":1200,"promptId":"p1","turnStartMs":$now_ms,"streamStartMs":$now_ms,"updateType":"AgentMessageChunk","chunkId":2}}}
{"timestamp":$old_ms,"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk"},"_meta":{"totalTokens":500,"promptId":"p2","turnStartMs":$old_ms,"streamStartMs":$old_ms,"updateType":"AgentMessageChunk","chunkId":3}}}
EOF

# pi transcripts: an assistant message routed through the xai (Grok) provider,
# carrying a full input/output/cache split for the same grok-4.5 model.
mkdir -p "$TEST_HOME/.pi/agent/sessions/project"
cat >"$TEST_HOME/.pi/agent/sessions/project/session-pi.jsonl" <<EOF
{"type":"message","id":"pi-1","parentId":null,"timestamp":"$(date -u -d "@$((now_ms / 1000))" +%Y-%m-%dT%H:%M:%SZ)","message":{"role":"assistant","provider":"xai","model":"grok-4.5","usage":{"input":300,"output":100,"cacheRead":400,"cacheWrite":0,"totalTokens":800}}}
EOF

result=$(HOME="$TEST_HOME" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --local-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "2000" ]] ||
  fail "Grok takes the peak cumulative tokens per turn" "$result"
[[ $(jq -c '.totalPrompts' <<<"$result") == "3" ]] ||
  fail "Grok counts session turns plus pi" "$result"
[[ $(jq -c '.todayPrompts' <<<"$result") == "2" ]] ||
  fail "Grok counts today's turns" "$result"
[[ $(jq -r '.modelUsage["grok-4.5"].inputTokens' <<<"$result") == "1500" ]] ||
  fail "Grok reports the turn total as input tokens" "$result"
[[ $(jq -r '.modelUsage["grok-4.5"].outputTokens' <<<"$result") == "100" ]] ||
  fail "Grok adds pi output onto the native turn" "$result"
[[ $(jq -r '.modelUsage["grok-4.5"].cacheReadInputTokens' <<<"$result") == "400" ]] ||
  fail "Grok keeps the pi cache split separate" "$result"
[[ $(jq -r '.modelUsage["grok-3"].inputTokens' <<<"$result") == "500" ]] ||
  fail "Grok maps turns to their model" "$result"
[[ $(jq -c '.id' <<<"$result") == '"grok"' ]] ||
  fail "Grok record identifies itself" "$result"
pass "Grok local scan aggregates native+pi per model"