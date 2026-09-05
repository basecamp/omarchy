#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# No OpenCode Go subscription is signed in under this fake home, so the
# limits probe stays offline and empty while the local-scan assertions run.
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

def message(id, provider, model, role="assistant", input=0, output=0, reasoning=0, read=0, write=0):
  return (id, "ses_1", now_ms, now_ms, json.dumps({
    "role": role,
    "providerID": provider,
    "modelID": model,
    "tokens": {"input": input, "output": output, "reasoning": reasoning, "cache": {"read": read, "write": write}},
    "time": {"created": now_ms},
  }))

conn.executemany("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [
  message("m1", "opencode-go", "deepseek-v4-pro", input=100, output=40, reasoning=5, read=30),
  message("m2", "opencode-go", "deepseek-v4-flash", input=10, output=2),
  message("m3", "opencode", "deepseek-v4-pro", input=999, output=999),
  message("m4", "opencode-go", "deepseek-v4-pro", role="user"),
  message("m5", "opencode-go-local", "deepseek-v4-pro", input=999, output=999),
])
conn.execute("INSERT INTO message VALUES ('m6', 'ses_1', ?, ?, '[\"not\",\"an\",\"object\"]')", (now_ms, now_ms))
conn.commit()
conn.close()
PY

result=$(HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  "$ROOT/bin/omarchy-agent-usage-opencode-go")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "187" ]] ||
  fail "OpenCode Go collector counts Go usage, reasoning included, from opencode sessions" "$result"
pass "OpenCode Go collector counts Go usage, reasoning included, from opencode sessions"

[[ $(jq -c '.modelUsage' <<<"$result") == '{"deepseek-v4-pro":{"inputTokens":100,"outputTokens":45,"cacheReadInputTokens":30,"cacheCreationInputTokens":0},"deepseek-v4-flash":{"inputTokens":10,"outputTokens":2,"cacheReadInputTokens":0,"cacheCreationInputTokens":0}}' ]] ||
  fail "OpenCode Go collector ignores non-Go providers, user messages, and malformed rows" "$result"
pass "OpenCode Go collector ignores non-Go providers, user messages, and malformed rows"

[[ $(jq -c '.id + "/" + (.limits|tostring)' <<<"$result") == '"opencode-go/[]"' ]] ||
  fail "OpenCode Go collector identifies itself with an empty limits list when unsigned" "$result"
pass "OpenCode Go collector identifies itself with an empty limits list when unsigned"

# A warm cache makes --limits-only cheap: local stats come from the last scan
# instead of another walk over the opencode database.
CACHE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$CACHE_HOME"' EXIT

python3 - "$CACHE_HOME/.local/share/opencode/opencode.db" <<'PY'
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
conn.execute(
  "INSERT INTO message VALUES (?, ?, ?, ?, ?)",
  ("c1", "ses_1", now_ms, now_ms, json.dumps({
    "role": "assistant",
    "providerID": "opencode-go",
    "modelID": "deepseek-v4-pro",
    "tokens": {"input": 5, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": now_ms},
  })),
)
conn.commit()
conn.close()
PY

result=$(HOME="$CACHE_HOME" XDG_DATA_HOME="$CACHE_HOME/.local/share" XDG_CACHE_HOME="$CACHE_HOME/.cache" \
  "$ROOT/bin/omarchy-agent-usage-opencode-go")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "5" ]] ||
  fail "OpenCode Go collector writes a fresh local-stats cache on first scan" "$result"
cache_file=$(ls "$CACHE_HOME/.cache/omarchy/agent-usage/"/opencode-go-scan-*.json 2>/dev/null | head -n 1)
[[ -n $cache_file && -s $cache_file ]] ||
  fail "OpenCode Go collector leaves a cache file behind" "$result"
[[ $(stat -c %a "$cache_file") == "644" ]] ||
  fail "OpenCode Go collector keeps cache files readable" "$result"
[[ $(jq -r '.schemaVersion' "$cache_file") == "1" && $(jq -r '.stats.todayTotalTokens' "$cache_file") == "5" ]] ||
  fail "OpenCode Go collector writes a versioned cache envelope" "$result"
pass "OpenCode Go collector writes a local-stats cache on first scan"

# A corrupt-but-parseable cache (wrong shape) is a cache miss: rescan and
# rewrite instead of emitting a garbage record.
printf '[]' >"$cache_file"
result=$(HOME="$CACHE_HOME" XDG_DATA_HOME="$CACHE_HOME/.local/share" XDG_CACHE_HOME="$CACHE_HOME/.cache" \
  "$ROOT/bin/omarchy-agent-usage-opencode-go")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "5" ]] ||
  fail "OpenCode Go collector recovers from a corrupt cache file" "$result"
[[ $(jq -r '.schemaVersion' "$cache_file") == "1" ]] ||
  fail "OpenCode Go collector rewrites the cache after a corrupt read" "$result"
pass "OpenCode Go collector recovers from a corrupt cache file"
