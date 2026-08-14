#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.hermes"

# A Hermes state.db with the session columns the collector reads: roots vs
# children (compression continuations, delegates), archived rows, and empty
# sessions must all behave the way Hermes' own usage totals treat them.
python3 - "$TEST_HOME/.hermes/state.db" <<'PY'
import sqlite3
import sys
import time
from datetime import datetime

db = sqlite3.connect(sys.argv[1])
db.execute("""
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  source TEXT NOT NULL,
  model TEXT,
  parent_session_id TEXT,
  started_at REAL NOT NULL,
  message_count INTEGER DEFAULT 0,
  input_tokens INTEGER DEFAULT 0,
  output_tokens INTEGER DEFAULT 0,
  cache_read_tokens INTEGER DEFAULT 0,
  cache_write_tokens INTEGER DEFAULT 0,
  reasoning_tokens INTEGER DEFAULT 0,
  api_call_count INTEGER DEFAULT 0,
  archived INTEGER NOT NULL DEFAULT 0
)""")
now = time.time()
today = datetime.fromtimestamp(now)
yesterday = datetime.fromtimestamp(now - 86400)

# today: 3 API calls, cached + write + reasoning
db.execute("INSERT INTO sessions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", (
  "root_today", "cli", "nousresearch/hermes-4-405b", None,
  today.timestamp(), 10, 100, 20, 30, 5, 8, 3, 0))
# yesterday: another model with a provider prefix, 2 API calls
db.execute("INSERT INTO sessions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", (
  "root_yesterday", "cli", "provider-prefix/hermes-3-70b", None,
  yesterday.timestamp(), 5, 300, 50, 0, 0, 12, 2, 0))
# child of a root: implementation detail, must not count
db.execute("INSERT INTO sessions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", (
  "child", "cli", "nousresearch/hermes-4-405b", "root_today",
  today.timestamp(), 3, 999, 999, 0, 0, 0, 1, 0))
# archived: must not count
db.execute("INSERT INTO sessions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", (
  "archived", "cli", "nousresearch/hermes-4-405b", None,
  today.timestamp(), 9, 999, 999, 0, 0, 0, 9, 1))
# no messages: must not count
db.execute("INSERT INTO sessions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", (
  "empty", "cli", "nousresearch/hermes-4-405b", None,
  today.timestamp(), 0, 0, 0, 0, 0, 0, 0, 0))
db.commit()
db.close()
PY

result=$(HOME="$TEST_HOME" HERMES_HOME="$TEST_HOME/.hermes" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  XDG_DATA_HOME="$TEST_HOME/.local/share" "$ROOT/bin/omarchy-agent-usage-hermes")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "163" ]] ||
  fail "Hermes collector totals today's input, output, and cache tokens once" "$result"
pass "Hermes collector totals today's input, output, and cache tokens once"

# 100 input + 30 cached + 5 write + 20 output + 8 reasoning, from today's root.
[[ $(jq -c '.modelUsage["hermes-4-405b"]' <<<"$result") == '{"inputTokens":100,"outputTokens":28,"cacheReadInputTokens":30,"cacheCreationInputTokens":5}' ]] ||
  fail "Hermes collector folds reasoning into output and keeps cache separate" "$result"
pass "Hermes collector folds reasoning into output and keeps cache separate"

# Provider prefixes are stripped from model ids, like the Hermes dashboard.
[[ $(jq -c '.modelUsage["hermes-3-70b"]' <<<"$result") == '{"inputTokens":300,"outputTokens":62,"cacheReadInputTokens":0,"cacheCreationInputTokens":0}' ]] ||
  fail "Hermes collector strips provider prefixes from model names" "$result"
pass "Hermes collector strips provider prefixes from model names"

# Each API call is a prompt; sessions without a count still count once.
[[ $(jq -r '.todayPrompts' <<<"$result") == "3" ]] ||
  fail "Hermes collector counts today's API calls as prompts" "$result"
[[ $(jq -r '.totalPrompts' <<<"$result") == "5" ]] ||
  fail "Hermes collector counts each API call once across all time" "$result"
pass "Hermes collector counts API calls as prompts"

[[ $(jq -r '.todaySessions' <<<"$result") == "1" ]] ||
  fail "Hermes collector counts one session started today" "$result"
[[ $(jq -r '.totalSessions' <<<"$result") == "2" ]] ||
  fail "Hermes collector excludes child, archived, and empty sessions" "$result"
pass "Hermes collector excludes child, archived, and empty sessions"

[[ $(jq -r '.activeDays' <<<"$result") == "2" ]] ||
  fail "Hermes collector counts distinct active days" "$result"
[[ $(jq -r '.activeDates[0]' <<<"$result") == "$(date -d yesterday +%Y-%m-%d)" ]] ||
  fail "Hermes collector attributes sessions to their start day" "$result"
pass "Hermes collector attributes sessions to their start day"

[[ $(jq -r '.recentDays[-1].messageCount' <<<"$result") == "163" ]] ||
  fail "Hermes collector builds the seven-day token series" "$result"
pass "Hermes collector builds the seven-day token series"

# Without a state.db the collector still prints a complete, hidden record.
empty=$(HOME="$TEST_HOME" HERMES_HOME="$TEST_HOME/none" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  XDG_DATA_HOME="$TEST_HOME/.local/share" "$ROOT/bin/omarchy-agent-usage-hermes")
[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + (.todayTotalTokens | tostring)' <<<"$empty") == "hermes:true:0" ]] ||
  fail "Hermes collector prints a valid record without a session store" "$empty"
pass "Hermes collector prints a valid record without a session store"

# The cache reuses a scan for --limits-only, and --force bypasses it. Hermes
# has no limits endpoint, so both flags only affect the local-stats scan.
cache_home=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$cache_home"' EXIT
cp "$TEST_HOME/.hermes/state.db" "$cache_home/state.db"

python3 - "$cache_home/state.db" <<'PY'
import sqlite3
import sys
import time
from datetime import datetime

db = sqlite3.connect(sys.argv[1])
now = time.time()
db.execute("INSERT INTO sessions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", (
  "new_root", "cli", "nousresearch/hermes-4-405b", None,
  now, 2, 10, 0, 0, 0, 0, 1, 0))
db.commit()
db.close()
PY

result=$(HOME="$cache_home" HERMES_HOME="$cache_home" XDG_CACHE_HOME="$cache_home/.cache" \
  XDG_DATA_HOME="$cache_home/.local/share" "$ROOT/bin/omarchy-agent-usage-hermes")
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "173" ]] ||
  fail "Hermes collector writes a fresh local-stats cache on first scan" "$result"
pass "Hermes collector writes a local-stats cache on first scan"

# A new session after the scan changes what a fresh scan would find;
# --limits-only must reuse the cached stats instead of rescanning.
python3 - "$cache_home/state.db" <<'PY'
import sqlite3
import sys
import time

db = sqlite3.connect(sys.argv[1])
now = time.time()
db.execute("INSERT INTO sessions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", (
  "later_root", "cli", "nousresearch/hermes-4-405b", None,
  now, 1, 10, 0, 0, 0, 0, 1, 0))
db.commit()
db.close()
PY

result=$(HOME="$cache_home" HERMES_HOME="$cache_home" XDG_CACHE_HOME="$cache_home/.cache" \
  XDG_DATA_HOME="$cache_home/.local/share" "$ROOT/bin/omarchy-agent-usage-hermes" --limits-only)
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "173" ]] ||
  fail "Hermes collector --limits-only reuses cached local stats" "$result"
pass "Hermes collector --limits-only reuses cached local stats"

# --force must ignore the cache and pick up the new session.
result=$(HOME="$cache_home" HERMES_HOME="$cache_home" XDG_CACHE_HOME="$cache_home/.cache" \
  XDG_DATA_HOME="$cache_home/.local/share" "$ROOT/bin/omarchy-agent-usage-hermes" --force)
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "183" ]] ||
  fail "Hermes collector --force rescans past the cache" "$result"
pass "Hermes collector --force rescans past the cache"

# A corrupted cache is a miss: rescan and rewrite instead of a garbage record.
cache_file=$(ls "$cache_home/.cache/omarchy/agent-usage/"/hermes-scan-*.json 2>/dev/null | head -n 1)
[[ -n $cache_file && -s $cache_file ]] ||
  fail "Hermes collector leaves a cache file behind" "$result"
[[ $(stat -c %a "$cache_file") == "644" ]] ||
  fail "Hermes collector keeps cache files readable" "$result"
printf '[]' >"$cache_file"
result=$(HOME="$cache_home" HERMES_HOME="$cache_home" XDG_CACHE_HOME="$cache_home/.cache" \
  XDG_DATA_HOME="$cache_home/.local/share" "$ROOT/bin/omarchy-agent-usage-hermes")
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "183" ]] ||
  fail "Hermes collector recovers from a corrupt cache file" "$result"
pass "Hermes collector recovers from a corrupt cache file"
