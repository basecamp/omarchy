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
[[ $(jq -c '.modelUsage["glm-5-2"]' <<<"$result") == '{"cacheCreationInputTokens":0,"cacheReadInputTokens":110,"inputTokens":230,"outputTokens":35}' ]] ||
  fail "Devin collector aggregates glm-5-2 model usage" "$result"
[[ $(jq -c '.modelUsage["devin-pro"]' <<<"$result") == '{"cacheCreationInputTokens":10,"cacheReadInputTokens":0,"inputTokens":200,"outputTokens":40}' ]] ||
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
[[ $(jq -r '.authHelpText' <<<"$result") != "" ]] ||
  fail "Devin collector shows install hint for missing database" "$result"
pass "Devin collector reports missing database gracefully"

# Caching: a second run without --force should reuse the cached scan
# (rebuild the DB since we deleted it above)
mkdir -p "$DEVIN_DATA_DIR"
python3 - "$DEVIN_DATA_DIR/sessions.db" "$now" <<'PY'
import json, sqlite3, sys
db_path, now = sys.argv[1], int(sys.argv[2])
conn = sqlite3.connect(db_path)
conn.execute("CREATE TABLE message_nodes (row_id INTEGER PRIMARY KEY, session_id TEXT, node_id INTEGER, chat_message TEXT, created_at INTEGER, metadata TEXT)")
conn.execute("CREATE TABLE prompt_history (id INTEGER PRIMARY KEY, content TEXT, timestamp INTEGER, session_id TEXT, is_shell INTEGER)")
conn.execute("INSERT INTO message_nodes (session_id, node_id, chat_message, created_at) VALUES ('s1', 1, ?, ?)",
             (json.dumps({"metadata": {"metrics": {"input_tokens": 10, "output_tokens": 5, "cache_read_tokens": 0, "cache_creation_tokens": 0}, "generation_model": "test"}}), now))
conn.execute("INSERT INTO prompt_history (content, timestamp, session_id, is_shell) VALUES ('hi', ?, 's1', 0)", (now,))
conn.commit()
conn.close()
PY

# First run populates the cache
result1=$(HOME="$TEST_HOME" DEVIN_DATA_DIR="$DEVIN_DATA_DIR" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  "$ROOT/bin/omarchy-agent-usage-devin")
[[ $(jq -r '.todayTotalTokens' <<<"$result1") == "15" ]] ||
  fail "Devin collector first scan populates cache" "$result1"

# Add more data after the cache is written
python3 - "$DEVIN_DATA_DIR/sessions.db" "$now" <<'PY'
import json, sqlite3, sys
db_path, now = sys.argv[1], int(sys.argv[2])
conn = sqlite3.connect(db_path)
conn.execute("INSERT INTO message_nodes (session_id, node_id, chat_message, created_at) VALUES ('s1', 2, ?, ?)",
             (json.dumps({"metadata": {"metrics": {"input_tokens": 100, "output_tokens": 50, "cache_read_tokens": 0, "cache_creation_tokens": 0}, "generation_model": "test"}}), now))
conn.commit()
conn.close()
PY

# Second run without --force should still serve the cached value (15, not 165)
result2=$(HOME="$TEST_HOME" DEVIN_DATA_DIR="$DEVIN_DATA_DIR" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  "$ROOT/bin/omarchy-agent-usage-devin")
[[ $(jq -r '.todayTotalTokens' <<<"$result2") == "15" ]] ||
  fail "Devin collector serves cached scan without --force" "$result2"
pass "Devin collector serves cached scan without --force"

# --force bypasses the cache and sees the new data (165)
result3=$(HOME="$TEST_HOME" DEVIN_DATA_DIR="$DEVIN_DATA_DIR" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  "$ROOT/bin/omarchy-agent-usage-devin" --force)
[[ $(jq -r '.todayTotalTokens' <<<"$result3") == "165" ]] ||
  fail "Devin collector --force rescans past the cache" "$result3"
pass "Devin collector --force rescans past the cache"

# Quota / limits from user-status cache
# Build a minimal protobuf PlanStatus: field 1 (PlanInfo) with field 2 (plan name "Pro"),
# field 14 (daily_remaining_pct=69), field 15 (weekly_remaining_pct=53),
# field 17 (daily_reset_unix), field 18 (weekly_reset_unix)
python3 - "$TEST_HOME/.cache/devin/cli" "$now" <<'PY'
import base64, json, os, struct, sys

cache_dir, now = sys.argv[1], int(sys.argv[2])
os.makedirs(cache_dir, exist_ok=True)

def varint(val):
    out = b""
    while True:
        byte = val & 0x7F
        val >>= 7
        if val:
            out += bytes([byte | 0x80])
        else:
            out += bytes([byte])
            break
    return out

def field(fn, data):
    if isinstance(data, int):
        return varint((fn << 3) | 0) + varint(data)
    return varint((fn << 3) | 2) + varint(len(data)) + data

# PlanInfo: field 2 = "Pro"
plan_info = field(2, b"Pro")
# PlanStatus: field 1 = PlanInfo, field 14 = 69 (remaining), field 15 = 53 (remaining),
#   field 17 = now+3600, field 18 = now+86400*4
plan_status = field(1, plan_info) + field(14, 69) + field(15, 53) + field(17, now + 3600) + field(18, now + 86400 * 4)
# Top-level: field 13 = PlanStatus
payload = field(13, plan_status)

cache = {
    "version": 1,
    "identity_digest": "test123",
    "fetched_at_secs": now,
    "payload": base64.b64encode(payload).decode("ascii"),
}
with open(os.path.join(cache_dir, "user_status.test123.bin"), "w") as f:
    json.dump(cache, f)
PY

result=$(HOME="$TEST_HOME" DEVIN_DATA_DIR="$DEVIN_DATA_DIR" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  "$ROOT/bin/omarchy-agent-usage-devin" --force)
[[ $(jq -r '.tierLabel' <<<"$result") == "Pro" ]] ||
  fail "Devin collector reads plan name from user-status cache" "$result"
[[ $(jq -r '.limits[0].label' <<<"$result") == "Daily" ]] ||
  fail "Devin collector reports daily limit label" "$result"
[[ $(jq -r '.limits[0].percent' <<<"$result") == "0.31" ]] ||
  fail "Devin collector reports daily limit percent (31% used = 69% remaining)" "$result"
[[ $(jq -r '.limits[1].label' <<<"$result") == "Weekly" ]] ||
  fail "Devin collector reports weekly limit label" "$result"
[[ $(jq -r '.limits[1].percent' <<<"$result") == "0.47" ]] ||
  fail "Devin collector reports weekly limit percent (47% used = 53% remaining)" "$result"
pass "Devin collector parses quota from user-status cache"
