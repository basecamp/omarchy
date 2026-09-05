#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# A shared helper: run the collector with a controlled env (no key, temp paths).
run_collector() {
  local home="$1"; shift
  HOME="$home" XDG_DATA_HOME="$home/.local/share" XDG_CACHE_HOME="$home/.cache" \
    "$ROOT/bin/omarchy-agent-usage-opencode-go" "$@"
}

# --------------------------------------------------------------------------
# 1. Record contract + SQL totals (no key)
# --------------------------------------------------------------------------
mkdir -p "$TEST_HOME/.local/share/opencode"
python3 - "$TEST_HOME/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1])
db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now = int(time.time() * 1000)
def msg(mid, provider, model, role="assistant", inp=0, out=0, reason=0, read=0, write=0, ts=None):
  return (mid, "ses_1", ts or now, ts or now, json.dumps({
    "role": role, "providerID": provider, "modelID": model,
    "tokens": {"input": inp, "output": out, "reasoning": reason, "cache": {"read": read, "write": write}},
    "time": {"created": ts or now},
  }))
conn.executemany("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [
  msg("m1", "opencode-go", "deepseek-v4-flash", inp=100, out=50, reason=7, read=25, write=10),
  msg("m2", "opencode-go", "deepseek-v4-flash", role="user", inp=999, out=999),
  msg("m3", "opencode", "deepseek-v4-flash", inp=999, out=999),
  msg("m4", "opencode-go-proxy", "deepseek-v4-flash", inp=999, out=999),
])
conn.execute("INSERT INTO message VALUES ('m5', 'ses_1', ?, ?, '[\"not\",\"an\",\"object\"]')", (now, now))
conn.commit(); conn.close()
PY

result=$(run_collector "$TEST_HOME" --force)
[[ $(jq -r '.id' <<<"$result") == "opencode-go" ]] ||
  fail "OpenCode collector identifies itself as opencode-go" "$result"
pass "OpenCode collector identifies itself as opencode-go"

[[ $(jq -r '.name' <<<"$result") == "OpenCode" ]] ||
  fail "OpenCode collector reports its display name" "$result"
pass "OpenCode collector reports its display name"

[[ $(jq -r '.tierLabel' <<<"$result") == "Go" ]] ||
  fail "OpenCode collector reports the Go tier label" "$result"
pass "OpenCode collector reports the Go tier label"

[[ $(jq -r '.hasLocalStats' <<<"$result") == "true" ]] ||
  fail "OpenCode collector reports local stats" "$result"
pass "OpenCode collector reports local stats"

[[ $(jq -r '.schemaVersion' <<<"$result") == "1" ]] ||
  fail "OpenCode collector emits a versioned record" "$result"
pass "OpenCode collector emits a versioned record"

[[ $(jq -r '.usageStatusText' <<<"$result") == "Waiting for auth" ]] ||
  fail "OpenCode collector reports missing auth without a key" "$result"
pass "OpenCode collector reports missing auth without a key"

[[ $(jq -c '.limits' <<<"$result") == "[]" ]] ||
  fail "OpenCode collector emits an empty limits list without a key" "$result"
pass "OpenCode collector emits an empty limits list without a key"

# SQL totals: only the one opencode-go assistant row counts; reasoning is
# included in the output side and cache read/write split out.
[[ $(jq -r '.dbStats.todayTotalTokens' <<<"$result") == "192" ]] ||
  fail "OpenCode collector counts opencode-go assistant usage once" "$result"
pass "OpenCode collector counts opencode-go assistant usage once"

[[ $(jq -c '.dbStats.modelUsage["deepseek-v4-flash"]' <<<"$result") == \
  '{"cacheCreation":10,"cacheRead":25,"input":100,"output":50,"reasoning":7}' ]] ||
  fail "OpenCode collector splits model usage into input/output/reasoning/cache" "$result"
pass "OpenCode collector splits model usage into input/output/reasoning/cache"

[[ $(jq -r '(.dbStats.totalPrompts|tostring) + "/" + (.dbStats.totalSessions|tostring)' <<<"$result") == "1/1" ]] ||
  fail "OpenCode collector ignores prefix-colliding providers, user messages, malformed rows" "$result"
pass "OpenCode collector ignores prefix-colliding providers, user messages, malformed rows"

[[ $(jq -r '.ready' <<<"$result") == "true" ]] ||
  fail "OpenCode collector is ready when usage exists" "$result"
pass "OpenCode collector is ready when usage exists"

# The envelope is versioned, dated, and carries the watermark bookkeeping.
cache_file=$(ls "$TEST_HOME/.cache/omarchy/agent-usage/"/opencode-scan-*.json 2>/dev/null | head -n1)
[[ -n $cache_file && -s $cache_file ]] ||
  fail "OpenCode collector leaves a scan envelope behind" "$result"
[[ $(jq -r '.schemaVersion' "$cache_file") == "3" && $(jq -r '.scanDate' "$cache_file") == "$(date +%Y-%m-%d)" ]] ||
  fail "OpenCode collector writes a versioned dated envelope" "$(cat "$cache_file")"
[[ $(jq -r '.bandMs' "$cache_file") == "600000" ]] ||
  fail "OpenCode collector records the incremental overlap band" "$(cat "$cache_file")"
[[ $(jq -r '.complete' "$cache_file") == "true" ]] ||
  fail "OpenCode collector marks a completed scan complete" "$(cat "$cache_file")"
[[ $(jq -r '.stats.todayTotalTokens' "$cache_file") == "192" ]] ||
  fail "OpenCode collector stores stats in the envelope" "$(cat "$cache_file")"
pass "OpenCode collector writes a versioned dated scan envelope"

# Cache files are locked down: 0600 files, 0700 directory.
[[ $(stat -c %a "$cache_file") == "600" ]] ||
  fail "OpenCode collector keeps cache files private (0600)" "$result"
[[ $(stat -c %a "$TEST_HOME/.cache/omarchy/agent-usage") == "700" ]] ||
  fail "OpenCode collector keeps the cache directory private (0700)" "$result"
pass "OpenCode collector locks down cache permissions"

# dbStats nests the full local-stats contract.
[[ $(jq -r '.dbStats | has("recentDays") and has("activeDates") and has("todayTokensByModel") and has("totalPrompts") and has("totalSessions")' <<<"$result") == "true" ]] ||
  fail "OpenCode collector nests the full dbStats contract" "$result"
pass "OpenCode collector nests the full dbStats contract"

[[ $(jq -r '.dbStats.recentDays | length' <<<"$result") == "7" ]] ||
  fail "OpenCode collector emits a 7-day recentDays window" "$result"
[[ $(jq -r '.dbStats.recentDays[6].date' <<<"$result") == "$(date +%Y-%m-%d)" ]] ||
  fail "OpenCode collector keys recentDays to the local date" "$result"
[[ $(jq -r '.dbStats.activeDates | type' <<<"$result") == "array" ]] ||
  fail "OpenCode collector emits activeDates as an array" "$result"
pass "OpenCode collector emits a well-formed dbStats window"

# An empty database means no usage yet: not ready.
EMPTY_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME"' EXIT
mkdir -p "$EMPTY_HOME/.local/share/opencode"
python3 - "$EMPTY_HOME/.local/share/opencode/opencode.db" <<'PY'
import sqlite3, sys
from pathlib import Path
db = Path(sys.argv[1]); db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
conn.commit(); conn.close()
PY
empty=$(run_collector "$EMPTY_HOME" --force)
[[ $(jq -r '.ready' <<<"$empty") == "false" ]] ||
  fail "OpenCode collector is not ready without usage" "$empty"
pass "OpenCode collector is not ready without usage"

# --------------------------------------------------------------------------
# 2. Corrupt cache recovery
# --------------------------------------------------------------------------
printf '[]' >"$cache_file"
result=$(run_collector "$TEST_HOME" --force)
[[ $(jq -r '.dbStats.todayTotalTokens' <<<"$result") == "192" ]] ||
  fail "OpenCode collector recovers from a corrupt cache file" "$result"
[[ $(jq -r '.schemaVersion' "$cache_file") == "3" ]] ||
  fail "OpenCode collector rewrites the cache after a corrupt read" "$result"
pass "OpenCode collector recovers from a corrupt cache file"

# --------------------------------------------------------------------------
# 3. FAST path serves the cache without opening SQLite
# --------------------------------------------------------------------------
fast=$(ROOT_DIR="$ROOT" TEST_HOME="$TEST_HOME" python3 - <<'PY'
import importlib.util, json, os, sys
from importlib.machinery import SourceFileLoader
from pathlib import Path
root = Path(os.environ["ROOT_DIR"])
spec = importlib.util.spec_from_loader("collector", SourceFileLoader("collector", str(root / "bin/omarchy-agent-usage-opencode-go")))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)

home = Path(os.environ["TEST_HOME"])
os.environ["XDG_DATA_HOME"] = str(home / ".local" / "share")
os.environ["XDG_CACHE_HOME"] = str(home / ".cache")

# Prime the cache with a full scan.
stats1 = c.scan_local(force=True)

# FAST path must not open SQLite at all.
def boom(*a, **k):
  raise RuntimeError("sqlite must not be touched on the FAST path")
c.sqlite3.connect = boom
stats2 = c.scan_local(force=False)
ok = stats1 == stats2
print(json.dumps({"same": ok, "todayTotalTokens": stats2["todayTotalTokens"], "totalPrompts": stats2["totalPrompts"]}))
PY
)
[[ $(jq -r '.same' <<<"$fast") == "true" ]] ||
  fail "OpenCode collector FAST path serves the cached scan unchanged" "$fast"
[[ $(jq -r '.todayTotalTokens' <<<"$fast") == "192" ]] ||
  fail "OpenCode collector FAST path returns the cached totals" "$fast"
pass "OpenCode collector FAST path serves the cache without SQLite"

# --------------------------------------------------------------------------
# 4. Incremental merge with new rows + overlap dedupe
# --------------------------------------------------------------------------
INCR_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$INCR_HOME"' EXIT
mkdir -p "$INCR_HOME/.local/share/opencode"
python3 - "$INCR_HOME/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1]); db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("r1", "ses_1", now, now, json.dumps({
  "role":"assistant","providerID":"opencode-go","modelID":"m1",
  "tokens":{"input":5,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},
  "time":{"created":now}})))
conn.commit(); conn.close()
PY

base=$(run_collector "$INCR_HOME" --force)
[[ $(jq -r '.dbStats.totalPrompts' <<<"$base") == "1" ]] ||
  fail "OpenCode collector scans the first incremental fixture" "$base"
pass "OpenCode collector scans the first incremental fixture"

# Add a new row and an in-band row 5 minutes below the watermark (bandWide):
# the in-band row was not in the previous overlap set, so it must be picked up.
python3 - "$INCR_HOME/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1])
conn = sqlite3.connect(db)
now = int(time.time() * 1000)
# r2: a brand-new row now; r3: a row 5 minutes below the current watermark
# (that was NOT present when the full scan ran), within the 10-minute band.
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("r2", "ses_2", now, now, json.dumps({
  "role":"assistant","providerID":"opencode-go","modelID":"m1",
  "tokens":{"input":10,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},
  "time":{"created":now}})))
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("r3", "ses_3", now - 300000, now - 300000, json.dumps({
  "role":"assistant","providerID":"opencode-go","modelID":"m1",
  "tokens":{"input":7,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},
  "time":{"created":now - 300000}})))
conn.commit(); conn.close()
PY

merged=$(run_collector "$INCR_HOME")
[[ $(jq -r '.dbStats.totalPrompts' <<<"$merged") == "3" ]] ||
  fail "OpenCode collector incrementally merges new and in-band rows" "$merged"
[[ $(jq -r '.dbStats.todayTotalTokens' <<<"$merged") == "22" ]] ||
  fail "OpenCode collector sums tokens across an incremental merge" "$merged"
[[ $(jq -r '.dbStats.recentDays[6].messageCount' <<<"$merged") == "22" ]] ||
  fail "OpenCode collector folds merged tokens into recentDays" "$merged"
[[ $(jq -r '.dbStats.activeDates[-1]' <<<"$merged") == "$(date +%Y-%m-%d)" ]] ||
  fail "OpenCode collector carries activeDates across an incremental merge" "$merged"
pass "OpenCode collector incrementally merges new and in-band rows"

# A second incremental (with a new row) must not double-count the rows that
# landed in the previous overlap band.
python3 - "$INCR_HOME/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1])
conn = sqlite3.connect(db)
now = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("r4", "ses_4", now, now, json.dumps({
  "role":"assistant","providerID":"opencode-go","modelID":"m1",
  "tokens":{"input":3,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},
  "time":{"created":now}})))
conn.commit(); conn.close()
PY
merged2=$(run_collector "$INCR_HOME")
[[ $(jq -r '.dbStats.totalPrompts' <<<"$merged2") == "4" ]] ||
  fail "OpenCode collector does not double-count rows already in the overlap band" "$merged2"
pass "OpenCode collector does not double-count rows already in the overlap band"

# --------------------------------------------------------------------------
# 5. --force bypasses the cache; --limits-only reuses it when db unchanged
# --------------------------------------------------------------------------
[[ $(jq -r '.dbStats.totalPrompts' <<<"$(run_collector "$INCR_HOME" --force)") == "4" ]] ||
  fail "OpenCode collector --force rescans past the cache" "$result"
pass "OpenCode collector --force rescans past the cache"

limits_only=$(run_collector "$INCR_HOME" --limits-only)
[[ $(jq -r '.dbStats.totalPrompts' <<<"$limits_only") == "4" ]] ||
  fail "OpenCode collector --limits-only reuses cached local stats" "$limits_only"
pass "OpenCode collector --limits-only reuses cached local stats"

# --------------------------------------------------------------------------
# 6. Band migration: an envelope with a different bandMs forces a full scan
# --------------------------------------------------------------------------
MIG_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$INCR_HOME" "$MIG_HOME"' EXIT
mkdir -p "$MIG_HOME/.local/share/opencode"
python3 - "$MIG_HOME/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1]); db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("a1", "ses_1", now, now, json.dumps({
  "role":"assistant","providerID":"opencode-go","modelID":"m1",
  "tokens":{"input":11,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},
  "time":{"created":now}})))
conn.commit(); conn.close()
PY
run_collector "$MIG_HOME" --force >/dev/null
mig_file=$(ls "$MIG_HOME/.cache/omarchy/agent-usage/"/opencode-scan-*.json)
# Rewrite the envelope to claim an older, different band width.
jq -c '.bandMs = 300000' "$mig_file" >"$mig_file.tmp" && mv "$mig_file.tmp" "$mig_file"
mig=$(run_collector "$MIG_HOME")
[[ $(jq -r '.dbStats.totalPrompts' <<<"$mig") == "1" ]] ||
  fail "OpenCode collector rescans when the band width changes (no double count)" "$mig"
[[ $(jq -r '.bandMs' "$mig_file") == "600000" ]] ||
  fail "OpenCode collector rewrites the envelope with the current band" "$mig"
pass "OpenCode collector handles band migration with a full scan"

# --------------------------------------------------------------------------
# 7. Day rollover forces a full scan
# --------------------------------------------------------------------------
roll=$(jq -c '.scanDate = "1999-01-01"' "$mig_file" >"$mig_file.tmp" && mv "$mig_file.tmp" "$mig_file")
result=$(run_collector "$MIG_HOME")
[[ $(jq -r '.dbStats.totalPrompts' <<<"$result") == "1" ]] ||
  fail "OpenCode collector rescans on a day rollover" "$result"
[[ $(jq -r '.scanDate' "$mig_file") == "$(date +%Y-%m-%d)" ]] ||
  fail "OpenCode collector stamps a fresh envelope on rollover" "$result"
pass "OpenCode collector treats a cache from another day as a miss"

# --------------------------------------------------------------------------
# 8. --force reflects deleted rows; a shrunken table forces a full scan
# --------------------------------------------------------------------------
FORCE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$INCR_HOME" "$MIG_HOME" "$FORCE_HOME"' EXIT
mkdir -p "$FORCE_HOME/.local/share/opencode"
python3 - "$FORCE_HOME/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1]); db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now = int(time.time() * 1000)
def row(mid, ts):
  conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", (mid, "s", ts, ts, json.dumps({
    "role":"assistant","providerID":"opencode-go","modelID":"m1",
    "tokens":{"input":1,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},
    "time":{"created":ts}})))
for i in range(5):
  row(f"f{i}", now + i)
conn.commit(); conn.close()
PY
[[ $(jq -r '.dbStats.totalPrompts' <<<"$(run_collector "$FORCE_HOME" --force)") == "5" ]] ||
  fail "OpenCode collector scans five force fixtures" "$result"
pass "OpenCode collector scans five force fixtures"

# Delete the newest rows so the db max drops below the cached watermark: a
# non-forced run must detect the shrink and do a full scan.
python3 - "$FORCE_HOME/.local/share/opencode/opencode.db" <<'PY'
import sqlite3, sys
from pathlib import Path
conn = sqlite3.connect(sys.argv[1])
conn.execute("DELETE FROM message WHERE id IN ('f3','f4')")
conn.commit(); conn.close()
PY
shrunken=$(run_collector "$FORCE_HOME")
[[ $(jq -r '.dbStats.totalPrompts' <<<"$shrunken") == "3" ]] ||
  fail "OpenCode collector reflects a shrunken table with a full scan" "$shrunken"
pass "OpenCode collector reflects a shrunken table with a full scan"

python3 - "$FORCE_HOME/.local/share/opencode/opencode.db" <<'PY'
import sqlite3, sys
from pathlib import Path
conn = sqlite3.connect(sys.argv[1])
conn.execute("DELETE FROM message WHERE id = 'f2'")
conn.commit(); conn.close()
PY
forced=$(run_collector "$FORCE_HOME" --force)
[[ $(jq -r '.dbStats.totalPrompts' <<<"$forced") == "2" ]] ||
  fail "OpenCode collector --force reflects deleted rows" "$forced"
pass "OpenCode collector --force reflects deleted rows"

# --------------------------------------------------------------------------
# 9. Timestamp unit guard: a seconds-scale column still buckets by day
# --------------------------------------------------------------------------
SECS_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$INCR_HOME" "$MIG_HOME" "$FORCE_HOME" "$SECS_HOME"' EXIT
mkdir -p "$SECS_HOME/.local/share/opencode"
python3 - "$SECS_HOME/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1]); db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now = int(time.time())  # seconds, not ms
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("s1", "ses_1", now, now, json.dumps({
  "role":"assistant","providerID":"opencode-go","modelID":"m1",
  "tokens":{"input":9,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},
  "time":{"created":now * 1000}})))
conn.commit(); conn.close()
PY
secs=$(run_collector "$SECS_HOME" --force)
[[ $(jq -r '.dbStats.todayTotalTokens' <<<"$secs") == "9" ]] ||
  fail "OpenCode collector guards against seconds-scale timestamps" "$secs"
[[ $(jq -r '.dbStats.recentDays[-1].messageCount' <<<"$secs") == "9" ]] ||
  fail "OpenCode collector buckets a seconds-scale row into today" "$secs"
pass "OpenCode collector guards against seconds-scale timestamps"

# --------------------------------------------------------------------------
# 10. Malformed rows survive via json_valid
# --------------------------------------------------------------------------
MAL_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$INCR_HOME" "$MIG_HOME" "$FORCE_HOME" "$SECS_HOME" "$MAL_HOME"' EXIT
mkdir -p "$MAL_HOME/.local/share/opencode"
python3 - "$MAL_HOME/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1]); db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now = int(time.time() * 1000)
def row(mid, inp):
  return (mid, "s", now, now, json.dumps({"role":"assistant","providerID":"opencode-go","modelID":"m1",
    "tokens":{"input":inp,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":now}},
    separators=(",",":")))
conn.executemany("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [row("x1",5), row("x2",7)])
good = json.dumps({"role":"assistant","providerID":"opencode-go","modelID":"m1",
  "tokens":{"input":999,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":now}})
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("x3","s",now,now,good + " trailing-garbage"))
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("x4","s",now,now,"this is not json"))
conn.commit(); conn.close()
PY
mal=$(run_collector "$MAL_HOME" --force)
[[ $(jq -r '.dbStats.todayTotalTokens' <<<"$mal") == "12" ]] ||
  fail "OpenCode collector counts good rows past malformed ones" "$mal"
pass "OpenCode collector counts good rows past malformed ones"

# --------------------------------------------------------------------------
# 11. Unwritable cache still prints a complete record (valid JSON + limits)
# --------------------------------------------------------------------------
UNW_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$INCR_HOME" "$MIG_HOME" "$FORCE_HOME" "$SECS_HOME" "$MAL_HOME" "$UNW_HOME"' EXIT
mkdir -p "$UNW_HOME/.local/share/opencode"
python3 - "$UNW_HOME/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1]); db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("u1", "s", now, now, json.dumps({
  "role":"assistant","providerID":"opencode-go","modelID":"m1",
  "tokens":{"input":3,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":now}})))
conn.commit(); conn.close()
PY
touch "$UNW_HOME/not-a-dir"
unw_err=$(mktemp)
unw=$(HOME="$UNW_HOME" XDG_DATA_HOME="$UNW_HOME/.local/share" XDG_CACHE_HOME="$UNW_HOME/not-a-dir" \
  "$ROOT/bin/omarchy-agent-usage-opencode-go" --force 2>"$unw_err")
[[ $(jq -r '.dbStats.todayTotalTokens' <<<"$unw") == "3" ]] ||
  fail "OpenCode collector prints a complete record when the cache is unwritable" "$unw"
[[ $(jq -r 'has("limits") and has("dbStats") and has("usageStatusText")' <<<"$unw") == "true" ]] ||
  fail "OpenCode collector keeps limits and dbStats present with an unwritable cache" "$unw"
grep -qi "cache unavailable" "$unw_err" ||
  fail "OpenCode collector warns on stderr about an unwritable cache" "$(cat "$unw_err")"
pass "OpenCode collector degrades when the cache is unwritable"

# --------------------------------------------------------------------------
# 12. Empty XDG_CACHE_HOME falls back to ~/.cache
# --------------------------------------------------------------------------
CLEAN_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$INCR_HOME" "$MIG_HOME" "$FORCE_HOME" "$SECS_HOME" "$MAL_HOME" "$UNW_HOME" "$CLEAN_HOME"' EXIT
mkdir -p "$CLEAN_HOME/.local/share/opencode"
python3 - "$CLEAN_HOME/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1]); db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("c1", "s", now, now, json.dumps({
  "role":"assistant","providerID":"opencode-go","modelID":"m1",
  "tokens":{"input":2,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":now}})))
conn.commit(); conn.close()
PY
clean=$(HOME="$CLEAN_HOME" XDG_DATA_HOME="$CLEAN_HOME/.local/share" XDG_CACHE_HOME="" \
  "$ROOT/bin/omarchy-agent-usage-opencode-go" --force)
[[ $(jq -r '.dbStats.todayTotalTokens' <<<"$clean") == "2" ]] ||
  fail "OpenCode collector treats an empty XDG_CACHE_HOME as unset" "$clean"
[[ -n $(ls "$CLEAN_HOME/.cache/omarchy/agent-usage/"/opencode-scan-*.json 2>/dev/null) ]] ||
  fail "OpenCode collector writes to ~/.cache with an empty XDG_CACHE_HOME" "$clean"
pass "OpenCode collector treats an empty XDG_CACHE_HOME as unset"

# --------------------------------------------------------------------------
# 13. Stale *.tmp files are swept
# --------------------------------------------------------------------------
SWEEP_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$INCR_HOME" "$MIG_HOME" "$FORCE_HOME" "$SECS_HOME" "$MAL_HOME" "$UNW_HOME" "$CLEAN_HOME" "$SWEEP_HOME"' EXIT
mkdir -p "$SWEEP_HOME/.local/share/opencode" "$SWEEP_HOME/.cache/omarchy/agent-usage"
python3 - "$SWEEP_HOME/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1]); db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("w1", "s", now, now, json.dumps({
  "role":"assistant","providerID":"opencode-go","modelID":"m1",
  "tokens":{"input":1,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":now}})))
conn.commit(); conn.close()
PY
touch -d "2 hours ago" "$SWEEP_HOME/.cache/omarchy/agent-usage/stale.tmp"
touch "$SWEEP_HOME/.cache/omarchy/agent-usage/fresh.tmp"
run_collector "$SWEEP_HOME" --force >/dev/null
[[ ! -e "$SWEEP_HOME/.cache/omarchy/agent-usage/stale.tmp" ]] ||
  fail "OpenCode collector sweeps stale *.tmp files" "$result"
[[ -e "$SWEEP_HOME/.cache/omarchy/agent-usage/fresh.tmp" ]] ||
  fail "OpenCode collector leaves fresh *.tmp files alone" "$result"
pass "OpenCode collector sweeps stale *.tmp files"

# --------------------------------------------------------------------------
# 14. Multi-db channel selection
# --------------------------------------------------------------------------
CH_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$INCR_HOME" "$MIG_HOME" "$FORCE_HOME" "$SECS_HOME" "$MAL_HOME" "$UNW_HOME" "$CLEAN_HOME" "$SWEEP_HOME" "$CH_HOME"' EXIT
mkdir -p "$CH_HOME/.local/share/opencode"
touch "$CH_HOME/.local/share/opencode/opencode-default.db"
touch -d "2 hours ago" "$CH_HOME/.local/share/opencode/opencode-a.db"
touch -d "2 hours ago" "$CH_HOME/.local/share/opencode/opencode-a.db-wal"
touch "$CH_HOME/.local/share/opencode/opencode-b.db"
touch -d "1 minute ago" "$CH_HOME/.local/share/opencode/opencode-b.db-wal"
chosen=$(CH_HOME="$CH_HOME" python3 - <<'PY'
import importlib.util, os
from importlib.machinery import SourceFileLoader
from pathlib import Path
spec = importlib.util.spec_from_loader("collector", SourceFileLoader("collector", str(Path(os.environ["ROOT"])/"bin/omarchy-agent-usage-opencode-go")))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
root = Path(os.environ["CH_HOME"]) / ".local" / "share"
db, channel = c.choose_database(root)
print(f"{db.name}/{channel}")
PY
)
[[ $(echo "$chosen" | cut -d/ -f1) == "opencode-b.db" && $(echo "$chosen" | cut -d/ -f2) == "True" ]] ||
  fail "OpenCode collector prefers the freshest channel database" "$chosen"
pass "OpenCode collector prefers the freshest channel database"

# A channel db chosen for scanning is announced on stderr.
# Build a working channel db and confirm the "scanning channel database" log.
CHERR=$(mktemp)
python3 - "$CH_HOME/.local/share/opencode/opencode-b.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1]); db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("ch1", "s", now, now, json.dumps({
  "role":"assistant","providerID":"opencode-go","modelID":"m1",
  "tokens":{"input":4,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":now}})))
conn.commit(); conn.close()
PY
ch_out=$(HOME="$CH_HOME" XDG_DATA_HOME="$CH_HOME/.local/share" XDG_CACHE_HOME="$CH_HOME/.cache" \
  "$ROOT/bin/omarchy-agent-usage-opencode-go" --force 2>"$CHERR")
grep -q "scanning channel database opencode-b.db" "$CHERR" ||
  fail "OpenCode collector logs the chosen channel database" "$(cat "$CHERR")"
[[ $(jq -r '.dbStats.totalPrompts' <<<"$ch_out") == "1" ]] ||
  fail "OpenCode collector scans the chosen channel database" "$ch_out"
pass "OpenCode collector logs and scans the chosen channel database"

# With no channel databases, the plain opencode.db is chosen (not a channel).
DEF_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$INCR_HOME" "$MIG_HOME" "$FORCE_HOME" "$SECS_HOME" "$MAL_HOME" "$UNW_HOME" "$CLEAN_HOME" "$SWEEP_HOME" "$CH_HOME" "$DEF_HOME" "$INT_HOME"' EXIT
mkdir -p "$DEF_HOME/.local/share/opencode"
touch "$DEF_HOME/.local/share/opencode/opencode.db"
def_chosen=$(DEF_HOME="$DEF_HOME" python3 - <<'PY'
import importlib.util, os
from importlib.machinery import SourceFileLoader
from pathlib import Path
spec = importlib.util.spec_from_loader("collector", SourceFileLoader("collector", str(Path(os.environ["ROOT"])/"bin/omarchy-agent-usage-opencode-go")))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
db, channel = c.choose_database(Path(os.environ["DEF_HOME"]) / ".local" / "share")
print(f"{db.name}/{channel}")
PY
)
[[ $(echo "$def_chosen" | cut -d/ -f2) == "False" ]] ||
  fail "OpenCode collector uses the plain opencode.db when no channel exists" "$def_chosen"
pass "OpenCode collector uses the plain opencode.db when no channel exists"

# An insecure --api-base-url refuses to send the key and reports it clearly,
# while still printing a complete record.
INSEC_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$INCR_HOME" "$MIG_HOME" "$FORCE_HOME" "$SECS_HOME" "$MAL_HOME" "$UNW_HOME" "$CLEAN_HOME" "$SWEEP_HOME" "$CH_HOME" "$DEF_HOME" "$INT_HOME" "$INSEC_HOME"' EXIT
mkdir -p "$INSEC_HOME/.local/share/opencode"
python3 - "$INSEC_HOME/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1]); db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", ("i1", "s", now, now, json.dumps({
  "role":"assistant","providerID":"opencode-go","modelID":"m1",
  "tokens":{"input":6,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":now}})))
conn.commit(); conn.close()
PY
insec_err=$(mktemp)
insec=$(HOME="$INSEC_HOME" XDG_DATA_HOME="$INSEC_HOME/.local/share" XDG_CACHE_HOME="$INSEC_HOME/.cache" OPENCODE_GO_API_KEY="sk-test" \
  "$ROOT/bin/omarchy-agent-usage-opencode-go" --api-base-url "http://opencode.ai" --force 2>"$insec_err")
[[ $(jq -r '.dbStats.todayTotalTokens' <<<"$insec") == "6" ]] ||
  fail "OpenCode collector still prints local stats with an insecure base URL" "$insec"
[[ $(jq -r '.usageStatusText' <<<"$insec") == "OpenCode limits unavailable" ]] ||
  fail "OpenCode collector refuses to probe an insecure base URL" "$insec"
grep -qi "refusing to send API key" "$insec_err" ||
  fail "OpenCode collector warns on stderr about an insecure endpoint" "$(cat "$insec_err")"
pass "OpenCode collector refuses an insecure --api-base-url"

# --------------------------------------------------------------------------
# 15. Interrupted scan is never cached
# --------------------------------------------------------------------------
INT_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$INCR_HOME" "$MIG_HOME" "$FORCE_HOME" "$SECS_HOME" "$MAL_HOME" "$UNW_HOME" "$CLEAN_HOME" "$SWEEP_HOME" "$CH_HOME" "$INT_HOME"' EXIT
mkdir -p "$INT_HOME/.local/share/opencode"
# A database without the message table makes the scan fail mid-flight.
python3 - "$INT_HOME/.local/share/opencode/opencode.db" <<'PY'
import sqlite3, sys
from pathlib import Path
db = Path(sys.argv[1]); db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE unrelated (id text PRIMARY KEY)")
conn.commit(); conn.close()
PY
int_result=$(run_collector "$INT_HOME")
[[ $(jq -r '.dbStats.todayTotalTokens' <<<"$int_result") == "0" ]] ||
  fail "OpenCode collector reports what it could read from a broken database" "$int_result"
[[ -z $(ls "$INT_HOME/.cache/omarchy/agent-usage/"/opencode-scan-*.json 2>/dev/null) ]] ||
  fail "OpenCode collector must not cache an interrupted scan" "$int_result"
pass "OpenCode collector must not cache an interrupted scan"

# --------------------------------------------------------------------------
# 16. Limits: percent scale + both response shapes + normalize helpers
# --------------------------------------------------------------------------
limits_out=$(python3 - <<'PY'
import importlib.util, json, os
from importlib.machinery import SourceFileLoader
from pathlib import Path
spec = importlib.util.spec_from_loader("collector", SourceFileLoader("collector", str(Path(os.environ["ROOT"])/"bin/omarchy-agent-usage-opencode-go")))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)

# Deployed shape: three windows, percent-scaled (values >= 1).
deployed = {"usage": {
  "rolling": {"percent": 0.0, "resetsAt": 1234},
  "weekly": {"percent": 41.0, "resetsAt": 5678},
  "monthly": {"percent": 20.0, "resetsAt": 9012},
}}
r = c.parse_limits_payload(deployed)
out = {"deployed_ok": r["ok"], "deployed_labels": [l["label"] for l in r["limits"]],
       "deployed_percents": [l["percent"] for l in r["limits"]]}

# Upstream-PR shape: flat usagePercent / resetInSec.
pr = {"usagePercent": 25.0, "resetInSec": 3600}
r2 = c.parse_limits_payload(pr)
out["pr_ok"] = r2["ok"]
out["pr_percent"] = r2["limits"][0]["percent"] if r2["ok"] else None

# Fraction scale: no value >= 1 means 0..1 is kept as-is.
frac = {"usage": {"weekly": {"percent": 0.41, "resetsAt": ""}}}
r3 = c.parse_limits_payload(frac)
out["frac_percent"] = r3["limits"][0]["percent"] if r3["ok"] else None

# Empty / unparseable payloads.
out["empty_ok"] = c.parse_limits_payload({})["ok"]
out["list_ok"] = c.parse_limits_payload([])["ok"]

# redirect safety.
from urllib.request import Request
h = c.SafeRedirectHandler()
req = Request("https://opencode.ai/zen/go/v1/usage", headers={"Authorization": "Bearer k", "Accept": "application/json"})
same = h.redirect_request(req, None, 302, {}, {}, "https://opencode.ai/other")
cross = h.redirect_request(req, None, 302, {}, {}, "https://evil.example/other")
downgrade = h.redirect_request(req, None, 302, {}, {}, "http://opencode.ai/other")
out["same_keep"] = "Authorization" in same.headers
out["cross_strip"] = "Authorization" not in cross.headers
out["downgrade_strip"] = "Authorization" not in downgrade.headers
out["secure_https"] = c.api_base_is_secure("https://opencode.ai")
out["secure_http"] = c.api_base_is_secure("http://opencode.ai")
print(json.dumps(out, sort_keys=True))
PY
)
[[ $(jq -r '.deployed_ok' <<<"$limits_out") == "true" ]] ||
  fail "OpenCode collector parses the deployed limits shape" "$limits_out"
[[ $(jq -c '.deployed_labels' <<<"$limits_out") == '["Session (5-hour)","Weekly (7-day)","Monthly (30-day)"]' ]] ||
  fail "OpenCode collector maps the three limit windows to their labels" "$limits_out"
[[ $(jq -c '.deployed_percents' <<<"$limits_out") == '[0.0,0.41,0.2]' ]] ||
  fail "OpenCode collector normalizes percent-scaled limits to 0..1" "$limits_out"
[[ $(jq -r '.pr_ok' <<<"$limits_out") == "true" && $(jq -r '.pr_percent' <<<"$limits_out") == "0.25" ]] ||
  fail "OpenCode collector parses the upstream-PR usage shape" "$limits_out"
[[ $(jq -r '.frac_percent' <<<"$limits_out") == "0.41" ]] ||
  fail "OpenCode collector keeps fraction-scaled limits as-is" "$limits_out"
[[ $(jq -r '.empty_ok' <<<"$limits_out") == "false" && $(jq -r '.list_ok' <<<"$limits_out") == "false" ]] ||
  fail "OpenCode collector rejects empty or unexpected payloads" "$limits_out"
pass "OpenCode collector parses both limits shapes and normalizes the scale"

[[ $(jq -r '.same_keep' <<<"$limits_out") == "true" ]] ||
  fail "OpenCode collector keeps Authorization on a same-origin redirect" "$limits_out"
[[ $(jq -r '.cross_strip' <<<"$limits_out") == "true" ]] ||
  fail "OpenCode collector strips Authorization on a cross-origin redirect" "$limits_out"
[[ $(jq -r '.downgrade_strip' <<<"$limits_out") == "true" ]] ||
  fail "OpenCode collector strips Authorization on an https->http downgrade" "$limits_out"
[[ $(jq -r '.secure_https' <<<"$limits_out") == "true" && $(jq -r '.secure_http' <<<"$limits_out") == "false" ]] ||
  fail "OpenCode collector only accepts https API base URLs" "$limits_out"
pass "OpenCode collector guards redirects and API base URLs"

# collect_limits: freshness window, force bypass, and cache reuse.
collect_out=$(python3 - <<'PY'
import importlib.util, json, os
from importlib.machinery import SourceFileLoader
from pathlib import Path
spec = importlib.util.spec_from_loader("collector", SourceFileLoader("collector", str(Path(os.environ["ROOT"])/"bin/omarchy-agent-usage-opencode-go")))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
import tempfile
tmp = Path(tempfile.mkdtemp())
os.environ["XDG_CACHE_HOME"] = str(tmp / ".cache")

calls = {"n": 0}
def fake_probe(tok, base):
  calls["n"] += 1
  return {"ok": True, "limits": [{"label": "Weekly (7-day)", "percent": 0.41, "resetsAt": ""}]}
c.probe_limits = fake_probe

r1 = c.collect_limits("key", "https://opencode.ai", False, 20, False)
r2 = c.collect_limits("key", "https://opencode.ai", False, 20, False)  # within window -> reuse
after_r2 = calls["n"]
r3 = c.collect_limits("key", "https://opencode.ai", True, 20, False)   # force -> probe again
out = {"limits_len": len(r1["limits"]),
       "calls_after_r1_r2": after_r2, "calls_after_force": calls["n"],
       "cached_file": (tmp / ".cache/omarchy/agent-usage/opencode-limits.json").exists(),
       "waiting_auth": c.collect_limits("", "https://opencode.ai", False, 20, False)["usageStatusText"],
       "insecure_refused": c.collect_limits("key", "http://opencode.ai", False, 20, True)["usageStatusText"]}
print(json.dumps(out, sort_keys=True))
PY
)
[[ $(jq -r '.limits_len' <<<"$collect_out") == "1" ]] ||
  fail "OpenCode collector returns limits from a successful probe" "$collect_out"
[[ $(jq -r '.calls_after_r1_r2' <<<"$collect_out") == "1" ]] ||
  fail "OpenCode collector reuses the limits cache within the freshness window" "$collect_out"
[[ $(jq -r '.calls_after_force' <<<"$collect_out") == "2" ]] ||
  fail "OpenCode collector --force re-probes past the limits cache" "$collect_out"
[[ $(jq -r '.cached_file' <<<"$collect_out") == "true" ]] ||
  fail "OpenCode collector writes a limits cache file" "$collect_out"
[[ $(jq -r '.waiting_auth' <<<"$collect_out") == "Waiting for auth" ]] ||
  fail "OpenCode collector reports waiting for auth without a key" "$collect_out"
[[ $(jq -r '.insecure_refused' <<<"$collect_out") == "OpenCode limits unavailable" ]] ||
  fail "OpenCode collector refuses an insecure endpoint" "$collect_out"
pass "OpenCode collector caches, reuses, and forces the limits probe"

# Limits failure modes: each status maps to its own statusText + authHelpText.
failures=$(python3 - <<'PY'
import importlib.util, json, os
from importlib.machinery import SourceFileLoader
from pathlib import Path
spec = importlib.util.spec_from_loader("collector", SourceFileLoader("collector", str(Path(os.environ["ROOT"])/"bin/omarchy-agent-usage-opencode-go")))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)

def status_for(err):
  return c.http_error_result(err)

class E:
  def __init__(self, code): self.code = code
out = {}
out["unauth"] = status_for(E(401))["authHelpText"]
out["forbidden"] = status_for(E(403))["usageStatusText"]
out["server"] = status_for(E(502))["retryAdvised"]
out["rate"] = status_for(E(429))["retryAdvised"]

# Transport failure on the probe itself -> retryAdvised + transport.
real_build = c.urllib.request.build_opener
class Boom:
  def open(self, req, timeout=None): raise OSError("no route to host")
c.urllib.request.build_opener = lambda *a, **k: Boom()
try:
  p = c.probe_limits("k", "https://opencode.ai")
  out["transport_retry"] = p.get("retryAdvised") is True
  out["transport_ok"] = p["ok"] is False
finally:
  c.urllib.request.build_opener = real_build

# Empty payload -> rejected.
out["empty_auth"] = c.parse_limits_payload({})["authHelpText"]
# Fraction AND percent mixed: any value >= 1 flips the whole payload to percent.
mixed = {"usage": {"weekly": {"percent": 0.41}, "monthly": {"percent": 50.0}}}
r = c.parse_limits_payload(mixed)
out["mixed_weekly"] = r["limits"][0]["percent"]
out["mixed_monthly"] = r["limits"][1]["percent"]
print(json.dumps(out, sort_keys=True))
PY
)
[[ $(jq -r '.unauth' <<<"$failures") == *"rejected the key"* ]] ||
  fail "OpenCode collector maps 401 to an auth help message" "$failures"
pass "OpenCode collector maps 401/403 to an auth help message"
[[ $(jq -r '.forbidden' <<<"$failures") == "OpenCode limits unavailable" ]] ||
  fail "OpenCode collector sets a status text for a 403" "$failures"
[[ $(jq -r '.server' <<<"$failures") == "true" ]] ||
  fail "OpenCode collector advises retry on a 5xx" "$failures"
[[ $(jq -r '.rate' <<<"$failures") == "true" ]] ||
  fail "OpenCode collector advises retry on a 429" "$failures"
[[ $(jq -r '.transport_retry' <<<"$failures") == "true" && $(jq -r '.transport_ok' <<<"$failures") == "true" ]] ||
  fail "OpenCode collector marks a transport failure for retry" "$failures"
[[ $(jq -r '.empty_auth' <<<"$failures") == *"no limits"* ]] ||
  fail "OpenCode collector explains an empty limits payload" "$failures"
[[ $(jq -r '(.mixed_weekly*10000|round)' <<<"$failures") == "41" && $(jq -r '.mixed_monthly' <<<"$failures") == "0.5" ]] ||
  fail "OpenCode collector detects percent scale payload-wide" "$failures"
pass "OpenCode collector maps each limits failure mode distinctly"

# --------------------------------------------------------------------------
# 17. O_NOFOLLOW on the lock file
# --------------------------------------------------------------------------
nofollow=$(NOFOLLOW_HOME="$SWEEP_HOME" python3 - <<'PY'
import importlib.util, os
from importlib.machinery import SourceFileLoader
from pathlib import Path
spec = importlib.util.spec_from_loader("collector", SourceFileLoader("collector", str(Path(os.environ["ROOT"])/"bin/omarchy-agent-usage-opencode-go")))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
if not hasattr(os, "O_NOFOLLOW"):
  print("skip"); raise SystemExit(0)
root = Path(os.environ["NOFOLLOW_HOME"]) / ".cache/omarchy/agent-usage"
root.mkdir(parents=True, exist_ok=True)
lock = root / "opencode-nofollow.lock"
target = root / "target"
target.write_text("x")
lock.symlink_to(target.name)
try:
  c.acquire_lock(lock)
  print("followed")
except OSError as e:
  print("refused")
PY
)
if ! echo "$nofollow" | grep -qx "refused"; then
  fail "OpenCode collector refuses a symlinked lock file (O_NOFOLLOW)" "$nofollow"
fi
pass "OpenCode collector refuses a symlinked lock file (O_NOFOLLOW)"

# --------------------------------------------------------------------------
# 18. raceNoRegress: an older lower-watermark merge must not clobber a
#     fresher envelope.
# --------------------------------------------------------------------------
race=$(python3 - <<'PY'
import importlib.util, json, os, tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path
spec = importlib.util.spec_from_loader("collector", SourceFileLoader("collector", str(Path(os.environ["ROOT"])/"bin/omarchy-agent-usage-opencode-go")))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
tmp = Path(tempfile.mkdtemp())
os.environ["XDG_CACHE_HOME"] = str(tmp / ".cache")
cache_file, lock_file = tmp / ".cache/omarchy/agent-usage/opencode-scan-x.json", tmp / ".cache/omarchy/agent-usage/opencode-scan-x.lock"
cache_file.parent.mkdir(parents=True, exist_ok=True)
today = c.local_date_string()
# A fresh envelope already on disk with a high watermark.
fresh = {"schemaVersion":3, "scanDate": today, "watermark": 2000, "complete": True,
         "stats": c.empty_stats(), "dbMtime":1.0, "walMtime":1.0, "bandMs":c.INCREMENTAL_OVERLAP_MS,
         "todaySessionIds":[], "allSessionIds":[], "watermarkOverlap":[]}
c.write_envelope(cache_file, fresh)
# An older merge with a lower watermark tries to commit.
stale = dict(fresh); stale["watermark"] = 1000
result = c.commit_envelope(cache_file, lock_file, stale, force=False, mode="incremental")
final = c.read_envelope(cache_file)
print(json.dumps({"served": result["watermark"], "on_disk": final["watermark"]}))
PY
)
[[ $(jq -r '.on_disk' <<<"$race") == "2000" && $(jq -r '.served' <<<"$race") == "2000" ]] ||
  fail "OpenCode collector does not clobber a fresher envelope (raceNoRegress)" "$race"
pass "OpenCode collector does not clobber a fresher envelope (raceNoRegress)"

# --------------------------------------------------------------------------
# 19. rolloverNoClobber: a stale merge must not clobber a fresh today
#     full-scan result.
# --------------------------------------------------------------------------
roll2=$(python3 - <<'PY'
import importlib.util, json, os, tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path
spec = importlib.util.spec_from_loader("collector", SourceFileLoader("collector", str(Path(os.environ["ROOT"])/"bin/omarchy-agent-usage-opencode-go")))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
tmp = Path(tempfile.mkdtemp())
os.environ["XDG_CACHE_HOME"] = str(tmp / ".cache")
cache_file, lock_file = tmp/".cache/omarchy/agent-usage/opencode-scan-y.json", tmp/".cache/omarchy/agent-usage/opencode-scan-y.lock"
cache_file.parent.mkdir(parents=True, exist_ok=True)
today = c.local_date_string()
# A fresh today full-scan envelope with a high watermark.
fresh = {"schemaVersion":3, "scanDate": today, "watermark": 9000, "complete": True,
         "stats": c.empty_stats(), "dbMtime":1.0, "walMtime":1.0, "bandMs":c.INCREMENTAL_OVERLAP_MS,
         "todaySessionIds":[], "allSessionIds":[], "watermarkOverlap":[]}
c.write_envelope(cache_file, fresh)
# A stale merge (lower watermark, still same scanDate) must not clobber it.
stale = dict(fresh); stale["watermark"] = 100
result = c.commit_envelope(cache_file, lock_file, stale, force=False, mode="incremental")
final = c.read_envelope(cache_file)
# A full scan / --force MUST always overwrite, so deletions are reflected.
forced = c.commit_envelope(cache_file, lock_file, stale, force=True, mode="full")
final2 = c.read_envelope(cache_file)
print(json.dumps({"merge_on_disk": final["watermark"], "force_on_disk": final2["watermark"]}))
PY
)
[[ $(jq -r '.merge_on_disk' <<<"$roll2") == "9000" ]] ||
  fail "OpenCode collector stale merge does not clobber a fresh full scan" "$roll2"
[[ $(jq -r '.force_on_disk' <<<"$roll2") == "100" ]] ||
  fail "OpenCode collector full/force path always overwrites" "$roll2"
pass "OpenCode collector rollover merge does not clobber a fresh full scan"

# --------------------------------------------------------------------------
# 20. Extra hardening: lock perms, limits-cache degradation, session ids
# --------------------------------------------------------------------------
HARD_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$INCR_HOME" "$MIG_HOME" "$FORCE_HOME" "$SECS_HOME" "$MAL_HOME" "$UNW_HOME" "$CLEAN_HOME" "$SWEEP_HOME" "$CH_HOME" "$DEF_HOME" "$INT_HOME" "$INSEC_HOME" "$HARD_HOME"' EXIT
mkdir -p "$HARD_HOME/.local/share/opencode"
python3 - "$HARD_HOME/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1]); db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now = int(time.time() * 1000)
conn.executemany("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [
  ("h1", "sesA", now, now, json.dumps({"role":"assistant","providerID":"opencode-go","modelID":"m1",
    "tokens":{"input":1,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":now}})),
  ("h2", "sesB", now + 1, now + 1, json.dumps({"role":"assistant","providerID":"opencode-go","modelID":"m1",
    "tokens":{"input":2,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":now + 1}})),
])
conn.commit(); conn.close()
PY
run_collector "$HARD_HOME" --force >/dev/null
hard_lock=$(ls "$HARD_HOME/.cache/omarchy/agent-usage/"/opencode-scan-*.lock)
hard_file=$(ls "$HARD_HOME/.cache/omarchy/agent-usage/"/opencode-scan-*.json)
[[ $(stat -c %a "$hard_lock") == "600" ]] ||
  fail "OpenCode collector creates 0600 lock files" "$result"
pass "OpenCode collector creates 0600 lock files"

# Envelope session-id bookkeeping: two sessions, both with first messages today.
[[ $(jq -r '.todaySessionIds | length' "$hard_file") == "2" && $(jq -r '.allSessionIds | length' "$hard_file") == "2" ]] ||
  fail "OpenCode collector records session ids in the envelope" "$(cat "$hard_file")"
pass "OpenCode collector records session ids in the envelope"

# A corrupt limits cache degrades to a fresh probe without crashing.
hard_out=$(python3 - <<'PY'
import importlib.util, json, os, tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path
spec = importlib.util.spec_from_loader("collector", SourceFileLoader("collector", str(Path(os.environ["ROOT"])/"bin/omarchy-agent-usage-opencode-go")))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
tmp = Path(tempfile.mkdtemp())
os.environ["XDG_CACHE_HOME"] = str(tmp / ".cache")
limits_cache = tmp / ".cache/omarchy/agent-usage/opencode-limits.json"
limits_cache.parent.mkdir(parents=True, exist_ok=True)
limits_cache.write_text("not json at all")
calls = {"n": 0}
def probe(tok, base):
  calls["n"] += 1
  return {"ok": True, "limits": [{"label":"Weekly (7-day)","percent":0.5,"resetsAt":""}]}
c.probe_limits = probe
r = c.collect_limits("key", "https://opencode.ai", False, 20, False)
print(json.dumps({"len": len(r["limits"]), "calls": calls["n"]}))
PY
)
[[ $(jq -r '.len' <<<"$hard_out") == "1" && $(jq -r '.calls' <<<"$hard_out") == "1" ]] ||
  fail "OpenCode collector degrades from a corrupt limits cache" "$hard_out"
pass "OpenCode collector degrades from a corrupt limits cache"

# A transport failure propagates retryAdvised through collect_limits.
retry_out=$(python3 - <<'PY'
import importlib.util, json, os, tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path
spec = importlib.util.spec_from_loader("collector", SourceFileLoader("collector", str(Path(os.environ["ROOT"])/"bin/omarchy-agent-usage-opencode-go")))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
tmp = Path(tempfile.mkdtemp())
os.environ["XDG_CACHE_HOME"] = str(tmp / ".cache")
def probe(tok, base):
  return {"ok": False, "transport": True, "usageStatusText":"OpenCode limits unavailable",
          "authHelpText":"nope", "retryAdvised": True}
c.probe_limits = probe
r = c.collect_limits("key", "https://opencode.ai", False, 20, False)
print(json.dumps({"retry": r.get("retryAdvised") is True, "status": r["usageStatusText"]}))
PY
)
[[ $(jq -r '.retry' <<<"$retry_out") == "true" ]] ||
  fail "OpenCode collector propagates retryAdvised for a transport failure" "$retry_out"
[[ $(jq -r '.status' <<<"$retry_out") == "OpenCode limits unavailable" ]] ||
  fail "OpenCode collector reports an unavailable status for a transport failure" "$retry_out"
pass "OpenCode collector propagates retryAdvised for a transport failure"

# The limits cache reuse respects --cache-seconds: an expired cache re-probes.
expire_out=$(python3 - <<'PY'
import importlib.util, json, os, tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path
spec = importlib.util.spec_from_loader("collector", SourceFileLoader("collector", str(Path(os.environ["ROOT"])/"bin/omarchy-agent-usage-opencode-go")))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
tmp = Path(tempfile.mkdtemp())
os.environ["XDG_CACHE_HOME"] = str(tmp / ".cache")
limits_cache = tmp / ".cache/omarchy/agent-usage/opencode-limits.json"
limits_cache.parent.mkdir(parents=True, exist_ok=True)
limits_cache.write_text(json.dumps({"fetchedAtMs": int((__import__("time").time()-3600)*1000),
                                    "limits":[{"label":"Weekly (7-day)","percent":0.5,"resetsAt":""}]}))
calls = {"n": 0}
def probe(tok, base):
  calls["n"] += 1
  return {"ok": True, "limits": [{"label":"Weekly (7-day)","percent":0.9,"resetsAt":""}]}
c.probe_limits = probe
r = c.collect_limits("key", "https://opencode.ai", False, 20, False)
print(json.dumps({"calls": calls["n"], "percent": r["limits"][0]["percent"]}))
PY
)
[[ $(jq -r '.calls' <<<"$expire_out") == "1" && $(jq -r '.percent' <<<"$expire_out") == "0.9" ]] ||
  fail "OpenCode collector re-probes an expired limits cache" "$expire_out"
pass "OpenCode collector re-probes an expired limits cache"

# --------------------------------------------------------------------------
# 21. Session first-message semantics + limits-cache write degradation
# --------------------------------------------------------------------------
SESS_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$INCR_HOME" "$MIG_HOME" "$FORCE_HOME" "$SECS_HOME" "$MAL_HOME" "$UNW_HOME" "$CLEAN_HOME" "$SWEEP_HOME" "$CH_HOME" "$DEF_HOME" "$INT_HOME" "$INSEC_HOME" "$HARD_HOME" "$SESS_HOME"' EXIT
mkdir -p "$SESS_HOME/.local/share/opencode"
python3 - "$SESS_HOME/.local/share/opencode/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path
db = Path(sys.argv[1]); db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now = int(time.time() * 1000)
yesterday = now - 86400000
def row(mid, sess, ts):
  conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", (mid, sess, ts, ts, json.dumps({
    "role":"assistant","providerID":"opencode-go","modelID":"m1",
    "tokens":{"input":1,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":ts}})))
# Session A started yesterday (first message NOT today) but has a today message.
row("a1", "sesA", yesterday)
row("a2", "sesA", now)
# Session B started today.
row("b1", "sesB", now)
conn.commit(); conn.close()
PY
sess=$(run_collector "$SESS_HOME" --force)
[[ $(jq -r '.dbStats.totalPrompts' <<<"$sess") == "3" ]] ||
  fail "OpenCode collector counts all assistant messages across days" "$sess"
[[ $(jq -r '.dbStats.todayPrompts' <<<"$sess") == "2" ]] ||
  fail "OpenCode collector counts today's messages toward todayPrompts" "$sess"
[[ $(jq -r '.dbStats.todaySessions' <<<"$sess") == "1" ]] ||
  fail "OpenCode collector counts a session for today only by its first message" "$sess"
[[ $(jq -r '.dbStats.activeDays' <<<"$sess") == "2" ]] ||
  fail "OpenCode collector counts active days across both dates" "$sess"
pass "OpenCode collector applies session first-message semantics"

# A failing limits-cache write degrades to fresh limits with a stderr warning.
write_degrade=$(python3 - <<'PY'
import importlib.util, json, os, tempfile, sys
from importlib.machinery import SourceFileLoader
from pathlib import Path
spec = importlib.util.spec_from_loader("collector", SourceFileLoader("collector", str(Path(os.environ["ROOT"])/"bin/omarchy-agent-usage-opencode-go")))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
tmp = Path(tempfile.mkdtemp())
os.environ["XDG_CACHE_HOME"] = str(tmp / ".cache")
def probe(tok, base):
  return {"ok": True, "limits": [{"label":"Weekly (7-day)","percent":0.5,"resetsAt":""}]}
c.probe_limits = probe
# Force the write path to fail.
def boom_write(path, payload):
  raise OSError("disk full")
c.write_json = boom_write
r = c.collect_limits("key", "https://opencode.ai", False, 20, False)
print(json.dumps({"len": len(r["limits"]), "status": r["usageStatusText"]}))
PY
)
[[ $(jq -r '.len' <<<"$write_degrade") == "1" && $(jq -r '.status' <<<"$write_degrade") == "" ]] ||
  fail "OpenCode collector serves fresh limits when the limits cache write fails" "$write_degrade"
pass "OpenCode collector serves fresh limits when the limits cache write fails"
