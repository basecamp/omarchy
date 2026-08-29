#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3
require_command sqlite3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

database="$TEST_HOME/copilot-state/session-store.db"
mkdir -p "$(dirname "$database")"

python3 - "$database" <<'PY'
import sqlite3
import sys
from datetime import datetime, time, timedelta

database = sys.argv[1]
local_zone = datetime.now().astimezone().tzinfo
today = datetime.now().astimezone().date()

def timestamp(days_ago):
  return datetime.combine(today - timedelta(days=days_ago), time(12), local_zone).isoformat()

connection = sqlite3.connect(database)
connection.execute("""
  CREATE TABLE assistant_usage_events (
    session_id TEXT NOT NULL,
    model TEXT NOT NULL,
    input_tokens INTEGER,
    output_tokens INTEGER,
    cache_read_tokens INTEGER,
    cache_write_tokens INTEGER,
    created_at TEXT
  )
""")
connection.executemany(
  "INSERT INTO assistant_usage_events VALUES (?, ?, ?, ?, ?, ?, ?)",
  [
    ("session-today", "gpt-test", 100, 20, 60, 10, timestamp(0)),
    ("session-today", "gpt-test", 50, 10, 20, 5, timestamp(0)),
    ("session-yesterday", "claude-test", 40, 5, 10, 0, timestamp(1)),
    ("session-old", "gpt-old", 10, 2, 0, 0, timestamp(8)),
    ("session-empty", "gpt-empty", None, None, None, None, timestamp(0)),
  ],
)
connection.commit()
connection.close()
PY

result=$(HOME="$TEST_HOME" COPILOT_HOME="$(dirname "$database")" "$ROOT/bin/omarchy-agent-usage-copilot")

[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + (.hasPromptStats | tostring)' <<<"$result") == "copilot:true:true" ]] ||
  fail "Copilot collector reads its local usage database" "$result"
pass "Copilot collector reads its local usage database"

[[ $(jq -c '{todayPrompts, todaySessions, todayTotalTokens, totalPrompts, totalSessions, activeDays}' <<<"$result") == \
  '{"todayPrompts":2,"todaySessions":1,"todayTotalTokens":180,"totalPrompts":4,"totalSessions":3,"activeDays":3}' ]] ||
  fail "Copilot collector aggregates prompts, sessions, days, and tokens" "$result"
pass "Copilot collector aggregates prompts, sessions, days, and tokens"

[[ $(jq -c '.modelUsage["gpt-test"]' <<<"$result") == \
  '{"inputTokens":55,"outputTokens":30,"cacheReadInputTokens":80,"cacheCreationInputTokens":15}' ]] ||
  fail "Copilot collector separates fresh and cached input tokens" "$result"
pass "Copilot collector separates fresh and cached input tokens"

today=$(date +%Y-%m-%d)
yesterday=$(date -d yesterday +%Y-%m-%d)
[[ $(jq -r --arg day "$today" '.recentDays[] | select(.date == $day) | .messageCount' <<<"$result") == "180" ]] &&
  [[ $(jq -r --arg day "$yesterday" '.recentDays[] | select(.date == $day) | .messageCount' <<<"$result") == "45" ]] ||
  fail "Copilot collector builds the seven-day usage series" "$result"
pass "Copilot collector builds the seven-day usage series"

missing=$(HOME="$TEST_HOME/missing" "$ROOT/bin/omarchy-agent-usage-copilot" --force --limits-only)
[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + (.totalPrompts | tostring)' <<<"$missing") == "copilot:false:0" ]] ||
  fail "Copilot collector prints a hidden record before first use" "$missing"
pass "Copilot collector prints a hidden record before first use"

malformed="$TEST_HOME/malformed.db"
sqlite3 "$malformed" "CREATE TABLE unrelated (id INTEGER);"
broken=$("$ROOT/bin/omarchy-agent-usage-copilot" --database "$malformed" 2>/dev/null)
[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + .usageStatusText' <<<"$broken") == \
  "copilot:false:GitHub Copilot usage unavailable" ]] ||
  fail "Copilot collector handles an incompatible database" "$broken"
pass "Copilot collector handles an incompatible database"
