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

# Timestamps are stored in UTC (as the real CLI does); the collector converts
# them to local dates, so all 'now' rows land on today's local date.
INSERT INTO assistant_usage_events VALUES
  ('session-1', 0, datetime('now'), 100, 50, 10, 5, 'gpt-4'),
  ('session-1', 1, datetime('now'), 80, 40, 8, 2, 'gpt-4'),
  ('session-2', 0, datetime('now'), 120, 60, 15, 3, 'gpt-4o'),
  ('session-1', 0, datetime('now', '-8 days'), 50, 25, 5, 2, 'gpt-4');
EOF

result=$(HOME="$TEST_HOME" COPILOT_HOME="$TEST_HOME/.copilot" "$ROOT/bin/omarchy-agent-usage-copilot")

# Test 1: Collector identifies itself
[[ $(jq -r '.id' <<<"$result") == "copilot" ]] ||
  fail "Copilot collector identifies as 'copilot'" "$result"
pass "Copilot collector identifies as 'copilot'"

# Test 2: Today's token counts are summed correctly
# input_tokens in the session store already includes cache read/write tokens,
# so the expected total is input + output only: (100+80+120) + (50+40+60) = 450.
# Adding the cache columns on top would double-count them.
today_tokens=$(jq -r '.todayTotalTokens' <<<"$result")
[[ $today_tokens == "450" ]] ||
  fail "Copilot collector sums today's tokens" "$result"
pass "Copilot collector sums today's tokens"

# Test 3: Model usage is tracked with correct schema
model_usage=$(jq '.todayTokensByModel.["gpt-4"]' <<<"$result")
[[ $(jq -r '.inputTokens' <<<"$model_usage") == "180" ]] ||
  fail "Copilot collector tracks todayTokensByModel with per-model breakdown" "$result"
pass "Copilot collector tracks todayTokensByModel with per-model breakdown"

# Test 4: Today's sessions are counted
today_sessions=$(jq -r '.todaySessions' <<<"$result")
(( today_sessions > 0 )) ||
  fail "Copilot collector counts today's sessions" "$result"
pass "Copilot collector counts today's sessions"

# Test 5: Total sessions are counted
total_sessions=$(jq -r '.totalSessions' <<<"$result")
(( total_sessions == 2 )) ||
  fail "Copilot collector counts total sessions correctly" "$result"
pass "Copilot collector counts total sessions correctly"

# Test 6: activeDays reflects all dates in the database (not capped at 7)
active_days=$(jq -r '.activeDays' <<<"$result")
(( active_days == 2 )) ||
  fail "Copilot collector reports exactly 2 distinct active dates (today + 8 days ago)" "$result"
pass "Copilot collector reports exactly 2 distinct active dates (today + 8 days ago)"

# Test 7: Schema matches panel expectations
[[ $(jq 'has("schemaVersion") and has("ready") and has("limits")' <<<"$result") == "true" ]] ||
  fail "Copilot collector emits correct schema" "$result"
pass "Copilot collector emits correct schema"

# Test 8: Without database, returns empty stats
result_empty=$(HOME="$(mktemp -d)" COPILOT_HOME="$(mktemp -d)" "$ROOT/bin/omarchy-agent-usage-copilot")
[[ $(jq -r '.todayTotalTokens' <<<"$result_empty") == "0" ]] ||
  fail "Copilot collector returns empty stats when DB missing" "$result_empty"
pass "Copilot collector returns empty stats when DB missing"

# Test 9: Exhausted quota end-to-end through real collector
# Mock the API to return exhausted quota, then verify the collector's JSON output
python3 << PYTEST
import sys
import json
import os
from unittest.mock import patch, MagicMock
from io import StringIO

# Set up test environment
os.environ["HOME"] = "$TEST_HOME"
os.environ["COPILOT_HOME"] = "$TEST_HOME/.copilot"

# Create mock OAuth token file in the correct format
os.makedirs("$TEST_HOME/.config/github-copilot", exist_ok=True)
with open("$TEST_HOME/.config/github-copilot/oauth.json", "w") as f:
    json.dump({
        "github.com": {
            "oauth_token": "ghu_fake_token_for_testing"
        }
    }, f)

# Mock the urlopen to return exhausted quota response
# The API returns quota_snapshots as a dict keyed by quota type. Exhaustion is
# a fully consumed positive entitlement with has_quota false, matching the
# endpoint's real semantics.
def mock_urlopen(*args, **kwargs):
    quota_response = {
        "quota_snapshots": {
            "premium_interactions": {
                "quota_type": "premium_interactions",
                "credits_used": 100,
                "entitlement": 100,
                "has_quota": False
            }
        },
        "quota_reset_date_utc": "2026-09-01T00:00:00Z"
    }
    response = MagicMock()
    response.__enter__.return_value.read.return_value = json.dumps(quota_response).encode()
    response.__exit__.return_value = None
    return response

with patch('urllib.request.urlopen', side_effect=mock_urlopen):
    # Read and execute the collector code in this process
    with open("$ROOT/bin/omarchy-agent-usage-copilot") as f:
        collector_code = f.read()
    
    # Remove shebang
    if collector_code.startswith("#!"):
        collector_code = '\n'.join(collector_code.split('\n')[1:])
    
    # Capture stdout
    old_stdout = sys.stdout
    sys.stdout = StringIO()
    
    try:
        # Execute the collector
        exec(collector_code, {'__name__': '__main__'})
        output = sys.stdout.getvalue()
        sys.stdout = old_stdout
        
        # Parse the JSON output
        try:
            result = json.loads(output)
        except json.JSONDecodeError as e:
            print(f"FAIL: Could not parse collector JSON: {e}")
            print(f"Output was: {output}")
            sys.exit(1)
        
        # Verify the exhausted quota message is in the limits label
        if "limits" not in result or len(result["limits"]) == 0:
            print(f"FAIL: No limits in collector output")
            sys.exit(1)
        
        label = result["limits"][0].get("label", "")
        if "No more" not in label:
            print(f"FAIL: Expected 'No more' in exhausted quota label, got: {label}")
            sys.exit(1)
        
        print("PASS")
    finally:
        sys.stdout = old_stdout
PYTEST

if (( $? == 0 )); then
  pass "Exhausted quota displays 'No more' message"
else
  fail "Exhausted quota message formatting"
fi

