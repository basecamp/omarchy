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
  python3 "$ROOT/shell/plugins/model-usage/scripts/claude_usage_scanner.py" "$TEST_HOME/.claude/projects" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "58793" ]] ||
  fail "Claude scanner counts each API message once" "$result"
pass "Claude scanner counts each API message once"

[[ $(jq -c '.modelUsage["claude-test"]' <<<"$result") == '{"cacheCreationInputTokens":29311,"cacheReadInputTokens":28857,"inputTokens":4,"outputTokens":621}' ]] ||
  fail "Claude scanner keeps mutually exclusive token categories" "$result"
pass "Claude scanner keeps mutually exclusive token categories"
