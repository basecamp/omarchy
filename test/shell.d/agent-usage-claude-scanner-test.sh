#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

projects="$TEST_HOME/.claude/projects/example"
mkdir -p "$projects"

timestamp="$(date +%Y-%m-%d)T12:00:00Z"
cat >"$projects/session.jsonl" <<EOF
{"timestamp":"$timestamp","type":"assistant","sessionId":"session-1","uuid":"event-1","message":{"id":"message-1","role":"assistant","model":"claude-test","usage":{"input_tokens":2,"cache_creation_input_tokens":28857,"cache_read_input_tokens":0,"output_tokens":231}}}
{"timestamp":"$timestamp","type":"assistant","sessionId":"session-1","uuid":"event-2","message":{"id":"message-1","role":"assistant","model":"claude-test","usage":{"input_tokens":2,"cache_creation_input_tokens":28857,"cache_read_input_tokens":0,"output_tokens":231}}}
{"timestamp":"$timestamp","type":"assistant","sessionId":"session-1","uuid":"event-3","message":{"id":"message-2","role":"assistant","model":"claude-test","usage":{"input_tokens":2,"cache_creation_input_tokens":454,"cache_read_input_tokens":28857,"output_tokens":390}}}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  "$ROOT/bin/omarchy-agent-usage-claude" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "58793" ]] ||
  fail "Claude collector counts each API message once" "$result"
pass "Claude collector counts each API message once"

[[ $(jq -c '.modelUsage["claude-test"]' <<<"$result") == '{"cacheCreationInputTokens":29311,"cacheReadInputTokens":28857,"inputTokens":4,"outputTokens":621}' ]] ||
  fail "Claude collector keeps mutually exclusive token categories" "$result"
pass "Claude collector keeps mutually exclusive token categories"

[[ $(jq -r '.id + "/" + .usageStatusText' <<<"$result") == "claude/Waiting for auth" ]] ||
  fail "Claude collector identifies itself and reports missing auth" "$result"
pass "Claude collector identifies itself and reports missing auth"

# A machine with no transcripts and no stats-cache still gets today's counts
# from history.jsonl alone.
HISTORY_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$HISTORY_HOME"' EXIT
mkdir -p "$HISTORY_HOME/.claude"

now_ms=$(($(date +%s) * 1000))
cat >"$HISTORY_HOME/.claude/history.jsonl" <<EOF
{"timestamp":86400000,"sessionId":"old","display":"ancient"}
{"timestamp":$now_ms,"sessionId":"s1","display":"one"}
{"timestamp":$now_ms,"sessionId":"s2","display":"two"}
EOF

result=$(HOME="$HISTORY_HOME" XDG_CACHE_HOME="$HISTORY_HOME/.cache" \
  "$ROOT/bin/omarchy-agent-usage-claude" --force)

[[ $(jq -r '(.todayPrompts|tostring) + "/" + (.todaySessions|tostring)' <<<"$result") == "2/2" ]] ||
  fail "Claude collector falls back to history.jsonl without a stats-cache" "$result"
pass "Claude collector falls back to history.jsonl without a stats-cache"
