#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

DEVIN_DATA_DIR="$TEST_HOME/.local/share/devin/cli"
mkdir -p "$DEVIN_DATA_DIR"

now=$(date +%s)
today=$(date +%Y-%m-%d)
yesterday=$(date -d yesterday +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)

# Build a mock sessions.db with the schema the collector expects.
python3 - "$DEVIN_DATA_DIR/sessions.db" "$now" "$today" "$yesterday" <<'PY'
import json, sqlite3, sys

db_path, now, today, yesterday = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]

conn = sqlite3.connect(db_path)
conn.execute("CREATE TABLE message_nodes (row_id INTEGER PRIMARY KEY, session_id TEXT, node_id INTEGER, parent_node_id INTEGER, chat_message TEXT, created_at INTEGER, metadata TEXT)")
conn.execute("CREATE TABLE prompt_history (id INTEGER PRIMARY KEY, content TEXT, timestamp INTEGER, session_id TEXT, is_shell INTEGER)")

def assistant_msg(model, inp, out, cache_read=0, cache_write=0):
    return json.dumps({
        "metadata": {
            "metrics": {
                "input_tokens": inp,
                "output_tokens": out,
                "cache_read_tokens": cache_read,
                "cache_creation_tokens": cache_write,
            },
            "generation_model": model,
        }
    })

# Today: two turns with glm-5-2, one with devin-pro
conn.execute("INSERT INTO message_nodes (session_id, node_id, chat_message, created_at) VALUES (?, 1, ?, ?)",
             ("s1", assistant_msg("glm-5-2", 100, 20, 60, 0), now))
conn.execute("INSERT INTO message_nodes (session_id, node_id, chat_message, created_at) VALUES (?, 2, ?, ?)",
             ("s1", assistant_msg("glm-5-2", 80, 10, 50, 0), now))
conn.execute("INSERT INTO message_nodes (session_id, node_id, chat_message, created_at) VALUES (?, 3, ?, ?)",
             ("s1", assistant_msg("devin-pro", 200, 40, 0, 10), now))

# Yesterday: one turn
conn.execute("INSERT INTO message_nodes (session_id, node_id, chat_message, created_at) VALUES (?, 4, ?, ?)",
             ("s2", assistant_msg("glm-5-2", 50, 5, 0, 0), now - 86400))

# A row with no metrics should be skipped
conn.execute("INSERT INTO message_nodes (session_id, node_id, chat_message, created_at) VALUES (?, 5, ?, ?)",
             ("s1", json.dumps({"metadata": {}}), now))

# Prompt history: 3 prompts today across 2 sessions, 1 yesterday
conn.execute("INSERT INTO prompt_history (content, timestamp, session_id, is_shell) VALUES (?, ?, 's1', 0)", ("hello", now))
conn.execute("INSERT INTO prompt_history (content, timestamp, session_id, is_shell) VALUES (?, ?, 's1', 0)", ("world", now))
conn.execute("INSERT INTO prompt_history (content, timestamp, session_id, is_shell) VALUES (?, ?, 's3', 0)", ("test", now))
conn.execute("INSERT INTO prompt_history (content, timestamp, session_id, is_shell) VALUES (?, ?, 's2', 0)", ("yesterday", now - 86400))

conn.commit()
conn.close()
PY

result=$(HOME="$TEST_HOME" DEVIN_DATA_DIR="$DEVIN_DATA_DIR" \
  "$ROOT/bin/omarchy-agent-usage-devin")

# Today: (100+20+60) + (80+10+50) + (200+40+0+10) = 570
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "570" ]] ||
  fail "Devin collector counts today's tokens across models" "$result"
pass "Devin collector counts today's tokens across models"

# 3 prompts today across 2 sessions
[[ $(jq -r '.todayPrompts' <<<"$result") == "3" ]] ||
  fail "Devin collector counts today's prompts" "$result"
[[ $(jq -r '.todaySessions' <<<"$result") == "2" ]] ||
  fail "Devin collector counts today's sessions" "$result"
pass "Devin collector counts today's prompts and sessions"

# Model usage (all-time): glm-5-2 = (100+80+50) input, (20+10+5) output, (60+50+0) cache_read, 0 cache_write
#                         devin-pro = 200 input, 40 output, 0 cache_read, 10 cache_write
[[ $(jq -c '.modelUsage["glm-5-2"]' <<<"$result") == '{"inputTokens":230,"outputTokens":35,"cacheReadInputTokens":110,"cacheCreationInputTokens":0}' ]] ||
  fail "Devin collector aggregates glm-5-2 model usage" "$result"
[[ $(jq -c '.modelUsage["devin-pro"]' <<<"$result") == '{"inputTokens":200,"outputTokens":40,"cacheReadInputTokens":0,"cacheCreationInputTokens":10}' ]] ||
  fail "Devin collector aggregates devin-pro model usage" "$result"
pass "Devin collector aggregates model usage correctly"

# Total prompts = 4 (3 today + 1 yesterday), total sessions = 3 (s1, s2, s3)
[[ $(jq -r '.totalPrompts' <<<"$result") == "4" ]] ||
  fail "Devin collector counts total prompts" "$result"
[[ $(jq -r '.totalSessions' <<<"$result") == "3" ]] ||
  fail "Devin collector counts total sessions" "$result"
pass "Devin collector counts total prompts and sessions"

# Active days = 2 (today + yesterday)
[[ $(jq -r '.activeDays' <<<"$result") == "2" ]] ||
  fail "Devin collector counts active days" "$result"
pass "Devin collector counts active days"

# Recent days: today should have 570, yesterday should have 55 (50+5)
[[ $(jq -r '[.recentDays[] | select(.date == "'$today'") | .messageCount] | .[0]' <<<"$result") == "570" ]] ||
  fail "Devin collector fills today's recent day" "$result"
[[ $(jq -r '[.recentDays[] | select(.date == "'$yesterday'") | .messageCount] | .[0]' <<<"$result") == "55" ]] ||
  fail "Devin collector fills yesterday's recent day" "$result"
pass "Devin collector fills the seven-day token series"

# No limits
[[ $(jq -c '.limits' <<<"$result") == "[]" ]] ||
  fail "Devin collector reports no limits" "$result"
pass "Devin collector reports no limits"

# Identifies itself
[[ $(jq -r '.id' <<<"$result") == "devin" ]] ||
  fail "Devin collector identifies itself" "$result"
[[ $(jq -r '.name' <<<"$result") == "Devin" ]] ||
  fail "Devin collector names itself" "$result"
pass "Devin collector identifies itself"

# Missing database
rm "$DEVIN_DATA_DIR/sessions.db"
result=$(HOME="$TEST_HOME" DEVIN_DATA_DIR="$DEVIN_DATA_DIR" \
  "$ROOT/bin/omarchy-agent-usage-devin")
[[ $(jq -r '.usageStatusText' <<<"$result") == "Devin CLI not installed" ]] ||
  fail "Devin collector reports missing database" "$result"
pass "Devin collector reports missing database gracefully"
