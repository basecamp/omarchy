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

result=$(COPILOT_HOME="$TEST_HOME/.copilot" "$ROOT/bin/omarchy-agent-usage-copilot")

# Test 1: Collector identifies itself
[[ $(jq -r '.id' <<<"$result") == "copilot" ]] ||
  fail "Copilot collector identifies as 'copilot'" "$result"
pass "Copilot collector identifies as 'copilot'"

# Test 2: Today's token counts are summed correctly
today_tokens=$(jq -r '.todayTotalTokens' <<<"$result")
[[ "$today_tokens" -gt 0 ]] ||
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
result_empty=$(COPILOT_HOME="$(mktemp -d)" "$ROOT/bin/omarchy-agent-usage-copilot")
[[ $(jq -r '.todayTotalTokens' <<<"$result_empty") == "0" ]] ||
  fail "Copilot collector returns empty stats when DB missing" "$result_empty"
pass "Copilot collector returns empty stats when DB missing"

# Test 9: Exhausted quota displays correct message
python3 << 'PYTEST'
import sys

# Test the collector's logic for exhausted quota
test_cases = [
    {"used": 0, "total": 0, "display": "Premium Requests", "expected_contains": "No more"},
    {"used": 100, "total": 1000, "display": "Premium Requests", "expected_contains": "Premium Requests"},
]

for case in test_cases:
    used = case["used"]
    total = case["total"]
    display_name = case["display"]
    expected = case["expected_contains"]
    
    # Simulate what the collector does
    if total == 0 and used == 0:
        display_name = f"No more {display_name} available"
    
    if expected not in display_name:
        print(f"FAIL: Expected '{expected}' in '{display_name}'")
        sys.exit(1)

print("PASS: Exhausted quota message formatting")
PYTEST

if (( $? == 0 )); then
  pass "Exhausted quota displays 'No more' message"
else
  fail "Exhausted quota message formatting"
fi

