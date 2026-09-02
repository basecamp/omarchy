#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.copilot/session-state" "$TEST_HOME/.config/omarchy/agents" "$TEST_HOME/.cache"

now=$(date -u +%Y-%m-%d)T12:00:00Z
today=$(date +%F)

# The session store carries one row per billed assistant request.
python3 - "$TEST_HOME/.copilot/session-store.db" "$now" <<'PY'
import sqlite3
import sys

db = sys.argv[1]
stamp = sys.argv[2]
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE assistant_usage_events (id TEXT PRIMARY KEY, session_id TEXT, created_at TEXT, model TEXT, total_nano_aiu INTEGER, input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER, cache_write_tokens INTEGER, reasoning_tokens INTEGER, duration_ms INTEGER)")
conn.executemany(
  "INSERT INTO assistant_usage_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
  [
    ("e1", "sess-a", stamp, "claude-sonnet-4-5", 500_000_000, 1200, 300, 400, 0, 50, 3000),
    ("e2", "sess-a", stamp, "claude-sonnet-4-5", 500_000_000, 800, 200, 100, 0, 0, 2000),
    ("e3", "sess-b", stamp, "gpt-5.2", 500_000_000, 1500, 700, 100, 300, 100, 5000),
  ],
)
conn.commit()
conn.close()
PY

printf '{"plan": "pro", "remote": false}' >"$TEST_HOME/.config/omarchy/agents/copilot.json"

run_collector() {
  HOME="$TEST_HOME" COPILOT_HOME="$TEST_HOME/.copilot" XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" "$ROOT/bin/omarchy-agent-usage-copilot" "$@"
}

result=$(run_collector --force --copilot-home "$TEST_HOME/.copilot")

[[ $(jq -r '.id' <<<"$result") == "copilot" ]] ||
  fail "Copilot collector identifies itself" "$result"
pass "Copilot collector identifies itself"

[[ $(jq -r '.ready' <<<"$result") == "true" ]] ||
  fail "Copilot collector is ready with usage" "$result"
pass "Copilot collector is ready with usage"

[[ $(jq -r '.todayPrompts' <<<"$result") == "3" ]] ||
  fail "Copilot collector counts billed requests" "$result"
pass "Copilot collector counts billed requests"

[[ $(jq -r '.todaySessions' <<<"$result") == "2" ]] ||
  fail "Copilot collector counts distinct sessions" "$result"
pass "Copilot collector counts distinct sessions"

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "5750" ]] ||
  fail "Copilot collector sums tokens from the store" "$result"
pass "Copilot collector sums tokens from the store"

[[ $(jq -c '.modelUsage["claude-sonnet-4-5"]' <<<"$result") == '{"inputTokens":2000,"outputTokens":550,"cacheReadInputTokens":500,"cacheCreationInputTokens":0}' ]] ||
  fail "Copilot collector folds reasoning tokens into output" "$result"
pass "Copilot collector folds reasoning tokens into output"

[[ $(jq -c '.modelUsage["gpt-5.2"]' <<<"$result") == '{"inputTokens":1500,"outputTokens":800,"cacheReadInputTokens":100,"cacheCreationInputTokens":300}' ]] ||
  fail "Copilot collector reads the cache split" "$result"
pass "Copilot collector reads the cache split"

[[ $(jq -r '.recentDays[-1].date' <<<"$result") == "$today" ]] ||
  fail "Copilot collector reports today's day row" "$result"
pass "Copilot collector reports today's day row"

[[ $(jq -r '.tierLabel' <<<"$result") == "Pro" ]] ||
  fail "Copilot collector exposes the configured plan label" "$result"
pass "Copilot collector exposes the configured plan label"

[[ $(jq -r '.limits[0].label' <<<"$result") == "Monthly allowance (est.)" ]] ||
  fail "Copilot collector labels the local estimate" "$result"
pass "Copilot collector labels the local estimate"

[[ $(jq -r '.limits[0].percent' <<<"$result") == "0.001" ]] ||
  fail "Copilot collector divides month credits by allowance" "$result"
pass "Copilot collector divides month credits by allowance"

[[ $(jq -r '.limits[0].resetsAt' <<<"$result") != "" ]] ||
  fail "Copilot collector sets an allowance reset time" "$result"
pass "Copilot collector sets an allowance reset time"

# A machine that never ran the CLI reports nothing and stays hidden: no meter,
# no ready.
EMPTY_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME"' EXIT
mkdir -p "$EMPTY_HOME/.config/omarchy/agents"
printf '{"plan": "pro", "remote": false}' >"$EMPTY_HOME/.config/omarchy/agents/copilot.json"

result=$(HOME="$EMPTY_HOME" COPILOT_HOME="$EMPTY_HOME/.copilot" XDG_CONFIG_HOME="$EMPTY_HOME/.config" \
  XDG_CACHE_HOME="$EMPTY_HOME/.cache" "$ROOT/bin/omarchy-agent-usage-copilot" --force)

[[ $(jq -r '.ready' <<<"$result") == "false" && $(jq -c '.limits' <<<"$result") == "[]" ]] ||
  fail "Copilot collector stays hidden on a clean machine" "$result"
pass "Copilot collector stays hidden on a clean machine"
