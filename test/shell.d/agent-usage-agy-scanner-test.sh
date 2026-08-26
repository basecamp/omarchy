#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

history_dir="$TEST_HOME/.gemini/antigravity-cli"
mkdir -p "$history_dir"

now_ms=$(($(date +%s) * 1000))
cat >"$history_dir/history.jsonl" <<EOF
{"timestamp":86400000,"conversationId":"old-session","display":"ancient prompt"}
{"timestamp":$now_ms,"conversationId":"session-1","display":"prompt one"}
{"timestamp":$now_ms,"conversationId":"session-2","display":"prompt two"}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_DATA_HOME="$TEST_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-agy" --force)

[[ $(jq -r '.id' <<<"$result") == "agy" ]] ||
  fail "Antigravity collector identifies itself as agy" "$result"
pass "Antigravity collector identifies itself"

[[ $(jq -r '(.todayPrompts|tostring) + "/" + (.todaySessions|tostring)' <<<"$result") == "2/2" ]] ||
  fail "Antigravity collector reads today prompts and sessions from history.jsonl" "$result"
pass "Antigravity collector parses history.jsonl correctly"

[[ $(jq -r '.ready' <<<"$result") == "true" ]] ||
  fail "Antigravity collector marks ready as true when stats exist" "$result"
pass "Antigravity collector reports ready state"

# Opencode Google provider sessions
OPENCODE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OPENCODE_HOME"' EXIT

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
  message("msg_1", "google", "gemini-2.5-flash", input=200, output=100, reasoning=10, read=50, write=20),
  message("msg_2", "openai", "gpt-5.2-codex", input=999, output=999),
  message("msg_3", "google", "gemini-2.5-flash", role="user"),
])
conn.commit()
conn.close()
PY

result=$(HOME="$OPENCODE_HOME" XDG_CACHE_HOME="$OPENCODE_HOME/.cache" XDG_DATA_HOME="$OPENCODE_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-agy" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "380" ]] ||
  fail "Antigravity collector counts Google tokens from opencode database" "$result"
pass "Antigravity collector merges opencode Google provider stats"

# Pi and omp sessions with Google provider
PI_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OPENCODE_HOME" "$PI_HOME"' EXIT
mkdir -p "$PI_HOME/.pi/agent/sessions/project" "$PI_HOME/.omp/agent/sessions/project"

timestamp="$(date +%Y-%m-%d)T12:00:00Z"
cat >"$PI_HOME/.pi/agent/sessions/project/pi.jsonl" <<EOF
{"type":"message","id":"pi-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"google","model":"gemini-pi","usage":{"input":15,"output":5,"cacheRead":2,"cacheWrite":1,"totalTokens":23}}}
{"type":"message","id":"codex-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"openai-codex","model":"gpt-test","usage":{"input":999,"output":999}}}
EOF
cat >"$PI_HOME/.omp/agent/sessions/project/omp.jsonl" <<EOF
{ "type": "message", "id": "omp-1", "timestamp": "$timestamp", "message": { "role": "assistant", "provider": "gemini", "model": "gemini-omp", "usage": { "input": 25, "output": 10, "cacheRead": 5, "cacheWrite": 2, "totalTokens": 42 } } }
{ "type": "message", "id": "claude-1", "timestamp": "$timestamp", "message": { "role": "assistant", "provider": "anthropic", "model": "claude-test", "usage": { "input": 999, "output": 999 } } }
EOF

result=$(HOME="$PI_HOME" XDG_CACHE_HOME="$PI_HOME/.cache" XDG_DATA_HOME="$PI_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-agy" --force)

[[ $(jq -r '.modelUsage["gemini-pi"].inputTokens' <<<"$result") == "15" && \
   $(jq -r '.modelUsage["gemini-omp"].inputTokens' <<<"$result") == "25" && \
   $(jq -r '.modelUsage["claude-test"] // null' <<<"$result") == "null" && \
   $(jq -r '.modelUsage["gpt-test"] // null' <<<"$result") == "null" ]] ||
  fail "Antigravity collector filters pi and omp sessions to Google/Gemini providers" "$result"
pass "Antigravity collector counts pi and omp Google subscription usage"

# Concurrent write safety
race_output=$(python3 - "$ROOT/bin/omarchy-agent-usage-agy" "$TEST_HOME/race.json" <<'PY'
import importlib.util
import json
import sys
import threading
from importlib.machinery import SourceFileLoader
from pathlib import Path

spec = importlib.util.spec_from_loader("collector", SourceFileLoader("collector", sys.argv[1]))
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)

target = Path(sys.argv[2])
failures = []
start = threading.Barrier(8)

def hammer(writer):
  start.wait()
  for round in range(25):
    try:
      collector.write_json(target, {"writer": writer, "round": round})
    except Exception as error:
      failures.append(repr(error))

threads = [threading.Thread(target=hammer, args=(writer,)) for writer in range(8)]
for thread in threads:
  thread.start()
for thread in threads:
  thread.join()

leftovers = sorted(path.name for path in target.parent.glob(target.name + ".*"))
print(json.dumps({
  "failures": failures[:3],
  "mode": oct(target.stat().st_mode & 0o777),
  "payload": json.loads(target.read_text(encoding="utf-8")),
  "leftovers": leftovers,
}))
PY
)

[[ $(jq -c '.failures' <<<"$race_output") == "[]" ]] ||
  fail "Antigravity collector survives concurrent writes to one cache file" "$race_output"
[[ $(jq -r '.payload.writer != null and (.leftovers | length) == 0' <<<"$race_output") == "true" ]] ||
  fail "Antigravity collector leaves one intact cache file and no temp files" "$race_output"
[[ $(jq -r '.mode' <<<"$race_output") == "0o644" ]] ||
  fail "Antigravity collector keeps cache files readable" "$race_output"
pass "Antigravity collector survives concurrent writes to one cache file"
