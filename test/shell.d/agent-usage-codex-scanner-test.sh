#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.codex/sessions/$(date +%Y/%m/%d)" "$TEST_HOME/bin"

cat >"$TEST_HOME/bin/codex" <<'EOF'
#!/bin/bash

if [[ -n ${CODEX_ARGS_FILE:-} ]]; then
  printf '%s\0' "$@" >"$CODEX_ARGS_FILE"
fi

while read -r request; do
  id=$(jq -r '.id // empty' <<<"$request")
  method=$(jq -r '.method // empty' <<<"$request")

  case "$method" in
    initialize)
      jq -cn --argjson id "$id" '{id: $id, result: {}}'
      ;;
    account/read)
      jq -cn --argjson id "$id" '{id: $id, result: {account: {}}}'
      ;;
    account/rateLimits/read)
      jq -cn --argjson id "$id" '{id: $id, result: {rateLimits: {}}}'
      ;;
  esac
done
EOF
chmod +x "$TEST_HOME/bin/codex"

timestamp="$(date +%Y-%m-%d)T12:00:00Z"
session="$TEST_HOME/.codex/sessions/$(date +%Y/%m/%d)/rollout.jsonl"
cat >"$session" <<EOF
{"timestamp":"$timestamp","type":"turn_context","payload":{"model":"gpt-test"}}
{"timestamp":"$timestamp","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120},"last_token_usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120}}}}
{"timestamp":"$timestamp","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":180,"cached_input_tokens":110,"output_tokens":30,"reasoning_output_tokens":8,"total_tokens":210},"last_token_usage":{"input_tokens":80,"cached_input_tokens":50,"output_tokens":10,"reasoning_output_tokens":3,"total_tokens":90}}}}
EOF

result=$(HOME="$TEST_HOME" CODEX_HOME="$TEST_HOME/.codex" CODEX_ARGS_FILE="$TEST_HOME/codex-args" XDG_DATA_HOME="$TEST_HOME/.local/share" PATH="$TEST_HOME/bin:$PATH" \
  "$ROOT/bin/omarchy-agent-usage-codex")

# NUL-separated, so the assertion sees argument boundaries: a single "-a on-request"
# would flatten to the same text as two arguments but is not a policy codex accepts.
expected_args=(-s read-only -a on-request app-server)
mapfile -d '' -t codex_args <"$TEST_HOME/codex-args"

[[ ${codex_args[*]@Q} == "${expected_args[*]@Q}" ]] ||
  fail "Codex collector uses the supported approval policy" "${codex_args[*]@Q}"
pass "Codex collector uses the supported approval policy"

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "210" ]] ||
  fail "Codex collector counts each turn once" "$result"
pass "Codex collector counts each turn once"

[[ $(jq -c '.modelUsage["gpt-test"]' <<<"$result") == '{"inputTokens":70,"outputTokens":30,"cacheReadInputTokens":110,"cacheCreationInputTokens":0}' ]] ||
  fail "Codex collector does not double-count cache or reasoning tokens" "$result"
pass "Codex collector does not double-count cache or reasoning tokens"

[[ $(jq -c '.id + "/" + (.limits|tostring)' <<<"$result") == '"codex/[]"' ]] ||
  fail "Codex collector identifies itself with an empty limits list" "$result"
pass "Codex collector identifies itself with an empty limits list"

# Pi and omp can both spend a Codex subscription without creating native
# Codex sessions. Their compatible JSONL transcripts must be included.
PI_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$PI_HOME"' EXIT
mkdir -p "$PI_HOME/bin" "$PI_HOME/.pi/agent/sessions/project" "$PI_HOME/.omp/agent/sessions/project"
cp "$TEST_HOME/bin/codex" "$PI_HOME/bin/codex"
cat >"$PI_HOME/.pi/agent/sessions/project/pi.jsonl" <<EOF
{"type":"message","id":"pi-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"openai-codex","api":"openai-codex-responses","model":"gpt-pi","usage":{"input":10,"output":4,"cacheRead":3,"cacheWrite":2,"totalTokens":19}}}
EOF
cat >"$PI_HOME/.omp/agent/sessions/project/omp.jsonl" <<EOF
{ "type": "message", "id": "omp-1", "timestamp": "$timestamp", "message": { "role": "assistant", "provider": "openai-codex", "model": "gpt-omp", "usage": { "input": 20, "output": 5, "cacheRead": 4, "cacheWrite": 1, "totalTokens": 30 } } }
{"type":"message","id":"other-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"anthropic","model":"claude-test","usage":{"input":999,"output":999}}}
EOF

result=$(HOME="$PI_HOME" CODEX_HOME="$PI_HOME/.codex" XDG_DATA_HOME="$PI_HOME/.local/share" \
  PATH="$PI_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "49" ]] ||
  fail "Codex collector counts usage from pi and omp sessions" "$result"
[[ $(jq -c '.modelUsage' <<<"$result") == '{"gpt-pi":{"inputTokens":10,"outputTokens":4,"cacheReadInputTokens":3,"cacheCreationInputTokens":2},"gpt-omp":{"inputTokens":20,"outputTokens":5,"cacheReadInputTokens":4,"cacheCreationInputTokens":1}}' ]] ||
  fail "Codex collector filters pi and omp sessions to Codex providers" "$result"
pass "Codex collector counts pi and omp subscription usage"

# A subscription burned entirely through opencode has no native session files;
# usage must come from opencode's message database, filtered to OpenAI.
OPENCODE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$PI_HOME" "$OPENCODE_HOME"' EXIT
mkdir -p "$OPENCODE_HOME/bin"
cp "$TEST_HOME/bin/codex" "$OPENCODE_HOME/bin/codex"

python3 - "$OPENCODE_HOME/.local/share/opencode/opencode.db" <<'PY'
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
  message("msg_1", "openai", "gpt-5.2-codex", input=80, output=40, reasoning=5, read=30),
  message("msg_2", "anthropic", "claude-opus-5", input=999, output=999),
  message("msg_3", "openai", "gpt-5.2-codex", role="user"),
  message("msg_4", "openai-local", "gpt-5.2-codex", input=999, output=999),
])
conn.execute("INSERT INTO message VALUES ('msg_5', 'ses_1', ?, ?, '[\"not\",\"an\",\"object\"]')", (now_ms, now_ms))
conn.commit()
conn.close()
PY

result=$(HOME="$OPENCODE_HOME" CODEX_HOME="$OPENCODE_HOME/.codex" XDG_DATA_HOME="$OPENCODE_HOME/.local/share" \
  PATH="$OPENCODE_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "155" ]] ||
  fail "Codex collector counts OpenAI usage, reasoning included, from opencode sessions" "$result"
pass "Codex collector counts OpenAI usage, reasoning included, from opencode sessions"

[[ $(jq -c '.modelUsage' <<<"$result") == '{"gpt-5.2-codex":{"inputTokens":80,"outputTokens":45,"cacheReadInputTokens":30,"cacheCreationInputTokens":0}}' ]] ||
  fail "Codex collector ignores prefix-colliding providers, user messages, and malformed rows" "$result"
pass "Codex collector ignores prefix-colliding providers, user messages, and malformed rows"

# Newer opencode releases migrate messages into session_message. When both
# tables exist, the migrated table is authoritative: falling through to the
# legacy table as well would count the same history twice.
python3 - "$OPENCODE_HOME/.local/share/opencode/opencode.db" <<'PY'
import json
import sqlite3
import sys
import time

db = sys.argv[1]
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE session_message (id text PRIMARY KEY, session_id text NOT NULL, type text NOT NULL, seq integer NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now_ms = int(time.time() * 1000)

def message(id, provider, model, type="assistant", input=0, output=0, reasoning=0, read=0, write=0):
  return (id, "ses_2", type, 1, now_ms, now_ms, json.dumps({
    "model": {"providerID": provider, "id": model},
    "tokens": {"input": input, "output": output, "reasoning": reasoning, "cache": {"read": read, "write": write}},
    "time": {"created": now_ms},
  }))

conn.executemany("INSERT INTO session_message VALUES (?, ?, ?, ?, ?, ?, ?)", [
  message("v2_1", "openai", "openai/gpt-new", input=12, output=8, reasoning=3, read=4, write=2),
  message("v2_2", "anthropic", "claude-opus-5", input=999, output=999),
  message("v2_3", "openai", "gpt-new", type="user", input=999, output=999),
  message("v2_4", "openai-local", "gpt-new", input=999, output=999),
])
conn.execute("INSERT INTO session_message VALUES ('v2_5', 'ses_2', 'assistant', 2, ?, ?, 'not json')", (now_ms, now_ms))
conn.commit()
conn.close()
PY

result=$(HOME="$OPENCODE_HOME" CODEX_HOME="$OPENCODE_HOME/.codex" XDG_DATA_HOME="$OPENCODE_HOME/.local/share" \
  PATH="$OPENCODE_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "29" ]] ||
  fail "Codex collector prefers migrated opencode messages over the legacy table" "$result"
[[ $(jq -c '.modelUsage' <<<"$result") == '{"gpt-new":{"inputTokens":12,"outputTokens":11,"cacheReadInputTokens":4,"cacheCreationInputTokens":2}}' ]] ||
  fail "Codex collector parses OpenAI usage from the migrated opencode schema" "$result"
pass "Codex collector reads the authoritative migrated opencode schema"

# A warm cache makes --limits-only cheap: local stats come from the last scan
# instead of another walk over the opencode database, and --force bypasses it.
CACHE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$PI_HOME" "$OPENCODE_HOME" "$CACHE_HOME" "$FRESH_HOME"' EXIT
mkdir -p "$CACHE_HOME/bin"
cp "$TEST_HOME/bin/codex" "$CACHE_HOME/bin/codex"

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

def message(id, provider, model, role="assistant", input=0, output=0, reasoning=0, read=0, write=0):
  return (id, "ses_1", now_ms, now_ms, json.dumps({
    "role": role,
    "providerID": provider,
    "modelID": model,
    "tokens": {"input": input, "output": output, "reasoning": reasoning, "cache": {"read": read, "write": write}},
    "time": {"created": now_ms},
  }))

conn.executemany("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [
  message("c_1", "openai", "gpt-5.2-codex", input=5),
])
conn.commit()
conn.close()
PY

result=$(HOME="$CACHE_HOME" CODEX_HOME="$CACHE_HOME/.codex" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  PATH="$CACHE_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "5" ]] ||
  fail "Codex collector writes a fresh local-stats cache on first scan" "$result"
cache_file=$(ls "$CACHE_HOME/.cache/omarchy/agent-usage/"/codex-scan-*.json 2>/dev/null | head -n 1)
[[ -n $cache_file && -s $cache_file ]] ||
  fail "Codex collector leaves a cache file behind" "$result"
[[ $(stat -c %a "$cache_file") == "644" ]] ||
  fail "Codex collector keeps cache files readable" "$result"
[[ $(jq -r '.schemaVersion' "$cache_file") == "1" && $(jq -r '.stats.todayTotalTokens' "$cache_file") == "5" ]] ||
  fail "Codex collector writes a versioned cache envelope" "$result"
pass "Codex collector writes a local-stats cache on first scan"

# A corrupt-but-parseable cache (wrong shape) is a cache miss: rescan and
# rewrite instead of emitting a garbage record.
printf '[]' >"$cache_file"
result=$(HOME="$CACHE_HOME" CODEX_HOME="$CACHE_HOME/.codex" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  PATH="$CACHE_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "5" ]] ||
  fail "Codex collector recovers from a corrupt cache file" "$result"
[[ $(jq -r '.schemaVersion' "$cache_file") == "1" ]] ||
  fail "Codex collector rewrites the cache after a corrupt read" "$result"
pass "Codex collector recovers from a corrupt cache file"

# A new opencode message changes what a scan would find; a --limits-only run
# must reuse the cached stats instead of rescanning.
python3 - "$CACHE_HOME/.local/share/opencode/opencode.db" <<'PY'
import json
import sqlite3
import sys
import time
from pathlib import Path

db = Path(sys.argv[1])
conn = sqlite3.connect(db)
now_ms = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", (
  "c_2", "ses_1", now_ms, now_ms, json.dumps({
    "role": "assistant",
    "providerID": "openai",
    "modelID": "gpt-5.2-codex",
    "tokens": {"input": 10, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": now_ms},
  }),
))
conn.commit()
conn.close()
PY

result=$(HOME="$CACHE_HOME" CODEX_HOME="$CACHE_HOME/.codex" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  PATH="$CACHE_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "5" ]] ||
  fail "Codex collector --limits-only reuses cached local stats" "$result"
[[ $(jq -c '.modelUsage' <<<"$result") == '{"gpt-5.2-codex":{"inputTokens":5,"outputTokens":0,"cacheReadInputTokens":0,"cacheCreationInputTokens":0}}' ]] ||
  fail "Codex collector --limits-only emits a complete record from cache" "$result"
pass "Codex collector --limits-only reuses cached local stats"

# --force must ignore the cache and pick up the new message.
result=$(HOME="$CACHE_HOME" CODEX_HOME="$CACHE_HOME/.codex" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  PATH="$CACHE_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "15" ]] ||
  fail "Codex collector --force rescans past the cache" "$result"
pass "Codex collector --force rescans past the cache"

# The forced scan refreshed the cache, so a following --limits-only sees it.
result=$(HOME="$CACHE_HOME" CODEX_HOME="$CACHE_HOME/.codex" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  PATH="$CACHE_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "15" ]] ||
  fail "Codex collector --limits-only sees a refreshed cache after --force" "$result"
pass "Codex collector --limits-only sees a refreshed cache after --force"

# An expired cache makes --limits-only rescan too: stale today* stats must
# never be served under a fresh updatedAt.
python3 - "$CACHE_HOME/.local/share/opencode/opencode.db" <<'PY'
import json
import sqlite3
import sys
import time
from pathlib import Path

db = Path(sys.argv[1])
conn = sqlite3.connect(db)
now_ms = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", (
  "c_3", "ses_1", now_ms, now_ms, json.dumps({
    "role": "assistant",
    "providerID": "openai",
    "modelID": "gpt-5.2-codex",
    "tokens": {"input": 10, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": now_ms},
  }),
))
conn.commit()
conn.close()
PY
touch -d "2 hours ago" "$cache_file"
result=$(HOME="$CACHE_HOME" CODEX_HOME="$CACHE_HOME/.codex" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  PATH="$CACHE_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "25" ]] ||
  fail "Codex collector --limits-only rescans when the cache is stale" "$result"
pass "Codex collector --limits-only rescans when the cache is stale"

# The 15-minute reuse window belongs to --limits-only alone. A no-flag run
# (the widget's periodic refresh) reuses a scan only while it is young enough
# to be a concurrent collector run; past that it rescans, so stats stay as
# fresh as refreshIntervalSec, however low the user sets it.
python3 - "$CACHE_HOME/.local/share/opencode/opencode.db" <<'PY'
import json
import sqlite3
import sys
import time
from pathlib import Path

db = Path(sys.argv[1])
conn = sqlite3.connect(db)
now_ms = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", (
  "c_4", "ses_1", now_ms, now_ms, json.dumps({
    "role": "assistant",
    "providerID": "openai",
    "modelID": "gpt-5.2-codex",
    "tokens": {"input": 10, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": now_ms},
  }),
))
conn.commit()
conn.close()
PY

result=$(HOME="$CACHE_HOME" CODEX_HOME="$CACHE_HOME/.codex" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  PATH="$CACHE_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "25" ]] ||
  fail "Codex collector no-flag reuses a seconds-old cache" "$result"

# 30 seconds is the lowest refreshIntervalSec the widget supports, so a
# cache that old must already be past the no-flag reuse window.
touch -d "30 seconds ago" "$cache_file"
result=$(HOME="$CACHE_HOME" CODEX_HOME="$CACHE_HOME/.codex" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  PATH="$CACHE_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "35" ]] ||
  fail "Codex collector no-flag rescans past the concurrent-run window" "$result"
pass "Codex collector no-flag mode rescans instead of serving a stale cache"

# The same age from the other side: a cache far past the no-flag window but
# well inside 15 minutes is still good enough for --limits-only.
python3 - "$CACHE_HOME/.local/share/opencode/opencode.db" <<'PY'
import json
import sqlite3
import sys
import time
from pathlib import Path

db = Path(sys.argv[1])
conn = sqlite3.connect(db)
now_ms = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", (
  "c_5", "ses_1", now_ms, now_ms, json.dumps({
    "role": "assistant",
    "providerID": "openai",
    "modelID": "gpt-5.2-codex",
    "tokens": {"input": 10, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": now_ms},
  }),
))
conn.commit()
conn.close()
PY
touch -d "10 minutes ago" "$cache_file"
result=$(HOME="$CACHE_HOME" CODEX_HOME="$CACHE_HOME/.codex" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  PATH="$CACHE_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "35" ]] ||
  fail "Codex collector --limits-only reuses a scan the no-flag mode would refresh" "$result"
pass "Codex collector --limits-only reuses a scan the no-flag mode would refresh"

# A cache written on another local date holds another day's today* stats even
# under a fresh mtime (midnight passed, or the clock moved backwards): the
# envelope's scanDate must turn it into a miss.
jq -c '.scanDate = "1999-01-01"' "$cache_file" >"$cache_file.tmp" && mv "$cache_file.tmp" "$cache_file"
result=$(HOME="$CACHE_HOME" CODEX_HOME="$CACHE_HOME/.codex" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  PATH="$CACHE_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "45" ]] ||
  fail "Codex collector treats a cache from another day as a miss" "$result"
[[ $(jq -r '.scanDate' "$cache_file") == "$(date +%Y-%m-%d)" ]] ||
  fail "Codex collector stamps the rewritten cache with the scan date" "$result"
pass "Codex collector treats a cache from another day as a miss"

# A cache stamped in the future (the clock was set backwards after the write)
# has no trustworthy age: it must be a miss, not fresh until the clock
# catches up.
python3 - "$CACHE_HOME/.local/share/opencode/opencode.db" <<'PY'
import json
import sqlite3
import sys
import time
from pathlib import Path

db = Path(sys.argv[1])
conn = sqlite3.connect(db)
now_ms = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", (
  "c_6", "ses_1", now_ms, now_ms, json.dumps({
    "role": "assistant",
    "providerID": "openai",
    "modelID": "gpt-5.2-codex",
    "tokens": {"input": 10, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": now_ms},
  }),
))
conn.commit()
conn.close()
PY
touch -d "@$(( $(date +%s) + 3600 ))" "$cache_file"
result=$(HOME="$CACHE_HOME" CODEX_HOME="$CACHE_HOME/.codex" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  PATH="$CACHE_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "55" ]] ||
  fail "Codex collector treats a future-dated cache as a miss" "$result"
pass "Codex collector treats a future-dated cache as a miss"

# First --limits-only on a machine with no cache falls back to a full scan.
FRESH_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$PI_HOME" "$OPENCODE_HOME" "$CACHE_HOME" "$FRESH_HOME"' EXIT
mkdir -p "$FRESH_HOME/bin"
cp "$TEST_HOME/bin/codex" "$FRESH_HOME/bin/codex"

python3 - "$FRESH_HOME/.local/share/opencode/opencode.db" <<'PY'
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
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", (
  "f_1", "ses_1", now_ms, now_ms, json.dumps({
    "role": "assistant",
    "providerID": "openai",
    "modelID": "gpt-5.2-codex",
    "tokens": {"input": 7, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": now_ms},
  }),
))
conn.commit()
conn.close()
PY

result=$(HOME="$FRESH_HOME" CODEX_HOME="$FRESH_HOME/.codex" XDG_CACHE_HOME="$FRESH_HOME/.cache" XDG_DATA_HOME="$FRESH_HOME/.local/share" \
  PATH="$FRESH_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "7" ]] ||
  fail "Codex collector --limits-only falls back to a full scan without a cache" "$result"
pass "Codex collector --limits-only falls back to a full scan without a cache"

# A malformed opencode row must not abort the scan: json_valid() guards the
# parse, so the good rows are still counted. Real opencode data also stores
# compact JSON, so one row is serialized compactly here on purpose.
MALFORMED_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$PI_HOME" "$OPENCODE_HOME" "$CACHE_HOME" "$FRESH_HOME" "$MALFORMED_HOME"' EXIT
mkdir -p "$MALFORMED_HOME/bin"
cp "$TEST_HOME/bin/codex" "$MALFORMED_HOME/bin/codex"

python3 - "$MALFORMED_HOME/.local/share/opencode/opencode.db" <<'PY'
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

def message(id, input=0, compact=False):
  payload = {
    "role": "assistant",
    "providerID": "openai",
    "modelID": "gpt-5.2-codex",
    "tokens": {"input": input, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": now_ms},
  }
  if compact:
    return (id, "ses_1", now_ms, now_ms, json.dumps(payload, separators=(",", ":")))
  return (id, "ses_1", now_ms, now_ms, json.dumps(payload))

conn.executemany("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [
  message("mm_1", input=5, compact=True),
  message("mm_2", input=7),
])
# Valid JSON followed by trailing garbage: without json_valid() this row
# makes json_extract() raise and aborts the whole scan.
good = json.dumps({"role": "assistant", "providerID": "openai", "modelID": "gpt-5.2-codex",
                   "tokens": {"input": 999, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
                   "time": {"created": now_ms}})
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("mm_3", "ses_1", now_ms, now_ms, good + " trailing-garbage"))
# Completely broken row: not JSON at all.
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("mm_4", "ses_1", now_ms, now_ms, "this is not json"))
conn.commit()
conn.close()
PY

result=$(HOME="$MALFORMED_HOME" CODEX_HOME="$MALFORMED_HOME/.codex" XDG_CACHE_HOME="$MALFORMED_HOME/.cache" XDG_DATA_HOME="$MALFORMED_HOME/.local/share" \
  PATH="$MALFORMED_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "12" ]] ||
  fail "Codex collector counts good opencode rows past malformed ones" "$result"
pass "Codex collector counts good opencode rows past malformed ones"

# An unwritable cache must not kill the collector: the record is the contract.
UNWRITABLE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$PI_HOME" "$OPENCODE_HOME" "$CACHE_HOME" "$FRESH_HOME" "$MALFORMED_HOME" "$UNWRITABLE_HOME"' EXIT
mkdir -p "$UNWRITABLE_HOME/bin"
cp "$TEST_HOME/bin/codex" "$UNWRITABLE_HOME/bin/codex"

python3 - "$UNWRITABLE_HOME/.local/share/opencode/opencode.db" <<'PY'
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
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", (
  "u_1", "ses_1", now_ms, now_ms, json.dumps({
    "role": "assistant",
    "providerID": "openai",
    "modelID": "gpt-5.2-codex",
    "tokens": {"input": 3, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": now_ms},
  }),
))
conn.commit()
conn.close()
PY

# XDG_CACHE_HOME points at a regular file, so mkdir inside cache_root fails.
touch "$UNWRITABLE_HOME/not-a-dir"
result=$(HOME="$UNWRITABLE_HOME" CODEX_HOME="$UNWRITABLE_HOME/.codex" XDG_CACHE_HOME="$UNWRITABLE_HOME/not-a-dir" XDG_DATA_HOME="$UNWRITABLE_HOME/.local/share" \
  PATH="$UNWRITABLE_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "3" ]] ||
  fail "Codex collector still prints a complete record when the cache is unwritable" "$result"
pass "Codex collector still prints a complete record when the cache is unwritable"

# A scan cut short by a database error (schema migration, transient lock,
# corruption) must not be cached as the whole story, or the missing usage
# would be suppressed for every reader until the cache expires.
INTERRUPTED_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$PI_HOME" "$OPENCODE_HOME" "$CACHE_HOME" "$FRESH_HOME" "$MALFORMED_HOME" "$UNWRITABLE_HOME" "$INTERRUPTED_HOME"' EXIT
mkdir -p "$INTERRUPTED_HOME/bin"
cp "$TEST_HOME/bin/codex" "$INTERRUPTED_HOME/bin/codex"

# A database without the message table makes the scan fail mid-flight.
python3 - "$INTERRUPTED_HOME/.local/share/opencode/opencode.db" <<'PY'
import sqlite3
import sys
from pathlib import Path

db = Path(sys.argv[1])
db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE unrelated (id text PRIMARY KEY)")
conn.commit()
conn.close()
PY

result=$(HOME="$INTERRUPTED_HOME" CODEX_HOME="$INTERRUPTED_HOME/.codex" XDG_CACHE_HOME="$INTERRUPTED_HOME/.cache" XDG_DATA_HOME="$INTERRUPTED_HOME/.local/share" \
  PATH="$INTERRUPTED_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "0" ]] ||
  fail "Codex collector reports what it could read from a broken database" "$result"
[[ -z $(ls "$INTERRUPTED_HOME/.cache/omarchy/agent-usage/"codex-scan-*.json 2>/dev/null) ]] ||
  fail "Codex collector must not cache an interrupted scan" "$result"

# Once the database is whole again, the very next --limits-only run scans it
# instead of reusing a zero snapshot.
python3 - "$INTERRUPTED_HOME/.local/share/opencode/opencode.db" <<'PY'
import json
import sqlite3
import sys
import time
from pathlib import Path

db = Path(sys.argv[1])
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now_ms = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", (
  "i_1", "ses_1", now_ms, now_ms, json.dumps({
    "role": "assistant",
    "providerID": "openai",
    "modelID": "gpt-5.2-codex",
    "tokens": {"input": 9, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": now_ms},
  }),
))
conn.commit()
conn.close()
PY

result=$(HOME="$INTERRUPTED_HOME" CODEX_HOME="$INTERRUPTED_HOME/.codex" XDG_CACHE_HOME="$INTERRUPTED_HOME/.cache" XDG_DATA_HOME="$INTERRUPTED_HOME/.local/share" \
  PATH="$INTERRUPTED_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "9" ]] ||
  fail "Codex collector does not reuse a snapshot from an interrupted scan" "$result"
pass "Codex collector does not cache an interrupted opencode scan"

# OpenCode can hold a different ChatGPT subscription from the native Codex
# CLI. Its OAuth token should be handed to an isolated app-server process,
# and its limits should only be added when the stable account ids differ.
LIMITS_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$PI_HOME" "$OPENCODE_HOME" "$CACHE_HOME" "$FRESH_HOME" "$MALFORMED_HOME" "$UNWRITABLE_HOME" "$INTERRUPTED_HOME" "$LIMITS_HOME"' EXIT
mkdir -p "$LIMITS_HOME/bin" "$LIMITS_HOME/.codex" "$LIMITS_HOME/.local/share/opencode"

cat >"$LIMITS_HOME/bin/codex" <<'EOF'
#!/bin/bash

external=false
while read -r request; do
  id=$(jq -r '.id // empty' <<<"$request")
  method=$(jq -r '.method // empty' <<<"$request")

  case "$method" in
    initialize)
      experimental=$(jq -r '.params.capabilities.experimentalApi // false' <<<"$request")
      printf 'initialize:%s\n' "$experimental" >>"$RPC_LOG"
      jq -cn --argjson id "$id" '{id: $id, result: {}}'
      ;;
    account/login/start)
      external=true
      type=$(jq -r '.params.type // empty' <<<"$request")
      has_access=$(jq -r '(.params.accessToken // "") != ""' <<<"$request")
      has_account=$(jq -r '(.params.chatgptAccountId // "") != ""' <<<"$request")
      printf 'login:%s:%s:%s\n' "$type" "$has_access" "$has_account" >>"$RPC_LOG"
      if [[ $(jq -r '.params.accessToken == "secret-database-token" and .params.chatgptAccountId == "database-account"' <<<"$request") == "true" ]]; then
        printf 'credential:database\n' >>"$RPC_LOG"
      fi
      if [[ ${FAIL_EXTERNAL_LOGIN:-false} == "true" ]]; then
        jq -cn --argjson id "$id" '{id: $id, error: {message: "login failed"}}'
      else
        jq -cn --argjson id "$id" '{id: $id, result: {type: "chatgptAuthTokens"}}'
      fi
      ;;
    account/read)
      if [[ $external == "true" ]]; then
        jq -cn --argjson id "$id" --arg email "${OPENCODE_TEST_EMAIL-opencode@example.com}" \
          '{id: $id, result: {account: {type: "chatgpt", email: $email, planType: "plus"}}}'
      else
        jq -cn --argjson id "$id" --arg email "${NATIVE_TEST_EMAIL-codex@example.com}" \
          '{id: $id, result: {account: {type: "chatgpt", email: $email, planType: "pro"}}}'
      fi
      ;;
    account/rateLimits/read)
      if [[ $external == "true" ]]; then
        if [[ ${NO_EXTERNAL_LIMITS:-false} == "true" ]]; then
          jq -cn --argjson id "$id" '{id: $id, result: {rateLimits: {}}}'
        else
          jq -cn --argjson id "$id" '{id: $id, result: {rateLimits: {primary: {usedPercent: 25, windowDurationMins: 300, resetsAt: 1780000000}}}}'
        fi
      else
        jq -cn --argjson id "$id" '{id: $id, result: {rateLimits: {primary: {usedPercent: 10, windowDurationMins: 10080, resetsAt: 1780000000}}}}'
      fi
      ;;
  esac
done
EOF
chmod +x "$LIMITS_HOME/bin/codex"

printf '%s\n' '{"tokens":{"account_id":"native-account"}}' >"$LIMITS_HOME/.codex/auth.json"
printf '%s\n' '{"openai":{"type":"oauth","access":"secret-opencode-token","accountId":"opencode-account"}}' >"$LIMITS_HOME/.local/share/opencode/auth.json"

RPC_LOG="$LIMITS_HOME/rpc.log" result=$(HOME="$LIMITS_HOME" CODEX_HOME="$LIMITS_HOME/.codex" XDG_DATA_HOME="$LIMITS_HOME/.local/share" \
  RPC_LOG="$LIMITS_HOME/rpc.log" PATH="$LIMITS_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex")

[[ $(jq -c '[.limits[] | [.label, .percent]]' <<<"$result") == '[["Weekly (7-day)",0.1]]' ]] ||
  fail "Codex collector leaves OpenCode limits disabled by default" "$result"
[[ $(grep -c '^login:' "$LIMITS_HOME/rpc.log") == "0" ]] ||
  fail "Codex collector does not use OpenCode OAuth without opt-in" "$(<"$LIMITS_HOME/rpc.log")"
pass "Codex collector requires opt-in for OpenCode limits"

: >"$LIMITS_HOME/rpc.log"
RPC_LOG="$LIMITS_HOME/rpc.log" result=$(HOME="$LIMITS_HOME" CODEX_HOME="$LIMITS_HOME/.codex" XDG_DATA_HOME="$LIMITS_HOME/.local/share" \
  RPC_LOG="$LIMITS_HOME/rpc.log" PATH="$LIMITS_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex" --opencode-openai-limits)

[[ $(jq -c '[.limits[] | [.label, .percent]]' <<<"$result") == '[["codex@example.com · Weekly (7-day)",0.1],["opencode@example.com · 5h window",0.25]]' ]] ||
  fail "Codex collector labels distinct account limits with their emails" "$result"
[[ $(jq -c '[.limits[].title]' <<<"$result") == '["codex@example.com · Weekly","opencode@example.com · Session"]' ]] ||
  fail "Codex collector supplies display titles that preserve account emails" "$result"
[[ $(jq -r '.tierLabel' <<<"$result") == "pro" ]] ||
  fail "Codex collector keeps the native subscription as the hero plan" "$result"
[[ $(grep -c '^login:chatgptAuthTokens:true:true$' "$LIMITS_HOME/rpc.log") == "1" ]] ||
  fail "Codex collector supplies OpenCode OAuth through external-token auth" "$(<"$LIMITS_HOME/rpc.log")"
[[ $(grep -c '^initialize:true$' "$LIMITS_HOME/rpc.log") == "1" ]] ||
  fail "Codex collector enables the experimental external-token API only for OpenCode" "$(<"$LIMITS_HOME/rpc.log")"
[[ $result != *"secret-opencode-token"* && $result != *"native-account"* && $result != *"opencode-account"* ]] ||
  fail "Codex collector keeps account credentials out of its record" "$result"
pass "Codex collector labels distinct account limits with their emails"

# Empty external windows and a failed external login are both best-effort
# outcomes. Neither should relabel or otherwise disturb native Codex limits.
for failure_mode in empty login; do
  : >"$LIMITS_HOME/rpc.log"
  if [[ $failure_mode == "empty" ]]; then
    result=$(HOME="$LIMITS_HOME" CODEX_HOME="$LIMITS_HOME/.codex" XDG_DATA_HOME="$LIMITS_HOME/.local/share" \
      RPC_LOG="$LIMITS_HOME/rpc.log" NO_EXTERNAL_LIMITS=true PATH="$LIMITS_HOME/bin:$PATH" \
      "$ROOT/bin/omarchy-agent-usage-codex" --opencode-openai-limits)
  else
    result=$(HOME="$LIMITS_HOME" CODEX_HOME="$LIMITS_HOME/.codex" XDG_DATA_HOME="$LIMITS_HOME/.local/share" \
      RPC_LOG="$LIMITS_HOME/rpc.log" FAIL_EXTERNAL_LOGIN=true PATH="$LIMITS_HOME/bin:$PATH" \
      "$ROOT/bin/omarchy-agent-usage-codex" --opencode-openai-limits)
  fi
  [[ $(jq -c '[.limits[] | [.label, .percent]]' <<<"$result") == '[["Weekly (7-day)",0.1]]' ]] ||
    fail "Codex collector preserves native limits after an OpenCode $failure_mode result" "$result"
  [[ $(jq -r '.usageStatusText' <<<"$result") == "" ]] ||
    fail "Codex collector keeps an OpenCode $failure_mode result best-effort" "$result"
done
pass "Codex collector preserves native limits when optional OpenCode limits are unavailable"

# App-server account emails are nullable. Both meters still need distinct,
# stable source labels when neither account supplies one.
: >"$LIMITS_HOME/rpc.log"
result=$(HOME="$LIMITS_HOME" CODEX_HOME="$LIMITS_HOME/.codex" XDG_DATA_HOME="$LIMITS_HOME/.local/share" \
  RPC_LOG="$LIMITS_HOME/rpc.log" NATIVE_TEST_EMAIL="" OPENCODE_TEST_EMAIL="" PATH="$LIMITS_HOME/bin:$PATH" \
  "$ROOT/bin/omarchy-agent-usage-codex" --opencode-openai-limits)

[[ $(jq -c '[.limits[].title]' <<<"$result") == '["Codex · Weekly","OpenCode · Session"]' ]] ||
  fail "Codex collector falls back to source names when account emails are unavailable" "$result"
pass "Codex collector falls back when account emails are unavailable"

# The same ChatGPT account in both tools must not produce duplicate meters or
# even start a second app-server authentication flow.
printf '%s\n' '{"openai":{"type":"oauth","access":"secret-opencode-token","accountId":"native-account"}}' >"$LIMITS_HOME/.local/share/opencode/auth.json"
: >"$LIMITS_HOME/rpc.log"

RPC_LOG="$LIMITS_HOME/rpc.log" result=$(HOME="$LIMITS_HOME" CODEX_HOME="$LIMITS_HOME/.codex" XDG_DATA_HOME="$LIMITS_HOME/.local/share" \
  RPC_LOG="$LIMITS_HOME/rpc.log" PATH="$LIMITS_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex" --opencode-openai-limits)

[[ $(jq -c '[.limits[] | [.label, .percent]]' <<<"$result") == '[["Weekly (7-day)",0.1]]' ]] ||
  fail "Codex collector deduplicates matching native and OpenCode accounts" "$result"
[[ $(grep -c '^login:' "$LIMITS_HOME/rpc.log") == "0" ]] ||
  fail "Codex collector skips external auth for a matching account" "$(<"$LIMITS_HOME/rpc.log")"
pass "Codex collector deduplicates matching native and OpenCode accounts"

# Newer OpenCode builds migrate provider credentials into opencode.db. That
# current database record must take precedence over a stale legacy auth.json,
# while the file-based cases above retain backwards compatibility.
python3 - "$LIMITS_HOME/.local/share/opencode/opencode.db" <<'PY'
import json
import sqlite3
import sys
import time
from pathlib import Path

db = Path(sys.argv[1])
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
conn.execute("CREATE TABLE credential (id text PRIMARY KEY, integration_id text, label text NOT NULL, value text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL)")
now_ms = int(time.time() * 1000)
conn.execute("INSERT INTO credential VALUES (?, ?, ?, ?, ?, ?)", (
  "cred_openai",
  "openai",
  "OAuth",
  json.dumps({
    "type": "oauth",
    "access": "secret-database-token",
    "refresh": "secret-database-refresh",
    "expires": now_ms + 3_600_000,
    "metadata": {"accountID": "database-account"},
  }),
  now_ms,
  now_ms,
))
conn.commit()
conn.close()
PY
printf '%s\n' '{"openai":{"type":"oauth","access":"secret-stale-token","accountId":"native-account"}}' >"$LIMITS_HOME/.local/share/opencode/auth.json"
: >"$LIMITS_HOME/rpc.log"

RPC_LOG="$LIMITS_HOME/rpc.log" result=$(HOME="$LIMITS_HOME" CODEX_HOME="$LIMITS_HOME/.codex" XDG_DATA_HOME="$LIMITS_HOME/.local/share" \
  RPC_LOG="$LIMITS_HOME/rpc.log" PATH="$LIMITS_HOME/bin:$PATH" "$ROOT/bin/omarchy-agent-usage-codex" --opencode-openai-limits)

[[ $(jq -c '[.limits[] | [.label, .percent]]' <<<"$result") == '[["codex@example.com · Weekly (7-day)",0.1],["opencode@example.com · 5h window",0.25]]' ]] ||
  fail "Codex collector reads current OpenCode database credentials" "$result"
[[ $(grep -c '^credential:database$' "$LIMITS_HOME/rpc.log") == "1" ]] ||
  fail "Codex collector prefers OpenCode database credentials over stale auth.json" "$(<"$LIMITS_HOME/rpc.log")"
[[ $result != *"secret-database-token"* && $result != *"secret-database-refresh"* && $result != *"database-account"* ]] ||
  fail "Codex collector keeps database-backed OpenCode credentials out of its record" "$result"
pass "Codex collector reads database-backed OpenCode credentials"
