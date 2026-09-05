#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.gemini/antigravity-cli/brain/conv-123/.system_generated/logs" "$TEST_HOME/bin"

# 1. Mock agy binary for live limits
cat >"$TEST_HOME/bin/agy" <<'MOCK_EOF'
#!/bin/bash
if [[ "$*" == *"/usage"* ]]; then
  cat <<'JSON_EOF'
{
  "command": {
    "name": "usage",
    "data": {
      "groups": [
        {
          "name": "Gemini Models",
          "buckets": [
            {
              "id": "gemini-weekly",
              "name": "Weekly Limit Remaining",
              "window": "weekly",
              "remaining_fraction": 0.85,
              "reset_time": "2026-08-26T23:00:00Z"
            },
            {
              "id": "gemini-5h",
              "name": "Five Hour Limit Remaining",
              "window": "5h",
              "remaining_fraction": 0.70,
              "reset_time": "2026-08-21T21:00:00Z"
            }
          ]
        },
        {
          "name": "Claude and GPT models",
          "buckets": [
            {
              "id": "3p-weekly",
              "name": "Weekly Limit Remaining",
              "window": "weekly",
              "remaining_fraction": 0.90,
              "reset_time": "2026-08-27T12:00:00Z"
            },
            {
              "id": "3p-5h",
              "name": "Five Hour Limit Remaining",
              "window": "5h",
              "remaining_fraction": 1.0,
              "reset_time": "2026-08-21T22:00:00Z"
            }
          ]
        }
      ]
    }
  }
}
JSON_EOF
  exit 0
fi
exit 1
MOCK_EOF
chmod +x "$TEST_HOME/bin/agy"

# 2. Populate transcript
today_iso="$(date -u +%Y-%m-%dT12:00:00Z)"
t_file="$TEST_HOME/.gemini/antigravity-cli/brain/conv-123/.system_generated/logs/transcript.jsonl"

cat >"$t_file" <<EOF
{"step_index":1,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"$today_iso","content":"Hello, please help with Gemini 3.7 Pro coding"}
{"step_index":2,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"$today_iso","content":"Here is the plan for Gemini 3.7 Pro:","thinking":"Deep thinking tokens...","tool_calls":[]}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_STATE_HOME="$TEST_HOME/.local/state"   PATH="$TEST_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-antigravity" --force)

[[ $(jq -r '.id' <<<"$result") == "antigravity" ]] ||
  fail "Antigravity collector identifies itself as antigravity" "$result"
pass "Antigravity collector identifies itself as antigravity"

[[ $(jq -r '.name' <<<"$result") == "Antigravity" ]] ||
  fail "Antigravity collector has name Antigravity" "$result"
pass "Antigravity collector has name Antigravity"

[[ $(jq -r '.todaySessions' <<<"$result") == "1" ]] ||
  fail "Antigravity collector counts today sessions" "$result"
pass "Antigravity collector counts today sessions"

[[ $(jq -r '.totalSessions' <<<"$result") == "1" ]] ||
  fail "Antigravity collector counts total sessions" "$result"
pass "Antigravity collector counts total sessions"

[[ $(jq -r '.modelUsage["gemini-3.7-pro"].outputTokens' <<<"$result") -gt 0 ]] ||
  fail "Antigravity collector attributes tokens to detected model" "$result"
pass "Antigravity collector attributes tokens to detected model"

# Test live limits parsing
[[ $(jq -r '.limits | length' <<<"$result") == "4" ]] ||
  fail "Antigravity collector returns 4 rate limit buckets" "$result"
pass "Antigravity collector returns 4 rate limit buckets"

[[ $(jq -r '.limits[0].label' <<<"$result") == "Gemini (5-hour)" ]] ||
  fail "Antigravity collector formats session bucket label" "$result"
pass "Antigravity collector formats session bucket label"

[[ $(jq -r '.limits[0].percent' <<<"$result") == "0.3" ]] ||
  fail "Antigravity collector calculates used percentage from remaining_fraction" "$result"
pass "Antigravity collector calculates used percentage from remaining_fraction"

[[ $(jq -r '.limits[1].label' <<<"$result") == "Gemini (7-day)" ]] ||
  fail "Antigravity collector formats weekly bucket label" "$result"
pass "Antigravity collector formats weekly bucket label"

# 3. Fallback when only history.jsonl is present
HISTORY_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$HISTORY_HOME"' EXIT
mkdir -p "$HISTORY_HOME/.gemini/antigravity-cli"

now_ms=$(($(date +%s) * 1000))
cat >"$HISTORY_HOME/.gemini/antigravity-cli/history.jsonl" <<EOF
{"timestamp":$now_ms,"conversationId":"h-1","text":"prompt 1"}
{"timestamp":$now_ms,"conversationId":"h-2","text":"prompt 2"}
{"timestamp":86400000,"conversationId":"h-old","text":"ancient prompt"}
EOF

hist_result=$(HOME="$HISTORY_HOME" XDG_CACHE_HOME="$HISTORY_HOME/.cache" XDG_STATE_HOME="$HISTORY_HOME/.local/state"   PATH="/usr/bin:/bin" "$ROOT/bin/omarchy-agent-usage-antigravity" --force)

[[ $(jq -r '(.todayPrompts|tostring) + "/" + (.todaySessions|tostring)' <<<"$hist_result") == "2/2" ]] ||
  fail "Antigravity collector falls back to history.jsonl" "$hist_result"
pass "Antigravity collector falls back to history.jsonl"

[[ $(jq -r '.totalPrompts' <<<"$hist_result") == "3" ]] ||
  fail "Antigravity collector reads total prompts from history.jsonl" "$hist_result"
pass "Antigravity collector reads total prompts from history.jsonl"

# Fallback limits when agy is missing
[[ $(jq -r '.limits | length' <<<"$hist_result") == "4" ]] ||
  fail "Antigravity collector provides fallback limits without agy binary" "$hist_result"
pass "Antigravity collector provides fallback limits without agy binary"
