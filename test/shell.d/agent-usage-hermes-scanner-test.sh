#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# No Hermes install: still print a full, hidden-by-default record so the
# updater can write valid JSON without failing the other collectors.
empty=$(HOME="$TEST_HOME" "$ROOT/bin/omarchy-agent-usage-hermes")
[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + (.hasLocalStats | tostring)' <<<"$empty") == "hermes:false:false" ]] ||
  fail "Hermes collector prints a valid record without a state.db" "$empty"
pass "Hermes collector prints a valid record without a state.db"

[[ $(jq -r '.name' <<<"$empty") == "Hermes Agent" ]] ||
  fail "Hermes collector identifies itself" "$empty"
pass "Hermes collector identifies itself"

python3 - "$TEST_HOME" <<'PY'
import sqlite3
import sys
import time
from pathlib import Path

home = Path(sys.argv[1])
now = time.time()
today = now
week_ago = now - 7 * 24 * 3600

def write_db(path, rows, users):
  path.parent.mkdir(parents=True, exist_ok=True)
  conn = sqlite3.connect(path)
  conn.executescript("""
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      source TEXT NOT NULL,
      started_at REAL NOT NULL,
      last_activity_at REAL,
      message_count INTEGER DEFAULT 0,
      input_tokens INTEGER DEFAULT 0,
      output_tokens INTEGER DEFAULT 0
    );
    CREATE TABLE session_model_usage (
      session_id TEXT NOT NULL,
      model TEXT NOT NULL,
      billing_provider TEXT NOT NULL DEFAULT '',
      billing_base_url TEXT NOT NULL DEFAULT '',
      billing_mode TEXT NOT NULL DEFAULT '',
      task TEXT NOT NULL DEFAULT '',
      api_call_count INTEGER NOT NULL DEFAULT 0,
      input_tokens INTEGER NOT NULL DEFAULT 0,
      output_tokens INTEGER NOT NULL DEFAULT 0,
      cache_read_tokens INTEGER NOT NULL DEFAULT 0,
      cache_write_tokens INTEGER NOT NULL DEFAULT 0,
      reasoning_tokens INTEGER NOT NULL DEFAULT 0,
      estimated_cost_usd REAL NOT NULL DEFAULT 0,
      actual_cost_usd REAL NOT NULL DEFAULT 0,
      first_seen REAL,
      last_seen REAL,
      PRIMARY KEY (session_id, model, billing_provider, billing_base_url, billing_mode, task)
    );
    CREATE TABLE messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      role TEXT NOT NULL,
      content TEXT,
      timestamp REAL NOT NULL,
      active INTEGER NOT NULL DEFAULT 1
    );
  """)
  for session_id, started in {row[0]: row[5] for row in rows}.items():
    conn.execute(
      "INSERT OR IGNORE INTO sessions(id, source, started_at, last_activity_at) VALUES (?, 'cli', ?, ?)",
      (session_id, started, started),
    )
  conn.executemany(
    """INSERT INTO session_model_usage(
         session_id, model, billing_provider, input_tokens, output_tokens,
         cache_read_tokens, cache_write_tokens, reasoning_tokens, last_seen, first_seen
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
    rows,
  )
  conn.executemany(
    "INSERT INTO messages(session_id, role, content, timestamp, active) VALUES (?, 'user', 'hi', ?, 1)",
    users,
  )
  conn.commit()
  conn.close()

write_db(
  home / ".hermes" / "state.db",
  [
    ("ses-default", "grok-4.6", "xai-oauth", 100, 40, 10, 5, 2, today, today),
    ("ses-old", "glm-5.3-flash:cloud", "custom", 50, 10, 0, 0, 0, week_ago, week_ago),
  ],
  [("ses-default", today), ("ses-old", week_ago)],
)
write_db(
  home / ".hermes" / "profiles" / "james" / "state.db",
  [
    ("ses-james", "grok-4.6", "xai-oauth", 20, 8, 0, 0, 0, today, today),
  ],
  [("ses-james", today)],
)
PY

result=$(HOME="$TEST_HOME" "$ROOT/bin/omarchy-agent-usage-hermes" --force --limits-only)

[[ $(jq -r '.ready | tostring' <<<"$result") == "true" ]] ||
  fail "Hermes collector is ready when state.db has usage" "$result"
pass "Hermes collector is ready when state.db has usage"

# today: default 100+40+10+5+2=157 plus profile 20+8=28 → 185
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "185" ]] ||
  fail "Hermes collector sums tokens from default home and profiles" "$result"
pass "Hermes collector sums tokens from default home and profiles"

[[ $(jq -r '.todayPrompts' <<<"$result") == "2" ]] ||
  fail "Hermes collector counts today's user messages" "$result"
[[ $(jq -r '.todaySessions' <<<"$result") == "2" ]] ||
  fail "Hermes collector counts today's sessions" "$result"
pass "Hermes collector counts today's prompts and sessions"

[[ $(jq -c '.modelUsage["grok-4.6"]' <<<"$result") == '{"cacheCreationInputTokens":5,"cacheReadInputTokens":10,"inputTokens":120,"outputTokens":50}' ]] ||
  fail "Hermes collector merges per-model buckets and folds reasoning into output" "$result"
pass "Hermes collector merges per-model buckets and folds reasoning into output"

[[ $(jq -r '.tierLabel' <<<"$result") == "xai-oauth" ]] ||
  fail "Hermes collector labels the dominant billing provider" "$result"
pass "Hermes collector labels the dominant billing provider"

[[ $(jq -r '.limits | length' <<<"$result") == "0" ]] ||
  fail "Hermes collector does not invent rate limits" "$result"
pass "Hermes collector does not invent rate limits"

# A truncated db (no usage table) must not crash the updater.
BROKEN_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$BROKEN_HOME"' EXIT
mkdir -p "$BROKEN_HOME/.hermes"
python3 - "$BROKEN_HOME/.hermes/state.db" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE unrelated (id INTEGER)")
conn.commit()
conn.close()
PY
broken=$(HOME="$BROKEN_HOME" "$ROOT/bin/omarchy-agent-usage-hermes")
[[ $(jq -r '.id + ":" + (.ready | tostring)' <<<"$broken") == "hermes:false" ]] ||
  fail "Hermes collector survives a state.db without usage tables" "$broken"
pass "Hermes collector survives a state.db without usage tables"
