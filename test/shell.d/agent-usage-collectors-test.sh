#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3
require_command sqlite3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# 1. Test Antigravity Collector
brain_dir="$TEST_HOME/.gemini/antigravity/brain/session-1/.system_generated/logs"
mkdir -p "$brain_dir"

cat >"$brain_dir/transcript.jsonl" <<'INNER_EOF'
{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","content":"test prompt"}
{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","content":"test response text for 100 tokens"}
INNER_EOF

res_antigravity=$(HOME="$TEST_HOME" "$ROOT/bin/omarchy-agent-usage-antigravity")

[[ $(jq -r '.id' <<<"$res_antigravity") == "antigravity" ]] ||
  fail "Antigravity collector returns id 'antigravity'" "$res_antigravity"
pass "Antigravity collector returns id 'antigravity'"

[[ $(jq -r '.ready' <<<"$res_antigravity") == "true" ]] ||
  fail "Antigravity collector reports ready true" "$res_antigravity"
pass "Antigravity collector reports ready true"

[[ $(jq -r '.hasLocalStats' <<<"$res_antigravity") == "true" ]] ||
  fail "Antigravity collector reports hasLocalStats true" "$res_antigravity"
pass "Antigravity collector reports hasLocalStats true"


# 2. Test OpenCode Collector
opencode_dir="$TEST_HOME/.local/share/opencode"
mkdir -p "$opencode_dir"

sqlite3 "$opencode_dir/opencode.db" <<'SQL'
CREATE TABLE session (
  id TEXT PRIMARY KEY,
  model TEXT,
  tokens_input INTEGER,
  tokens_output INTEGER,
  tokens_reasoning INTEGER,
  tokens_cache_read INTEGER,
  time_created INTEGER
);
CREATE TABLE message (
  id TEXT PRIMARY KEY,
  role TEXT
);
INSERT INTO session VALUES ('ses_1', '{"id":"big-pickle"}', 100, 50, 0, 0, strftime('%s', 'now') * 1000);
INSERT INTO message VALUES ('msg_1', 'user');
SQL

res_opencode=$(HOME="$TEST_HOME" "$ROOT/bin/omarchy-agent-usage-opencode")

[[ $(jq -r '.id' <<<"$res_opencode") == "opencode" ]] ||
  fail "OpenCode collector returns id 'opencode'" "$res_opencode"
pass "OpenCode collector returns id 'opencode'"

[[ $(jq -r '.ready' <<<"$res_opencode") == "true" ]] ||
  fail "OpenCode collector reports ready true" "$res_opencode"
pass "OpenCode collector reports ready true"

[[ $(jq -r '.todayTotalTokens' <<<"$res_opencode") == "150" ]] ||
  fail "OpenCode collector sums tokens from SQLite correctly" "$res_opencode"
pass "OpenCode collector sums tokens from SQLite correctly"
