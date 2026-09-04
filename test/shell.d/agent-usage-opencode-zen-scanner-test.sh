#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

empty=$(HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  "$ROOT/bin/omarchy-agent-usage-opencode-zen")

[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + .name + ":" + .tierLabel' <<<"$empty") == \
  "opencode-zen:false:OpenCode:Zen · Pay as you go" ]] ||
  fail "OpenCode Zen collector prints a valid record without a database" "$empty"
pass "OpenCode Zen collector prints a valid record without a database"

result=$(python3 - "$ROOT/bin/omarchy-agent-usage-opencode-zen" "$TEST_HOME" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import sqlite3
import sys
import time
from pathlib import Path

collector_path = str(Path(sys.argv[1]))
test_home = Path(sys.argv[2])

os.environ["TZ"] = "UTC"
time.tzset()
os.environ["XDG_CACHE_HOME"] = str(test_home / "cache")

loader = importlib.machinery.SourceFileLoader("opencode_zen_collector", collector_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)

db = test_home / "data" / "opencode" / "opencode.db"
db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, data TEXT NOT NULL)")
conn.execute("CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, time_created INTEGER NOT NULL, data TEXT NOT NULL)")
now_ms = int(time.time() * 1000)

def day_offset(days):
  return now_ms - days * 86400 * 1000

rows = [
  ("zen-today", "session-one", {
    "role": "assistant", "providerID": "opencode", "modelID": "kimi-k2.6",
    "tokens": {"input": 607, "output": 36, "reasoning": 55, "total": 7386,
               "cache": {"read": 6688, "write": 0}},
    "time": {"created": day_offset(0)},
  }),
  ("zen-prior", "session-two", {
    "role": "assistant", "providerID": "opencode", "modelID": "glm-4.5",
    "tokens": {"input": 100, "output": 20, "reasoning": 5,
               "cache": {"read": 10, "write": 2}},
    "time": {"created": day_offset(2)},
  }),
  ("zen-old", "session-three", {
    "role": "assistant", "providerID": "opencode", "modelID": "kimi-k2.6",
    "tokens": {"input": 50, "output": 10}, "time": {"created": day_offset(8)},
  }),
  ("go", "session-go", {
    "role": "assistant", "providerID": "opencode-go", "modelID": "kimi-k2.6",
    "tokens": {"input": 9000, "output": 9000}, "time": {"created": day_offset(0)},
  }),
  ("openai", "session-openai", {
    "role": "assistant", "providerID": "openai", "modelID": "gpt-5",
    "tokens": {"input": 9000, "output": 9000}, "time": {"created": day_offset(0)},
  }),
  ("user", "session-one", {
    "role": "user", "providerID": "opencode", "modelID": "kimi-k2.6",
    "tokens": {"input": 9000, "output": 9000}, "time": {"created": day_offset(0)},
  }),
  ("zero", "session-zero", {
    "role": "assistant", "providerID": "opencode", "modelID": "kimi-k2.6",
    "tokens": {"input": 0, "output": 0}, "time": {"created": day_offset(0)},
  }),
]
conn.executemany(
  "INSERT INTO message (id, session_id, data) VALUES (?, ?, ?)",
  [(message_id, session_id, json.dumps(data)) for message_id, session_id, data in rows],
)
conn.executemany("INSERT INTO message (id, session_id, data) VALUES (?, ?, ?)", [
  ("malformed-one", "session-bad", "not json"),
  ("malformed-two", "session-bad", '{"role":"assistant","providerID":"opencode"'),
])
v2_rows = [
  ("zen-today", "session-one", "assistant", {
    "model": {"providerID": "opencode", "id": "kimi-k2.6"},
    "tokens": {"input": 607, "output": 36, "reasoning": 55,
               "cache": {"read": 6688, "write": 0}},
    "time": {"created": day_offset(0)},
  }),
  ("v2-zen", "session-four", "assistant", {
    "model": {"providerID": "opencode", "id": "gpt-5.6-terra"},
    "tokens": {"input": 300, "output": 40, "reasoning": 10,
               "cache": {"read": 20, "write": 5}},
    "time": {"created": day_offset(0)},
  }),
  ("v2-go", "session-v2-go", "assistant", {
    "model": {"providerID": "opencode-go", "id": "gpt-5.6-luna"},
    "tokens": {"input": 9000, "output": 9000},
    "time": {"created": day_offset(0)},
  }),
  ("v2-openai", "session-v2-openai", "assistant", {
    "model": {"providerID": "openai", "id": "gpt-5.6-sol"},
    "tokens": {"input": 9000, "output": 9000},
    "time": {"created": day_offset(0)},
  }),
  ("v2-user", "session-v2-user", "user", {
    "model": {"providerID": "opencode", "id": "gpt-5.6-terra"},
    "tokens": {"input": 9000, "output": 9000},
    "time": {"created": day_offset(0)},
  }),
]
conn.executemany(
  "INSERT INTO session_message (id, session_id, type, time_created, data) VALUES (?, ?, ?, ?, ?)",
  [(message_id, session_id, message_type, data["time"]["created"], json.dumps(data))
   for message_id, session_id, message_type, data in v2_rows],
)
conn.execute(
  "INSERT INTO session_message (id, session_id, type, time_created, data) VALUES (?, ?, ?, ?, ?)",
  ("v2-malformed", "session-v2-bad", "assistant", now_ms, "not json"),
)
conn.commit()

# Keep a writer transaction open while the collector reads the committed WAL.
conn.execute("BEGIN IMMEDIATE")
conn.execute("INSERT INTO message (id, session_id, data) VALUES (?, ?, ?)", (
  "uncommitted", "session-pending", json.dumps({
    "role": "assistant", "providerID": "opencode", "modelID": "pending",
    "tokens": {"input": 999, "output": 999}, "time": {"created": now_ms},
  }),
))
stats, complete = scanner.scan_opencode_db(db)
conn.rollback()
conn.close()

record = scanner.scan(db, force=True)

# First scan writes a dated cache. A later row is hidden by limits-only and
# revealed by force, matching the shared collector refresh contract.
scanner.cached_scan(db, 0)
cache_file = sorted((test_home / "cache" / "omarchy" / "agent-usage").glob("opencode-zen-scan-*.json"))[0]
cache_payload = json.loads(cache_file.read_text())
conn = sqlite3.connect(db)
conn.execute("INSERT INTO message (id, session_id, data) VALUES (?, ?, ?)", (
  "later", "session-later", json.dumps({
    "role": "assistant", "providerID": "opencode", "modelID": "kimi-k2.6",
    "tokens": {"input": 10, "output": 0}, "time": {"created": now_ms},
  }),
))
conn.commit()
conn.close()
cached_prompts = scanner.cached_scan(db, 900)["totalPrompts"]
forced_prompts = scanner.cached_scan(db, 0)["totalPrompts"]

# New OpenCode databases can expose session_message without the legacy message
# table. That remains a complete scan rather than an interrupted one.
v2_only_db = test_home / "v2-only" / "opencode.db"
v2_only_db.parent.mkdir(parents=True, exist_ok=True)
v2_only = sqlite3.connect(v2_only_db)
v2_only.execute("CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, time_created INTEGER NOT NULL, data TEXT NOT NULL)")
v2_only.execute(
  "INSERT INTO session_message (id, session_id, type, time_created, data) VALUES (?, ?, ?, ?, ?)",
  ("v2-only", "session-v2-only", "assistant", now_ms, json.dumps({
    "model": {"providerID": "opencode", "id": "kimi-k2.6"},
    "tokens": {"input": 12, "output": 3}, "time": {"created": now_ms},
  })),
)
v2_only.commit()
v2_only.close()
v2_only_stats, v2_only_complete = scanner.scan_opencode_db(v2_only_db)

# A database with the wrong schema is an incomplete scan and must not be cached.
broken_db = test_home / "broken" / "opencode.db"
broken_db.parent.mkdir(parents=True, exist_ok=True)
broken = sqlite3.connect(broken_db)
broken.execute("CREATE TABLE unrelated (id TEXT PRIMARY KEY)")
broken.commit()
broken.close()
os.environ["XDG_CACHE_HOME"] = str(test_home / "broken-cache")
broken_stats, broken_complete = scanner.scan_opencode_db(broken_db)
scanner.cached_scan(broken_db, 20)
broken_cache_files = list((test_home / "broken-cache" / "omarchy" / "agent-usage").glob("opencode-zen-scan-*.json"))

print(json.dumps({
  "stats": stats,
  "complete": complete,
  "record": {key: record[key] for key in (
    "schemaVersion", "id", "name", "ready", "hasLocalStats", "scope",
    "hasPromptStats", "tierLabel", "usageStatusText", "authHelpText", "limits"
  )},
  "cache": {
    "schemaVersion": cache_payload["schemaVersion"],
    "scanDate": cache_payload["scanDate"],
    "mode": f"{cache_file.stat().st_mode & 0o777:03o}",
    "cachedPrompts": cached_prompts,
    "forcedPrompts": forced_prompts,
  },
  "broken": {
    "totalPrompts": broken_stats["totalPrompts"],
    "complete": broken_complete,
    "cacheWritten": bool(broken_cache_files),
  },
  "v2Only": {
    "totalPrompts": v2_only_stats["totalPrompts"],
    "complete": v2_only_complete,
  },
}, separators=(",", ":")))
PY
)

[[ $(jq -c '.record' <<<"$result") == \
  '{"schemaVersion":1,"id":"opencode-zen","name":"OpenCode","ready":true,"hasLocalStats":true,"scope":"device","hasPromptStats":true,"tierLabel":"Zen · Pay as you go","usageStatusText":"","authHelpText":"","limits":[]}' ]] ||
  fail "OpenCode Zen collector follows the display record contract" "$result"
pass "OpenCode Zen collector follows the display record contract"

[[ $(jq -r '.complete' <<<"$result") == "true" ]] ||
  fail "OpenCode Zen collector reads a WAL database while a writer is active" "$result"
pass "OpenCode Zen collector reads a WAL database while a writer is active"

[[ $(jq -r '.stats.todayTotalTokens' <<<"$result") == "7761" ]] ||
  fail "OpenCode Zen collector totals verified input, output, reasoning, and cache tokens" "$result"
pass "OpenCode Zen collector totals verified input, output, reasoning, and cache tokens"

[[ $(jq -r '.stats.totalPrompts' <<<"$result") == "4" ]] ||
  fail "OpenCode Zen collector excludes Go, other providers, user rows, zero rows, and malformed JSON" "$result"
pass "OpenCode Zen collector excludes Go, other providers, user rows, zero rows, and malformed JSON"

[[ $(jq -r '.stats.totalSessions' <<<"$result") == "4" ]] ||
  fail "OpenCode Zen collector deduplicates message ids across database generations" "$result"
pass "OpenCode Zen collector deduplicates message ids across database generations"

[[ $(jq -r '.stats.activeDays' <<<"$result") == "3" ]] ||
  fail "OpenCode Zen collector counts all active dates" "$result"
pass "OpenCode Zen collector counts all active dates"

[[ $(jq -r '.stats.recentDays[-1].messageCount' <<<"$result") == "7761" ]] ||
  fail "OpenCode Zen collector builds the seven-day token series" "$result"
pass "OpenCode Zen collector builds the seven-day token series"

[[ $(jq -c '.stats.modelUsage["kimi-k2.6"]' <<<"$result") == \
  '{"inputTokens":657,"outputTokens":101,"cacheReadInputTokens":6688,"cacheCreationInputTokens":0}' ]] ||
  fail "OpenCode Zen collector preserves token splits and folds reasoning into output" "$result"
pass "OpenCode Zen collector preserves token splits and folds reasoning into output"

[[ $(jq -c '.stats.modelUsage["gpt-5.6-terra"]' <<<"$result") == \
  '{"inputTokens":300,"outputTokens":50,"cacheReadInputTokens":20,"cacheCreationInputTokens":5}' ]] ||
  fail "OpenCode Zen collector reads current session_message records" "$result"
pass "OpenCode Zen collector reads current session_message records"

[[ $(jq -c '.cache | {schemaVersion,mode,cachedPrompts,forcedPrompts}' <<<"$result") == \
  '{"schemaVersion":2,"mode":"644","cachedPrompts":4,"forcedPrompts":5}' ]] ||
  fail "OpenCode Zen collector caches local stats and honors forced refresh" "$result"
pass "OpenCode Zen collector caches local stats and honors forced refresh"

[[ $(jq -r '.cache.scanDate | length == 10' <<<"$result") == "true" ]] ||
  fail "OpenCode Zen collector dates its cache" "$result"
pass "OpenCode Zen collector dates its cache"

[[ $(jq -c '.broken' <<<"$result") == \
  '{"totalPrompts":0,"complete":false,"cacheWritten":false}' ]] ||
  fail "OpenCode Zen collector never caches an interrupted scan" "$result"
pass "OpenCode Zen collector never caches an interrupted scan"

[[ $(jq -c '.v2Only' <<<"$result") == '{"totalPrompts":1,"complete":true}' ]] ||
  fail "OpenCode Zen collector supports databases without the legacy message table" "$result"
pass "OpenCode Zen collector supports databases without the legacy message table"

# Pi sessions: the collector discovers Zen-originated assistant messages in
# ~/.pi/agent/sessions/*.jsonl and prefixes the model name so the panel shows
# the harness source.
PI_HOME=$(mktemp -d)
mkdir -p "$PI_HOME/.pi/agent/sessions" "$PI_HOME/.omp/agent/sessions"
cat > "$PI_HOME/.pi/agent/sessions/test.jsonl" <<'JSONL'
{"type":"message","id":"pi-zen-1","timestamp":"2026-08-21T12:00:00.000Z","message":{"role":"assistant","provider":"opencode","model":"kimi-k2.6","usage":{"input":100,"output":50,"cacheRead":10,"cacheWrite":5,"totalTokens":165}}}
{"type":"message","id":"pi-zen-2","timestamp":"2026-08-21T12:00:00.000Z","message":{"role":"assistant","provider":"opencode","model":"big-pickle","usage":{"input":200,"output":100,"totalTokens":300}}}
{"type":"message","id":"pi-go-1","timestamp":"2026-08-21T12:00:00.000Z","message":{"role":"assistant","provider":"opencode-go","model":"kimi-k2.6","usage":{"input":999,"output":999,"totalTokens":1998}}}
{"type":"message","id":"pi-go-api-1","timestamp":"2026-08-21T12:00:00.000Z","message":{"role":"assistant","provider":"opencode-go","api":"opencode","model":"kimi-k2.6","usage":{"input":999,"output":999,"totalTokens":1998}}}
{"type":"message","id":"pi-legacy-zen-1","timestamp":"2026-08-21T12:00:00.000Z","message":{"role":"assistant","api":"opencode","model":"legacy-zen","usage":{"input":40,"output":10,"totalTokens":50}}}
{"type":"message","id":"pi-legacy-go-1","timestamp":"2026-08-21T12:00:00.000Z","message":{"role":"assistant","api":"opencode-go","model":"legacy-go","usage":{"input":999,"output":999,"totalTokens":1998}}}
{"type":"message","id":"pi-claude-1","timestamp":"2026-08-21T12:00:00.000Z","message":{"role":"assistant","provider":"anthropic","model":"claude-haiku","usage":{"input":999,"output":999,"totalTokens":1998}}}
{"type":"message","id":"pi-user-1","timestamp":"2026-08-21T12:00:00.000Z","message":{"role":"user","provider":"opencode","model":"kimi-k2.6","usage":{"input":999,"output":999,"totalTokens":1998}}}
JSONL
cat > "$PI_HOME/.omp/agent/sessions/test.jsonl" <<'JSONL'
{"type":"message","id":"omp-zen-1","timestamp":"2026-08-21T12:00:00.000Z","message":{"role":"assistant","provider":"opencode","model":"qwen3.6-plus","usage":{"input":80,"output":20,"cacheRead":5,"cacheWrite":0,"totalTokens":105}}}
JSONL

pi_only=$(HOME="$PI_HOME" XDG_DATA_HOME="$PI_HOME/.local/share" XDG_CACHE_HOME="$PI_HOME/.cache" "$ROOT/bin/omarchy-agent-usage-opencode-zen")

[[ $(jq -r '.totalPrompts' <<<"$pi_only") == "4" ]] ||
  fail "Zen collector counts only Pi and OMP assistant messages on the opencode provider" "$pi_only"
pass "Zen collector counts only Pi and OMP assistant messages on the opencode provider"

[[ $(jq -r '.modelUsage["Pi-kimi-k2.6"].inputTokens' <<<"$pi_only") == "100" ]] ||
  fail "Zen collector preserves Pi token splits" "$pi_only"
[[ $(jq -r '.modelUsage["Pi-kimi-k2.6"].outputTokens' <<<"$pi_only") == "50" ]] ||
  fail "Zen collector preserves Pi token splits" "$pi_only"
[[ $(jq -r '.modelUsage["Pi-kimi-k2.6"].cacheReadInputTokens' <<<"$pi_only") == "10" ]] ||
  fail "Zen collector preserves Pi token splits" "$pi_only"
[[ $(jq -r '.modelUsage["Pi-kimi-k2.6"].cacheCreationInputTokens' <<<"$pi_only") == "5" ]] ||
  fail "Zen collector preserves Pi token splits" "$pi_only"
pass "Zen collector preserves Pi token splits"

[[ $(jq -r '.modelUsage["Pi-big-pickle"].inputTokens' <<<"$pi_only") == "200" ]] ||
  fail "Zen collector counts multiple Pi models" "$pi_only"
pass "Zen collector counts multiple Pi models"

[[ $(jq -r '.modelUsage["Omp-qwen3.6-plus"].inputTokens' <<<"$pi_only") == "80" ]] ||
  fail "Zen collector counts OMP models" "$pi_only"
pass "Zen collector counts OMP models"

[[ $(jq -r '.modelUsage["Pi-kimi-k2.6"].inputTokens' <<<"$pi_only") == "100" ]] ||
  fail "Zen collector excludes Pi messages from OpenCode Go" "$pi_only"
pass "Zen collector excludes Pi messages from OpenCode Go"

[[ $(jq -r '.modelUsage["Pi-legacy-zen"].inputTokens' <<<"$pi_only") == "40" ]] ||
  fail "Zen collector accepts the exact legacy Pi API id when provider is absent" "$pi_only"
pass "Zen collector accepts the exact legacy Pi API id when provider is absent"

[[ $(jq -r '.modelUsage["Pi-claude-haiku"] // "missing"' <<<"$pi_only") == "missing" ]] ||
  fail "Zen collector excludes Pi messages from other providers" "$pi_only"
pass "Zen collector excludes Pi messages from other providers"

# The update runner must discover the collector by filename and write its id.
UPDATE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$UPDATE_HOME" "$PI_HOME"' EXIT
HOME="$UPDATE_HOME" XDG_DATA_HOME="$TEST_HOME/data" XDG_CACHE_HOME="$UPDATE_HOME/.cache" \
  XDG_STATE_HOME="$UPDATE_HOME/.state" OMARCHY_PATH="$ROOT" \
  "$ROOT/bin/omarchy-agent-usage-update" opencode-zen

written="$UPDATE_HOME/.state/omarchy/agents/usage/opencode-zen.json"
[[ -f $written && $(jq -r '.id + ":" + (.ready | tostring)' "$written") == "opencode-zen:true" ]] ||
  fail "Agent usage update discovers and writes the OpenCode Zen collector"
pass "Agent usage update discovers and writes the OpenCode Zen collector"
