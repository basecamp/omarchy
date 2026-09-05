#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

export HOME="$TEST_HOME"
export COPILOT_HOME="$TEST_HOME/copilot-state"
export XDG_CACHE_HOME="$TEST_HOME/.cache"
database="$COPILOT_HOME/session-store.db"
mkdir -p "$COPILOT_HOME"

python3 - "$database" <<'PY'
import sqlite3
import sys
from datetime import datetime, time, timedelta

database = sys.argv[1]
local_zone = datetime.now().astimezone().tzinfo
today = datetime.now().astimezone().date()

def timestamp(days_ago):
  return datetime.combine(today - timedelta(days=days_ago), time(12), local_zone).isoformat()

connection = sqlite3.connect(database)
connection.execute("""
  CREATE TABLE assistant_usage_events (
    session_id TEXT NOT NULL,
    turn_index INTEGER,
    model TEXT NOT NULL,
    input_tokens INTEGER,
    output_tokens INTEGER,
    cache_read_tokens INTEGER,
    cache_write_tokens INTEGER,
    reasoning_tokens INTEGER,
    created_at TEXT
  )
""")
connection.execute("""
  CREATE TABLE turns (
    session_id TEXT NOT NULL,
    turn_index INTEGER NOT NULL,
    timestamp TEXT
  )
""")
connection.executemany(
  "INSERT INTO assistant_usage_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
  [
    ("session-today", 0, "gpt-test", 100, 20, 60, 10, 7, timestamp(0)),
    ("session-today", 0, "claude-test", 50, 10, 20, 5, 3, timestamp(0)),
    ("session-today", 1, "gpt-test", 40, 5, 10, 0, 2, timestamp(0)),
    ("session-internal", 99, "gpt-test", 30, 5, 0, 0, 1, timestamp(0)),
    ("session-old", 0, "gpt-old", 10, 2, 0, 0, 1, timestamp(8)),
    ("session-empty", 0, "gpt-empty", None, None, None, None, None, timestamp(0)),
    ("session-invalid", 0, "gpt-invalid", 50, 10, 0, 0, 0, "not-a-date"),
  ],
)
connection.executemany(
  "INSERT INTO turns VALUES (?, ?, ?)",
  [
    ("session-today", 0, timestamp(0)),
    # This turn began yesterday, though its model call completed today.
    ("session-today", 1, timestamp(1)),
    ("session-old", 0, timestamp(8)),
    ("session-without-usage", 0, timestamp(0)),
  ],
)
connection.commit()
connection.close()
PY

result=$("$ROOT/bin/omarchy-agent-usage-copilot" --force)

[[ $(jq -r '.id + ":" + .name + ":" + .tabLabel + ":" + .tierLabel' <<<"$result") == \
  "copilot:GitHub Copilot CLI:Copilot:CLI usage" ]] ||
  fail "Copilot collector identifies its CLI-only scope" "$result"
pass "Copilot collector identifies its CLI-only scope"

[[ $(jq -c '{ready, hasLocalStats, hasPromptStats, todayPrompts, todaySessions, todayTotalTokens, totalPrompts, totalSessions, activeDays}' <<<"$result") == \
  '{"ready":true,"hasLocalStats":true,"hasPromptStats":true,"todayPrompts":1,"todaySessions":1,"todayTotalTokens":260,"totalPrompts":3,"totalSessions":3,"activeDays":2}' ]] ||
  fail "Copilot collector separates user turns from model-call usage" "$result"
pass "Copilot collector separates user turns from model-call usage"

[[ $(jq -c '.modelUsage["gpt-test"]' <<<"$result") == \
  '{"inputTokens":90,"outputTokens":30,"cacheReadInputTokens":70,"cacheCreationInputTokens":10}' ]] ||
  fail "Copilot collector separates fresh and cached input without adding reasoning twice" "$result"
pass "Copilot collector separates fresh and cached input without adding reasoning twice"

today=$(date +%Y-%m-%d)
yesterday=$(python3 -c 'from datetime import date, timedelta; print(date.today() - timedelta(days=1))')
[[ $(jq -r --arg day "$today" '.recentDays[] | select(.date == $day) | .messageCount' <<<"$result") == "260" ]] &&
  [[ $(jq -r --arg day "$yesterday" '.recentDays[] | select(.date == $day) | .messageCount' <<<"$result") == "0" ]] ||
  fail "Copilot collector attributes tokens to model-call dates" "$result"
pass "Copilot collector attributes tokens to model-call dates"

partial="$TEST_HOME/partial.db"
python3 - "$partial" <<'PY'
import sqlite3
import sys
from datetime import datetime

connection = sqlite3.connect(sys.argv[1])
connection.execute("""
  CREATE TABLE assistant_usage_events (
    session_id TEXT, model TEXT, input_tokens INTEGER, output_tokens INTEGER,
    cache_read_tokens INTEGER, cache_write_tokens INTEGER, created_at TEXT
  )
""")
connection.execute(
  "INSERT INTO assistant_usage_events VALUES (?, ?, ?, ?, ?, ?, ?)",
  ("retained-session", "gpt-retained", 10, 2, 0, 0, datetime.now().astimezone().isoformat()),
)
connection.commit()
connection.close()
PY

partial_result=$("$ROOT/bin/omarchy-agent-usage-copilot" --database "$partial" --force)
[[ $(jq -c '{ready, hasLocalStats, hasPromptStats, totalPrompts, totalSessions, todayTotalTokens}' <<<"$partial_result") == \
  '{"ready":true,"hasLocalStats":true,"hasPromptStats":false,"totalPrompts":0,"totalSessions":1,"todayTotalTokens":12}' ]] ||
  fail "Copilot collector keeps token history when user-turn metadata is unavailable" "$partial_result"
pass "Copilot collector keeps token history when user-turn metadata is unavailable"

empty="$TEST_HOME/empty.db"
python3 - "$empty" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
connection.execute("""
  CREATE TABLE assistant_usage_events (
    session_id TEXT, turn_index INTEGER, model TEXT, input_tokens INTEGER,
    output_tokens INTEGER, cache_read_tokens INTEGER, cache_write_tokens INTEGER,
    created_at TEXT
  )
""")
connection.execute("CREATE TABLE turns (session_id TEXT, turn_index INTEGER, timestamp TEXT)")
connection.commit()
connection.close()
PY

empty_result=$("$ROOT/bin/omarchy-agent-usage-copilot" --database "$empty" --force)
[[ $(jq -c '{ready, hasLocalStats, hasPromptStats, totalSessions}' <<<"$empty_result") == \
  '{"ready":false,"hasLocalStats":true,"hasPromptStats":true,"totalSessions":0}' ]] ||
  fail "Copilot collector keeps a readable empty database hidden" "$empty_result"
pass "Copilot collector keeps a readable empty database hidden"

missing=$(COPILOT_HOME="$TEST_HOME/missing" "$ROOT/bin/omarchy-agent-usage-copilot" --force --limits-only)
[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + (.totalPrompts | tostring)' <<<"$missing") == "copilot:false:0" ]] ||
  fail "Copilot collector prints a hidden record before first use" "$missing"
pass "Copilot collector prints a hidden record before first use"

malformed="$TEST_HOME/malformed.db"
python3 - "$malformed" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
connection.execute("CREATE TABLE assistant_usage_events (session_id TEXT, model TEXT)")
connection.commit()
connection.close()
PY

broken=$("$ROOT/bin/omarchy-agent-usage-copilot" --database "$malformed" --force 2>/dev/null)
[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + .usageStatusText' <<<"$broken") == \
  "copilot:false:GitHub Copilot usage unavailable" ]] ||
  fail "Copilot collector reports an incompatible core schema" "$broken"
pass "Copilot collector reports an incompatible core schema"

uncached=$(XDG_CACHE_HOME=/dev/null "$ROOT/bin/omarchy-agent-usage-copilot" --database "$partial" --force 2>/dev/null)
[[ $(jq -r '(.ready | tostring) + ":" + (.todayTotalTokens | tostring)' <<<"$uncached") == "true:12" ]] ||
  fail "Copilot collector scans directly when its cache is unavailable" "$uncached"
pass "Copilot collector scans directly when its cache is unavailable"

wal_result=$(COLLECTOR="$ROOT/bin/omarchy-agent-usage-copilot" DATABASE="$TEST_HOME/wal.db" python3 - <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import sqlite3
from datetime import datetime

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

connection = sqlite3.connect(os.environ["DATABASE"])
connection.execute("PRAGMA journal_mode = WAL")
connection.execute("""
  CREATE TABLE assistant_usage_events (
    session_id TEXT, model TEXT, input_tokens INTEGER, output_tokens INTEGER,
    cache_read_tokens INTEGER, cache_write_tokens INTEGER, created_at TEXT
  )
""")
connection.execute(
  "INSERT INTO assistant_usage_events VALUES (?, ?, ?, ?, ?, ?, ?)",
  ("wal-session", "gpt-wal", 25, 5, 0, 0, datetime.now().astimezone().isoformat()),
)
connection.commit()
print(json.dumps(collector.scan(collector.Path(os.environ["DATABASE"]))))
connection.close()
PY
)

[[ $(jq -r '(.ready | tostring) + ":" + (.todayTotalTokens | tostring)' <<<"$wal_result") == "true:30" ]] ||
  fail "Copilot collector reads committed data from an active WAL database" "$wal_result"
pass "Copilot collector reads committed data from an active WAL database"

# A normal refresh reuses a recent scan, while --force bypasses it.
cached=$("$ROOT/bin/omarchy-agent-usage-copilot" --force)
python3 - "$database" <<'PY'
import sqlite3
import sys
from datetime import datetime

connection = sqlite3.connect(sys.argv[1])
connection.execute(
  "INSERT INTO assistant_usage_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
  ("session-new", 0, "gpt-new", 10, 1, 0, 0, 0, datetime.now().astimezone().isoformat()),
)
connection.execute(
  "INSERT INTO turns VALUES (?, ?, ?)",
  ("session-new", 0, datetime.now().astimezone().isoformat()),
)
connection.commit()
connection.close()
PY

reused=$("$ROOT/bin/omarchy-agent-usage-copilot")
[[ $(jq -r '.totalSessions' <<<"$reused") == "$(jq -r '.totalSessions' <<<"$cached")" ]] ||
  fail "Copilot collector reuses a recent scan" "$reused"
pass "Copilot collector reuses a recent scan"

forced=$("$ROOT/bin/omarchy-agent-usage-copilot" --force)
[[ $(jq -r '.totalSessions' <<<"$forced") == "4" ]] ||
  fail "Copilot collector bypasses its scan cache on --force" "$forced"
pass "Copilot collector bypasses its scan cache on --force"

# A 30-second-old cache is valid for --limits-only but not a normal refresh.
cache_file=$(COLLECTOR="$ROOT/bin/omarchy-agent-usage-copilot" DATABASE="$database" python3 - <<'PY'
import importlib.machinery
import importlib.util
import os
from pathlib import Path

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)
print(collector.scan_cache_paths(Path(os.environ["DATABASE"]))[0])
PY
)
python3 - "$cache_file" <<'PY'
import os
import sys
import time

past = time.time() - 30
os.utime(sys.argv[1], (past, past))
PY

python3 - "$database" <<'PY'
import sqlite3
import sys
from datetime import datetime

connection = sqlite3.connect(sys.argv[1])
connection.execute(
  "INSERT INTO assistant_usage_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
  ("session-limits-only", 0, "gpt-new", 12, 2, 0, 0, 0, datetime.now().astimezone().isoformat()),
)
connection.commit()
connection.close()
PY

limits_only=$("$ROOT/bin/omarchy-agent-usage-copilot" --limits-only)
[[ $(jq -r '.todayTotalTokens' <<<"$limits_only") == "$(jq -r '.todayTotalTokens' <<<"$forced")" ]] ||
  fail "Copilot collector reuses local stats for --limits-only" "$limits_only"
pass "Copilot collector reuses local stats for --limits-only"

normal=$("$ROOT/bin/omarchy-agent-usage-copilot")
[[ $(jq -r '.todayTotalTokens' <<<"$normal") == "$(( $(jq -r '.todayTotalTokens' <<<"$forced") + 14 ))" ]] ||
  fail "Copilot collector expires a normal scan after 20 seconds" "$normal"
pass "Copilot collector expires a normal scan after 20 seconds"

# Even a fresh cache belongs to the day it was scanned, not merely its mtime.
python3 - "$cache_file" <<'PY'
import json
import sys
from datetime import date, timedelta

path = sys.argv[1]
cached = json.loads(open(path, encoding="utf-8").read())
cached["scanDate"] = (date.today() - timedelta(days=1)).isoformat()
open(path, "w", encoding="utf-8").write(json.dumps(cached))
PY

python3 - "$database" <<'PY'
import sqlite3
import sys
from datetime import datetime

connection = sqlite3.connect(sys.argv[1])
connection.execute(
  "INSERT INTO assistant_usage_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
  ("session-next-day-cache", 0, "gpt-new", 5, 1, 0, 0, 0, datetime.now().astimezone().isoformat()),
)
connection.commit()
connection.close()
PY

new_day=$("$ROOT/bin/omarchy-agent-usage-copilot" --limits-only)
[[ $(jq -r '.todayTotalTokens' <<<"$new_day") == "$(( $(jq -r '.todayTotalTokens' <<<"$normal") + 6 ))" ]] ||
  fail "Copilot collector rejects a cache from another local day" "$new_day"
pass "Copilot collector rejects a cache from another local day"

# Parallel refreshes serialize through one lock and leave one intact cache.
rm -f "$cache_file"
pids=()
for index in $(seq 1 8); do
  "$ROOT/bin/omarchy-agent-usage-copilot" >"$TEST_HOME/concurrent-$index.json" &
  pids+=($!)
done
for pid in "${pids[@]}"; do
  wait "$pid"
done

for output in "$TEST_HOME"/concurrent-*.json; do
  jq -e '.id == "copilot" and .ready == true' "$output" >/dev/null ||
    fail "Copilot collector writes valid output during concurrent scans" "$output"
done
[[ -z $(find "$XDG_CACHE_HOME/omarchy/agent-usage" -name '*.tmp' -print -quit) ]] ||
  fail "Copilot collector leaves no temporary cache files"
[[ $(stat -c '%a' "$cache_file") == "600" ]] ||
  fail "Copilot collector keeps cached usage private" "$(stat -c '%a' "$cache_file")"
pass "Copilot collector serializes concurrent scans and writes atomically"

grep -q 'text: modelData.providerTabLabel' "$ROOT/shell/plugins/agents/Panel.qml" ||
  fail "Agents panel uses the provider's compact tab label"
pass "Agents panel keeps long provider names out of compact tabs"
