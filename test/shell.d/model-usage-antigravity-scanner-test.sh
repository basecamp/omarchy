#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# Set up local history.jsonl
mkdir -p "$TEST_HOME/.gemini/antigravity-cli"
history_file="$TEST_HOME/.gemini/antigravity-cli/history.jsonl"

today_ms=$(python3 -c "import time; print(int(time.time() * 1000))")
yesterday_ms=$((today_ms - 86400000))

cat >"$history_file" <<EOF
{"timestamp": $yesterday_ms, "conversationId": "yesterday-session"}
{"timestamp": $today_ms, "conversationId": "today-session-1"}
{"timestamp": $((today_ms + 1000)), "conversationId": "today-session-1"}
{"timestamp": $((today_ms + 2000)), "conversationId": "today-session-2"}
EOF

result=$(HOME="$TEST_HOME" python3 "$ROOT/shell/plugins/model-usage/scripts/antigravity_usage_scanner.py")

# Test total prompts
total_prompts=$(jq -r '.totalPrompts' <<<"$result")
[[ $total_prompts == "4" ]] || fail "Antigravity scanner total prompts mismatch" "$result"
pass "Antigravity scanner parses total prompts"

# Test today's prompts
today_prompts=$(jq -r '.todayPrompts' <<<"$result")
[[ $today_prompts == "3" ]] || fail "Antigravity scanner today prompts mismatch" "$result"
pass "Antigravity scanner parses today's prompts"

# Test today's sessions
today_sessions=$(jq -r '.todaySessions' <<<"$result")
[[ $today_sessions == "2" ]] || fail "Antigravity scanner today sessions mismatch" "$result"
pass "Antigravity scanner parses today's unique sessions"

# Test total sessions
total_sessions=$(jq -r '.totalSessions' <<<"$result")
[[ $total_sessions == "3" ]] || fail "Antigravity scanner total sessions mismatch" "$result"
pass "Antigravity scanner parses total unique sessions"

# Test active days
active_days=$(jq -r '.activeDays' <<<"$result")
[[ $active_days == "2" ]] || fail "Antigravity scanner active days mismatch" "$result"
pass "Antigravity scanner parses active days"

# Test recent days
recent_days_count=$(jq '.recentDays | length' <<<"$result")
[[ $recent_days_count == "7" ]] || fail "Antigravity scanner recent days length mismatch" "$result"
pass "Antigravity scanner has 7 recent days entries"

today_date=$(date +%Y-%m-%d)
today_msg_count=$(jq --arg date "$today_date" -r '.recentDays[] | select(.date == $date) | .messageCount' <<<"$result")
[[ $today_msg_count == "3" ]] || fail "Antigravity scanner today messageCount mismatch" "$result"
pass "Antigravity scanner recentDays maps today's prompt count"

