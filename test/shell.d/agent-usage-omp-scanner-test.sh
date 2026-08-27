#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command sqlite3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/bin"

# A stub so a machine with omp installed does not refresh the real stats db.
cat >"$TEST_HOME/bin/omp" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TEST_HOME/bin/omp"
jq_dir=$(dirname "$(command -v jq)")
export PATH="$TEST_HOME/bin:$jq_dir:/usr/bin:/bin"

empty=$(HOME="$TEST_HOME" OMP_HOME="$TEST_HOME/.omp" "$ROOT/bin/omarchy-agent-usage-omp" --force)
[[ $(jq -r '.id + "/" + (.ready|tostring) + "/" + (.totalPrompts|tostring)' <<<"$empty") == "omp/false/0" ]] ||
  fail "OMP collector prints a valid empty record without a stats database" "$empty"
pass "OMP collector prints a valid empty record without a stats database"

mkdir -p "$TEST_HOME/.omp"
today_ms=$(($(date +%s) * 1000))
sqlite3 "$TEST_HOME/.omp/stats.db" <<SQL
CREATE TABLE messages (
  id INTEGER PRIMARY KEY,
  session_file TEXT NOT NULL,
  entry_id TEXT NOT NULL,
  folder TEXT NOT NULL,
  model TEXT NOT NULL,
  provider TEXT NOT NULL,
  api TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  duration INTEGER,
  ttft INTEGER,
  stop_reason TEXT NOT NULL,
  error_message TEXT,
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  cache_read_tokens INTEGER NOT NULL,
  cache_write_tokens INTEGER NOT NULL,
  total_tokens INTEGER NOT NULL,
  premium_requests REAL NOT NULL,
  cost_input REAL NOT NULL,
  cost_output REAL NOT NULL,
  cost_cache_read REAL NOT NULL,
  cost_cache_write REAL NOT NULL,
  cost_total REAL NOT NULL
);
INSERT INTO messages (
  session_file, entry_id, folder, model, provider, api, timestamp, stop_reason,
  input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, total_tokens,
  premium_requests, cost_input, cost_output, cost_cache_read, cost_cache_write, cost_total
) VALUES
  ('sess-a', 'e1', '/tmp', 'gpt-5.6-sol', 'openai-codex', 'openai', $today_ms, 'end_turn',
   10, 4, 20, 1, 35, 0, 0, 0, 0, 0, 0),
  ('sess-a', 'e2', '/tmp', 'gpt-5.6-sol', 'openai-codex', 'openai', $today_ms, 'end_turn',
   5, 2, 0, 0, 7, 0, 0, 0, 0, 0, 0),
  ('sess-b', 'e3', '/tmp', 'grok-4.6', 'xai', 'xai', $today_ms, 'end_turn',
   8, 3, 1, 0, 12, 0, 0, 0, 0, 0, 0);
SQL

result=$(HOME="$TEST_HOME" OMP_HOME="$TEST_HOME/.omp" "$ROOT/bin/omarchy-agent-usage-omp" --force)
[[ $(jq -r '.id + "/" + (.ready|tostring) + "/" + (.todayPrompts|tostring) + "/" + (.todaySessions|tostring)' <<<"$result") == "omp/true/3/2" ]] ||
  fail "OMP collector counts messages and distinct sessions" "$result"
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "54" ]] ||
  fail "OMP collector sums total_tokens" "$result"
[[ $(jq -c '.modelUsage["gpt-5.6-sol"]' <<<"$result") == '{"cacheCreationInputTokens":1,"cacheReadInputTokens":20,"inputTokens":15,"outputTokens":6}' ]] ||
  fail "OMP collector groups tokens by model" "$result"
[[ $(jq -r '.scope + "/" + .tierLabel' <<<"$result") == "device/local" ]] ||
  fail "OMP collector is a local device view without subscription limits" "$result"
[[ $(jq -c '.limits' <<<"$result") == '[]' ]] ||
  fail "OMP collector has no rate-limit meters" "$result"
pass "OMP collector maps stats.db messages into the panel record"
