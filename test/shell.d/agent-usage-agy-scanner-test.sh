#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

brain_dir="$TEST_HOME/.gemini/antigravity-cli/brain/session-123/.system_generated/logs"
mkdir -p "$brain_dir"

timestamp="$(date +%Y-%m-%d)T12:00:00Z"
cat >"$brain_dir/transcript.jsonl" <<EOF
{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"$timestamp","content":"<USER_REQUEST>\nhello world\n</USER_REQUEST>\n<USER_SETTINGS_CHANGE>\nThe user changed setting \`Model Selection\` from None to Gemini 3.7 Flash (High).\n</USER_SETTINGS_CHANGE>"}
{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"$timestamp","content":"Hello there!","thinking":"thinking process","usage":{"input_tokens":100,"output_tokens":50,"cached_content_token_count":20}}
{"step_index":2,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"$timestamp","content":"write a function"}
{"step_index":3,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"$timestamp","content":"def foo(): pass","usage":{"input_tokens":150,"output_tokens":80,"cached_content_token_count":0}}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_DATA_HOME="$TEST_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-agy" --force)

[[ $(jq -r '.id' <<<"$result") == "agy" ]] ||
  fail "Antigravity collector reports correct agent ID" "$result"
pass "Antigravity collector reports correct agent ID"

[[ $(jq -r '.name' <<<"$result") == "Antigravity" ]] ||
  fail "Antigravity collector reports correct agent name" "$result"
pass "Antigravity collector reports correct agent name"

[[ $(jq -r '.totalPrompts' <<<"$result") == "2" ]] ||
  fail "Antigravity collector counts user prompts" "$result"
pass "Antigravity collector counts user prompts"

[[ $(jq -r '.todayPrompts' <<<"$result") == "2" ]] ||
  fail "Antigravity collector counts today's prompts" "$result"
pass "Antigravity collector counts today's prompts"

[[ $(jq -r '.todaySessions' <<<"$result") == "1" ]] ||
  fail "Antigravity collector counts today's sessions" "$result"
pass "Antigravity collector counts today's sessions"

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "400" ]] ||
  fail "Antigravity collector sums token usage" "$result"
pass "Antigravity collector sums token usage"

[[ $(jq -c '.modelUsage["gemini-3.7-flash"]' <<<"$result") == '{"cacheCreationInputTokens":0,"cacheReadInputTokens":20,"inputTokens":250,"outputTokens":130}' ]] ||
  fail "Antigravity collector categorizes model tokens" "$result"
pass "Antigravity collector categorizes model tokens"

# Test fallback to history.jsonl when no transcripts exist
HISTORY_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$HISTORY_HOME"' EXIT
mkdir -p "$HISTORY_HOME/.gemini/antigravity-cli"

now_ms=$(($(date +%s) * 1000))
cat >"$HISTORY_HOME/.gemini/antigravity-cli/history.jsonl" <<EOF
{"timestamp":86400000,"display":"ancient command"}
{"timestamp":$now_ms,"display":"first query today"}
{"timestamp":$now_ms,"display":"second query today"}
EOF

result=$(HOME="$HISTORY_HOME" XDG_CACHE_HOME="$HISTORY_HOME/.cache" XDG_DATA_HOME="$HISTORY_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-agy" --force)

[[ $(jq -r '(.totalPrompts|tostring) + "/" + (.todayPrompts|tostring)' <<<"$result") == "3/2" ]] ||
  fail "Antigravity collector falls back to history.jsonl" "$result"
pass "Antigravity collector falls back to history.jsonl"

# Test cached limits and tier extraction
LIMITS_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$HISTORY_HOME" "$LIMITS_HOME"' EXIT
mkdir -p "$LIMITS_HOME/.cache/omarchy/agent-usage"

cat >"$LIMITS_HOME/.cache/omarchy/agent-usage/agy-limits.json" <<EOF
{
  "fetchedAtMs": $now_ms,
  "tierLabel": "Google AI Pro",
  "limits": [
    {
      "label": "Session (5-hour)",
      "title": "Gemini (5h)",
      "percent": 0.1021,
      "resetsAt": "2030-01-01T12:00:00Z"
    },
    {
      "label": "Weekly (7-day)",
      "title": "Gemini (Weekly)",
      "percent": 0.0224,
      "resetsAt": "2030-01-07T12:00:00Z"
    }
  ]
}
EOF

result=$(HOME="$LIMITS_HOME" XDG_CACHE_HOME="$LIMITS_HOME/.cache" XDG_DATA_HOME="$LIMITS_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-agy" --limits-only)

[[ $(jq -r '.tierLabel' <<<"$result") == "Google AI Pro" ]] ||
  fail "Antigravity collector loads tier label from cache" "$result"
pass "Antigravity collector loads tier label from cache"

[[ $(jq -r '.limits | length' <<<"$result") == "2" ]] ||
  fail "Antigravity collector loads limits list from cache" "$result"
pass "Antigravity collector loads limits list from cache"

[[ $(jq -r '.limits[0].title + "/" + (.limits[0].percent|tostring)' <<<"$result") == "Gemini (5h)/0.1021" ]] ||
  fail "Antigravity collector preserves limit percent and titles" "$result"
pass "Antigravity collector preserves limit percent and titles"
