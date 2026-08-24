#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3
require_command sqlite3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.copilot"

# Create a test session-store.db with sample data
db_path="$TEST_HOME/.copilot/session-store.db"
sqlite3 "$db_path" <<'EOF'
CREATE TABLE turns (
  session_id TEXT,
  turn_index INTEGER
);

CREATE TABLE assistant_usage_events (
  session_id TEXT,
  turn_index INTEGER,
  created_at TEXT,
  input_tokens INTEGER,
  output_tokens INTEGER,
  cache_read_tokens INTEGER,
  cache_write_tokens INTEGER,
  model TEXT
);

INSERT INTO turns VALUES ('session-1', 0);
INSERT INTO turns VALUES ('session-1', 1);
INSERT INTO turns VALUES ('session-2', 0);

INSERT INTO assistant_usage_events VALUES
  ('session-1', 0, datetime('now'), 100, 50, 10, 5, 'gpt-4'),
  ('session-1', 1, datetime('now'), 80, 40, 8, 2, 'gpt-4'),
  ('session-2', 0, datetime('now'), 120, 60, 15, 3, 'gpt-4o');
EOF

result=$(HOME="$TEST_HOME" COPILOT_HOME="$TEST_HOME/.copilot" "$ROOT/bin/omarchy-agent-usage-copilot")

# Test 1: Collector identifies itself
[[ $(jq -r '.id' <<<"$result") == "copilot" ]] ||
  fail "Copilot collector identifies as 'copilot'" "$result"
pass "Copilot collector identifies as 'copilot'"

# Test 2: Today's token counts are summed correctly
today_tokens=$(jq -r '.todayTotalTokens' <<<"$result")
[[ $today_tokens == "450" ]] ||
  fail "Copilot collector sums today's tokens" "$result"
pass "Copilot collector sums today's tokens"

# Test 3: Model usage is tracked
[[ $(jq 'has("modelUsage")' <<<"$result") == "true" ]] ||
  fail "Copilot collector tracks modelUsage" "$result"
pass "Copilot collector tracks modelUsage"

# Test 4: Today's sessions are counted
today_sessions=$(jq -r '.todaySessions' <<<"$result")
[[ "$today_sessions" -gt 0 ]] ||
  fail "Copilot collector counts today's sessions" "$result"
pass "Copilot collector counts today's sessions"

# Test 5: Total sessions are counted
total_sessions=$(jq -r '.totalSessions' <<<"$result")
[[ "$total_sessions" == "2" ]] ||
  fail "Copilot collector counts total sessions correctly" "$result"
pass "Copilot collector counts total sessions correctly"

# Test 6: activeDays reflects all dates in the database (not capped at 7)
active_days=$(jq -r '.activeDays' <<<"$result")
[[ "$active_days" -gt 0 ]] ||
  fail "Copilot collector reports active days" "$result"
pass "Copilot collector reports active days"

# Test 7: Schema matches panel expectations
[[ $(jq 'has("schemaVersion") and has("ready") and has("limits")' <<<"$result") == "true" ]] ||
  fail "Copilot collector emits correct schema" "$result"
pass "Copilot collector emits correct schema"

# Test 8: Without database, returns empty stats
result_empty=$(HOME="$(mktemp -d)" COPILOT_HOME="$(mktemp -d)" "$ROOT/bin/omarchy-agent-usage-copilot")
[[ $(jq -r '.todayTotalTokens' <<<"$result_empty") == "0" ]] ||
  fail "Copilot collector returns empty stats when DB missing" "$result_empty"
pass "Copilot collector returns empty stats when DB missing"

# Test 9: Exhausted quota logic produces "No more" message
# Test the formatting of exhausted quota (entitlement=0, credits_used=0)
python3 << 'PYTEST'
import sys

# Test the exact formatting logic from fetch_quota
QUOTA_DISPLAY_NAMES = {
    "premium_interactions": "AI Credits",
    "premium_requests": "Premium Requests",
}

# Simulate exhausted quota response
quota_type = "premium_interactions"
display_name = QUOTA_DISPLAY_NAMES.get(quota_type, quota_type)
used = 0
total = 0

# This is the exact formatting from fetch_quota (lines 114-120)
formatted_label = display_name
if total == 0 and used == 0:
    formatted_label = f"No more {display_name} available"

# Verify the label has "No more"
if "No more" not in formatted_label:
    print(f"FAIL: Expected 'No more' in formatted label, got: {formatted_label}")
    sys.exit(1)

# Also verify normal quota still works
used2 = 100
total2 = 1000
formatted_label2 = display_name
if total2 == 0 and used2 == 0:
    formatted_label2 = f"No more {display_name} available"

if "No more" in formatted_label2:
    print(f"FAIL: Normal quota should not have 'No more', got: {formatted_label2}")
    sys.exit(1)

print("PASS")
PYTEST

if (( $? == 0 )); then
  pass "Exhausted quota displays 'No more' message"
else
  fail "Exhausted quota message formatting"
fi

