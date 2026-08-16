#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/bin" "$TEST_HOME/.local/share/opencode"

# A key in the opencode auth store, and a usage endpoint served from a file so
# the limits probe needs no network.
cat >"$TEST_HOME/.local/share/opencode/auth.json" <<'EOF'
{"opencode-go": {"type": "api", "key": "sk-test"}}
EOF
cat >"$TEST_HOME/usage.json" <<'EOF'
{"usage":{"rolling":{"status":"ok","percent":1,"resetsAt":"2026-08-16T11:43:04.949Z"},"weekly":{"status":"ok","percent":14,"resetsAt":"2026-08-17T00:00:00.949Z"},"monthly":{"status":"ok","percent":7,"resetsAt":"2026-09-12T09:44:39.949Z"}}}
EOF

python3 - "$TEST_HOME/.local/share/opencode/opencode.db" <<'PY'
import json
import sqlite3
import sys
import time
from pathlib import Path

db = Path(sys.argv[1])
db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now_ms = int(time.time() * 1000)

def message(id, provider, model, session="ses_1", role="assistant", input=0, output=0, reasoning=0, read=0, write=0):
  return (id, session, now_ms, now_ms, json.dumps({
    "role": role,
    "providerID": provider,
    "modelID": model,
    "tokens": {"input": input, "output": output, "reasoning": reasoning, "cache": {"read": read, "write": write}},
    "time": {"created": now_ms},
  }))

conn.executemany("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [
  message("msg_1", "opencode-go", "deepseek-v4-flash", input=80, output=40, reasoning=5, read=30),
  message("msg_2", "opencode-go", "deepseek-v4-flash", session="ses_2", input=10, output=2),
  message("msg_3", "opencode", "deepseek-v4-flash-free", input=999, output=999),
  message("msg_4", "openai", "gpt-5.2-codex", input=999, output=999),
  message("msg_5", "opencode-go", "deepseek-v4-flash", role="user"),
])
conn.execute("INSERT INTO message VALUES ('msg_6', 'ses_1', ?, ?, '[\"not\",\"an\",\"object\"]')", (now_ms, now_ms))
conn.commit()
conn.close()
PY

result=$(HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/.local/share" \
  OPENCODE_GO_USAGE_URL="file://$TEST_HOME/usage.json" \
  "$ROOT/bin/omarchy-agent-usage-opencode" --force)

[[ $(jq -c '.id + "/" + .name + "/" + (.hasLocalStats|tostring)' <<<"$result") == '"opencode-go/OpenCode Go/true"' ]] ||
  fail "OpenCode Go collector identifies itself" "$result"
pass "OpenCode Go collector identifies itself"

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "167" ]] ||
  fail "OpenCode Go collector counts only its own provider, reasoning included" "$result"
pass "OpenCode Go collector counts only its own provider, reasoning included"

[[ $(jq -c '.modelUsage' <<<"$result") == '{"deepseek-v4-flash":{"inputTokens":90,"outputTokens":47,"cacheReadInputTokens":30,"cacheCreationInputTokens":0}}' ]] ||
  fail "OpenCode Go collector ignores other providers, user messages, and malformed rows" "$result"
pass "OpenCode Go collector ignores other providers, user messages, and malformed rows"

[[ $(jq -c '.todaySessions' <<<"$result") == "2" ]] ||
  fail "OpenCode Go collector counts sessions across messages" "$result"
pass "OpenCode Go collector counts sessions across messages"

[[ $(jq -c '(.tierLabel|tostring) + "/" + ((.limits|length)|tostring)' <<<"$result") == '"Go/3"' ]] ||
  fail "OpenCode Go collector reads its plan and three limit windows" "$result"
pass "OpenCode Go collector reads its plan and three limit windows"

[[ $(jq -c '.limits' <<<"$result") == '[{"label":"Session (5-hour)","percent":0.01,"resetsAt":"2026-08-16T11:43:04.949Z"},{"label":"Weekly (7-day)","percent":0.14,"resetsAt":"2026-08-17T00:00:00.949Z"},{"label":"Monthly","percent":0.07,"resetsAt":"2026-09-12T09:44:39.949Z"}]' ]] ||
  fail "OpenCode Go collector maps rolling/weekly/monthly onto the panel's windows" "$result"
pass "OpenCode Go collector maps rolling/weekly/monthly onto the panel's windows"

[[ $(jq -r '(.ready|tostring) + "/" + (.usageStatusText|tostring)' <<<"$result") == "true/" ]] ||
  fail "OpenCode Go collector stays ready with no status note when limits resolve" "$result"
pass "OpenCode Go collector stays ready with no status note when limits resolve"

# Without a reachable endpoint the record keeps local stats, reports empty
# limits, and says what is missing instead of hiding.
OFFLINE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OFFLINE_HOME"' EXIT
mkdir -p "$OFFLINE_HOME/bin"

offline=$(HOME="$OFFLINE_HOME" XDG_DATA_HOME="$OFFLINE_HOME/.local/share" \
  OPENCODE_GO_USAGE_URL="file:///nonexistent" \
  "$ROOT/bin/omarchy-agent-usage-opencode" --force)

[[ $(jq -c '(.limits|tostring) + "/" + .usageStatusText' <<<"$offline") == '"[]/OpenCode Go limits unavailable"' ]] ||
  fail "OpenCode Go collector reports empty limits and a status note when offline" "$offline"
pass "OpenCode Go collector reports empty limits and a status note when offline"

# A warm cache makes --limits-only cheap and --force bypasses it: without the
# flag the record can reuse the last scan instead of walking the database.
FRESH_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$FRESH_HOME"' EXIT

cached=$(HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  OPENCODE_GO_USAGE_URL="file://$TEST_HOME/usage.json" \
  "$ROOT/bin/omarchy-agent-usage-opencode" --limits-only)
forced=$(HOME="$FRESH_HOME" XDG_DATA_HOME="$FRESH_HOME/.local/share" XDG_CACHE_HOME="$FRESH_HOME/.cache" \
  OPENCODE_GO_USAGE_URL="file://$TEST_HOME/usage.json" \
  "$ROOT/bin/omarchy-agent-usage-opencode" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$cached") == "167" ]] ||
  fail "OpenCode Go collector serves warm-cache limits-only stats" "$cached"
pass "OpenCode Go collector serves warm-cache limits-only stats"

[[ $(jq -r '.todayTotalTokens' <<<"$forced") == "0" ]] ||
  fail "OpenCode Go collector's --force scan respects a fresh data home" "$forced"
pass "OpenCode Go collector's --force scan respects a fresh data home"
