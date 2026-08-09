#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

projects="$TEST_HOME/.claude/projects/example"
mkdir -p "$projects"

timestamp="$(date +%Y-%m-%d)T12:00:00Z"
cat >"$projects/session.jsonl" <<EOF
{"timestamp":"$timestamp","type":"assistant","sessionId":"session-1","uuid":"event-1","message":{"id":"message-1","role":"assistant","model":"claude-test","usage":{"input_tokens":2,"cache_creation_input_tokens":28857,"cache_read_input_tokens":0,"output_tokens":231}}}
{"timestamp":"$timestamp","type":"assistant","sessionId":"session-1","uuid":"event-2","message":{"id":"message-1","role":"assistant","model":"claude-test","usage":{"input_tokens":2,"cache_creation_input_tokens":28857,"cache_read_input_tokens":0,"output_tokens":231}}}
{"timestamp":"$timestamp","type":"assistant","sessionId":"session-1","uuid":"event-3","message":{"id":"message-2","role":"assistant","model":"claude-test","usage":{"input_tokens":2,"cache_creation_input_tokens":454,"cache_read_input_tokens":28857,"output_tokens":390}}}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_DATA_HOME="$TEST_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-claude" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "58793" ]] ||
  fail "Claude collector counts each API message once" "$result"
pass "Claude collector counts each API message once"

[[ $(jq -c '.modelUsage["claude-test"]' <<<"$result") == '{"cacheCreationInputTokens":29311,"cacheReadInputTokens":28857,"inputTokens":4,"outputTokens":621}' ]] ||
  fail "Claude collector keeps mutually exclusive token categories" "$result"
pass "Claude collector keeps mutually exclusive token categories"

[[ $(jq -r '.id + "/" + .usageStatusText' <<<"$result") == "claude/Waiting for auth" ]] ||
  fail "Claude collector identifies itself and reports missing auth" "$result"
pass "Claude collector identifies itself and reports missing auth"

# A machine with no transcripts and no stats-cache still gets today's counts
# from history.jsonl alone.
HISTORY_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$HISTORY_HOME"' EXIT
mkdir -p "$HISTORY_HOME/.claude"

now_ms=$(($(date +%s) * 1000))
cat >"$HISTORY_HOME/.claude/history.jsonl" <<EOF
{"timestamp":86400000,"sessionId":"old","display":"ancient"}
{"timestamp":$now_ms,"sessionId":"s1","display":"one"}
{"timestamp":$now_ms,"sessionId":"s2","display":"two"}
EOF

result=$(HOME="$HISTORY_HOME" XDG_CACHE_HOME="$HISTORY_HOME/.cache" XDG_DATA_HOME="$HISTORY_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-claude" --force)

[[ $(jq -r '(.todayPrompts|tostring) + "/" + (.todaySessions|tostring)' <<<"$result") == "2/2" ]] ||
  fail "Claude collector falls back to history.jsonl without a stats-cache" "$result"
pass "Claude collector falls back to history.jsonl without a stats-cache"

# A subscription burned entirely through opencode has no ~/.claude transcripts;
# usage must come from opencode's message database, filtered to Anthropic.
OPENCODE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$HISTORY_HOME" "$OPENCODE_HOME"' EXIT

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
  message("msg_1", "anthropic", "claude-opus-5", input=100, output=50, reasoning=7, read=25, write=10),
  message("msg_2", "fireworks-ai", "accounts/fireworks/models/kimi-k3", input=999, output=999),
  message("msg_3", "openai", "gpt-5.2-codex", input=999, output=999),
  message("msg_4", "anthropic", "claude-opus-5", role="user"),
  message("msg_5", "anthropic-proxy", "claude-opus-5", input=999, output=999),
])
conn.execute("INSERT INTO message VALUES ('msg_6', 'ses_1', ?, ?, '[\"not\",\"an\",\"object\"]')", (now_ms, now_ms))
conn.commit()
conn.close()
PY

result=$(HOME="$OPENCODE_HOME" XDG_CACHE_HOME="$OPENCODE_HOME/.cache" XDG_DATA_HOME="$OPENCODE_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-claude" --force)

[[ $(jq -r '(.ready|tostring) + "/" + (.todayTotalTokens|tostring)' <<<"$result") == "true/192" ]] ||
  fail "Claude collector counts Anthropic usage, reasoning included, from opencode sessions" "$result"
pass "Claude collector counts Anthropic usage, reasoning included, from opencode sessions"

[[ $(jq -c '.modelUsage' <<<"$result") == '{"claude-opus-5":{"cacheCreationInputTokens":10,"cacheReadInputTokens":25,"inputTokens":100,"outputTokens":57}}' ]] ||
  fail "Claude collector ignores prefix-colliding providers, user messages, and malformed rows" "$result"
pass "Claude collector ignores prefix-colliding providers, user messages, and malformed rows"

# Pi and omp can both spend a Claude subscription without writing native
# Claude Code transcripts. Their compatible JSONL sessions must be included.
PI_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$HISTORY_HOME" "$OPENCODE_HOME" "$PI_HOME"' EXIT
mkdir -p "$PI_HOME/.pi/agent/sessions/project" "$PI_HOME/.omp/agent/sessions/project"

cat >"$PI_HOME/.pi/agent/sessions/project/pi.jsonl" <<EOF
{"type":"message","id":"pi-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"anthropic","api":"anthropic-messages","model":"claude-pi","usage":{"input":10,"output":4,"cacheRead":3,"cacheWrite":2,"totalTokens":19}}}
{"type":"message","id":"codex-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"openai-codex","model":"gpt-test","usage":{"input":999,"output":999}}}
{"type":"message","id":"kimi-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"kimi-coding","api":"anthropic-messages","model":"k3","usage":{"input":999,"output":999}}}
EOF
cat >"$PI_HOME/.omp/agent/sessions/project/omp.jsonl" <<EOF
{ "type": "message", "id": "omp-1", "timestamp": "$timestamp", "message": { "role": "assistant", "provider": "anthropic", "model": "claude-omp", "usage": { "input": 20, "output": 5, "cacheRead": 4, "cacheWrite": 1, "totalTokens": 30 } } }
EOF

result=$(HOME="$PI_HOME" XDG_CACHE_HOME="$PI_HOME/.cache" XDG_DATA_HOME="$PI_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-claude" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "49" ]] ||
  fail "Claude collector counts usage from pi and omp sessions" "$result"
[[ $(jq -c '.modelUsage' <<<"$result") == '{"claude-omp":{"cacheCreationInputTokens":1,"cacheReadInputTokens":4,"inputTokens":20,"outputTokens":5},"claude-pi":{"cacheCreationInputTokens":2,"cacheReadInputTokens":3,"inputTokens":10,"outputTokens":4}}' ]] ||
  fail "Claude collector filters pi and omp sessions to Anthropic providers" "$result"
pass "Claude collector counts pi and omp subscription usage"

# Collectors overlap in practice: the update command backgrounds one per agent
# while the panel refreshes on its own. Two writers aiming at one cache file
# must both land, not trip over a shared temp path.
race_output=$(python3 - "$ROOT/bin/omarchy-agent-usage-claude" "$TEST_HOME/race.json" <<'PY'
import importlib.util
import json
import sys
import threading
from importlib.machinery import SourceFileLoader
from pathlib import Path

# The collector has no .py suffix, so name its loader explicitly.
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
  fail "Claude collector survives concurrent writes to one cache file" "$race_output"
[[ $(jq -r '.payload.writer != null and (.leftovers | length) == 0' <<<"$race_output") == "true" ]] ||
  fail "Claude collector leaves one intact cache file and no temp files" "$race_output"
[[ $(jq -r '.mode' <<<"$race_output") == "0o644" ]] ||
  fail "Claude collector keeps cache files readable" "$race_output"
pass "Claude collector survives concurrent writes to one cache file"
