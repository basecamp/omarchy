#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# Without a database or key the collector must still print a full, hidden-by-
# default record: the update runner writes whatever valid JSON appears on
# stdout, and a machine that never ran opencode shows no tab.
no_source=$(HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  OPENCODE_API_KEY='' "$ROOT/bin/omarchy-agent-usage-opencode-go")

[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + (.hasLocalStats | tostring)' <<<"$no_source") == "opencode-go:false:false" ]] ||
  fail "OpenCode Go collector prints a valid hidden record without a database or key" "$no_source"
[[ $(jq -r '((.limits | length) | tostring) + ":" + .authHelpText' <<<"$no_source") == "0:" ]] ||
  fail "OpenCode Go collector stays clean (no limits, no auth hint) without a key" "$no_source"
pass "OpenCode Go collector prints a valid hidden record without a database or key"

# A subscription burned through opencode has no native session files; usage
# must come from opencode's message database, filtered to the opencode-go
# provider. Reasoning folds into output and the cache split stays separate.
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

def message(id, provider, model, role="assistant", input=0, output=0, reasoning=0, read=0, write=0, compact=False):
  payload = {
    "role": role,
    "providerID": provider,
    "modelID": model,
    "tokens": {"input": input, "output": output, "reasoning": reasoning, "cache": {"read": read, "write": write}},
    "time": {"created": now_ms},
  }
  return (id, "ses_1", now_ms, now_ms, json.dumps(payload, separators=(",", ":") if compact else None))

conn.executemany("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [
  message("m_1", "opencode-go", "kimi-k2.6", input=80, output=40, reasoning=5, read=30, compact=True),
  message("m_2", "anthropic", "claude-opus-5", input=999, output=999),
  message("m_3", "opencode-go", "kimi-k2.6", role="user", input=999, output=999),
  message("m_4", "opencode-go-proxy", "kimi-k2.6", input=999, output=999),
  message("m_5", "openai", "gpt-5.2-codex", input=999, output=999),
])
conn.commit()
conn.close()
PY

result=$(HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  OPENCODE_API_KEY='' "$ROOT/bin/omarchy-agent-usage-opencode-go" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "155" ]] ||
  fail "OpenCode Go collector counts opencode-go usage, reasoning included, from opencode sessions" "$result"
[[ $(jq -c '.modelUsage["kimi-k2.6"]' <<<"$result") == '{"inputTokens":80,"outputTokens":45,"cacheReadInputTokens":30,"cacheCreationInputTokens":0}' ]] ||
  fail "OpenCode Go collector does not double-count cache or reasoning tokens" "$result"
[[ $(jq -r '.todayPrompts' <<<"$result") == "1" && $(jq -r '.totalPrompts' <<<"$result") == "1" ]] ||
  fail "OpenCode Go collector counts one prompt for the one matching message" "$result"
pass "OpenCode Go collector counts opencode-go usage from opencode sessions"

# The provider match must be exact: prefix-colliding providers, other
# providers, and user messages stay out. Malformed rows must not abort the
# scan (json_valid guards the parse).
MALFORMED_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$MALFORMED_HOME"' EXIT

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

def good(input):
  return ("ses_1", now_ms, now_ms, json.dumps({
    "role": "assistant", "providerID": "opencode-go", "modelID": "kimi-k2.6",
    "tokens": {"input": input, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": now_ms},
  }))

rows = [("mm_1", *good(5))]
rows.append(("mm_2", *good(7)))
# Valid JSON followed by trailing garbage: json_valid turns this into a skip.
garbage = json.dumps({
  "role": "assistant", "providerID": "opencode-go", "modelID": "kimi-k2.6",
  "tokens": {"input": 999, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
  "time": {"created": now_ms}}) + " trailing-garbage"
rows.append(("mm_3", "ses_1", now_ms, now_ms, garbage))
# Not JSON at all.
rows.append(("mm_4", "ses_1", now_ms, now_ms, "this is not json"))
conn.executemany("INSERT INTO message VALUES (?, ?, ?, ?, ?)", rows)
conn.commit()
conn.close()
PY

result=$(HOME="$MALFORMED_HOME" XDG_DATA_HOME="$MALFORMED_HOME/.local/share" XDG_CACHE_HOME="$MALFORMED_HOME/.cache" \
  OPENCODE_API_KEY='' "$ROOT/bin/omarchy-agent-usage-opencode-go")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "12" ]] ||
  fail "OpenCode Go collector counts good rows past malformed ones" "$result"
pass "OpenCode Go collector counts good rows past malformed ones"

# A warm cache makes --limits-only cheap: local stats come from the last scan
# instead of another walk over the database, and --force bypasses it.
CACHE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$MALFORMED_HOME" "$CACHE_HOME"' EXIT

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
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", (
  "c_1", "ses_1", now_ms, now_ms, json.dumps({
    "role": "assistant", "providerID": "opencode-go", "modelID": "kimi-k2.6",
    "tokens": {"input": 5, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": now_ms},
  }),
))
conn.commit()
conn.close()
PY

result=$(HOME="$CACHE_HOME" XDG_DATA_HOME="$CACHE_HOME/.local/share" XDG_CACHE_HOME="$CACHE_HOME/.cache" \
  OPENCODE_API_KEY='' "$ROOT/bin/omarchy-agent-usage-opencode-go")
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "5" ]] ||
  fail "OpenCode Go collector writes a fresh local-stats cache on first scan" "$result"
cache_file=$(find "$CACHE_HOME/.cache/omarchy/agent-usage" -maxdepth 1 -name 'opencode-go-scan-*.json' -print -quit 2>/dev/null)
[[ -n "$cache_file" && -s "$cache_file" ]] ||
  fail "OpenCode Go collector leaves a cache file behind" "$result"
[[ $(jq -r '.schemaVersion' "$cache_file") == "1" && $(jq -r '.stats.todayTotalTokens' "$cache_file") == "5" ]] ||
  fail "OpenCode Go collector writes a versioned cache envelope" "$result"
pass "OpenCode Go collector writes a local-stats cache on first scan"

# A new opencode-go message changes what a scan would find; a --limits-only
# run must reuse the cached stats instead of rescanning.
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
    "role": "assistant", "providerID": "opencode-go", "modelID": "kimi-k2.6",
    "tokens": {"input": 10, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": now_ms},
  }),
))
conn.commit()
conn.close()
PY

result=$(HOME="$CACHE_HOME" XDG_DATA_HOME="$CACHE_HOME/.local/share" XDG_CACHE_HOME="$CACHE_HOME/.cache" \
  OPENCODE_API_KEY='' "$ROOT/bin/omarchy-agent-usage-opencode-go" --limits-only)
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "5" ]] ||
  fail "OpenCode Go collector --limits-only reuses cached local stats" "$result"
pass "OpenCode Go collector --limits-only reuses cached local stats"

result=$(HOME="$CACHE_HOME" XDG_DATA_HOME="$CACHE_HOME/.local/share" XDG_CACHE_HOME="$CACHE_HOME/.cache" \
  OPENCODE_API_KEY='' "$ROOT/bin/omarchy-agent-usage-opencode-go" --force)
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "15" ]] ||
  fail "OpenCode Go collector --force rescans past the cache" "$result"
pass "OpenCode Go collector --force rescans past the cache"

# The limits fetch and key resolution are exercised without the network by
# importing the module and stubbing urlopen, the same way the Fireworks
# scanner test stubs its client.
if ! HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  python3 - "$ROOT/bin/omarchy-agent-usage-opencode-go" "$TEST_HOME/.local/share" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import sys
import urllib.error
from pathlib import Path

loader = importlib.machinery.SourceFileLoader("opencode_go_collector", str(Path(sys.argv[1])))
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)

class FakeResponse:
  def __init__(self, payload):
    self.payload = payload
    self.status = 200
  def read(self):
    return json.dumps(self.payload).encode("utf-8")
  def __enter__(self):
    return self
  def __exit__(self, *args):
    return False

def respond(payload):
  return lambda *a, **k: FakeResponse(payload)

def http_error(code):
  def raiser(*a, **k):
    raise urllib.error.HTTPError("http://stub", code, "{}", {}, None)
  return raiser

# The endpoint reports percent as 0..100; a value of exactly 1 means 1% and
# must never be rescaled to 100. A fraction is scaled by the same rule.
scanner.urllib.request.urlopen = respond({"usage": {
  "rolling": {"status": "ok", "percent": 1, "resetsAt": "2026-08-16T06:00:00Z"},
  "weekly": {"status": "ok", "percent": 50, "resetsAt": "2026-08-17T00:00:00Z"},
  "monthly": {"status": "ok", "percent": 0.5, "resetsAt": "2026-08-28T00:00:00Z"},
}})
limits, usage_status, auth_help, retry = scanner.fetch_limits("sk-test", "https://stub")
assert [w["label"] for w in limits] == ["Rolling (5-hour)", "Weekly (7-day)", "Monthly (30-day)"]
assert limits[0]["percent"] == 0.01, limits[0]
assert limits[1]["percent"] == 0.5, limits[1]
assert limits[2]["percent"] == 0.005, limits[2]
assert limits[0]["resetsAt"] == "2026-08-16T06:00:00+00:00", limits[0]
assert usage_status == "" and auth_help == "" and retry is False

# A missing key is a clean no-op, not an error card.
limits, usage_status, auth_help, retry = scanner.fetch_limits("", "https://stub")
assert limits == [] and usage_status == "" and auth_help == "" and retry is False

# A 200 carrying no usage object — an error body, or a key the endpoint has
# nothing to say about — reads as no limits rather than raising.
for payload in ({}, {"usage": None}, {"usage": ["rolling"]}, {"error": "no subscription"}):
  scanner.urllib.request.urlopen = respond(payload)
  limits, usage_status, auth_help, retry = scanner.fetch_limits("sk-test", "https://stub")
  assert limits == [] and auth_help == "No usage data returned for this key.", (payload, limits, auth_help)

# The percentage is the number that decides whether the next prompt lands, so a
# window keeps its meter when the reset time is missing; the panel just drops
# the countdown.
scanner.urllib.request.urlopen = respond({"usage": {"rolling": {"status": "ok", "percent": 93}}})
limits, _, _, _ = scanner.fetch_limits("sk-test", "https://stub")
assert limits == [{"label": "Rolling (5-hour)", "percent": 0.93, "resetsAt": ""}], limits

# Auth failures map to stable help text and never reuse stale limits.
scanner.urllib.request.urlopen = http_error(401)
limits, usage_status, auth_help, retry = scanner.fetch_limits("sk-test", "https://stub")
assert auth_help == "opencode.ai rejected the API key.", auth_help
scanner.urllib.request.urlopen = http_error(403)
limits, usage_status, auth_help, retry = scanner.fetch_limits("sk-test", "https://stub")
assert auth_help == "This key has no OpenCode Go subscription.", auth_help

# The key must never travel over a non-HTTPS endpoint.
scanner.urllib.request.urlopen = respond({"usage": {
  "rolling": {"status": "ok", "percent": 10, "resetsAt": "2026-08-16T06:00:00Z"},
}})
limits, usage_status, auth_help, retry = scanner.fetch_limits("sk-test", "http://insecure")
assert limits == [] and usage_status == "OpenCode Go limits unavailable" and retry is False, (limits, usage_status, retry)
assert "HTTPS" in auth_help, auth_help

# Transient failures (429, 5xx, and network errors) reuse cached limits and
# ask the panel to retry, instead of blanking the meters.
os.environ["XDG_CACHE_HOME"] = str(Path(sys.argv[2]) / "cache")
scanner.urllib.request.urlopen = respond({"usage": {
  "rolling": {"status": "ok", "percent": 10, "resetsAt": "2026-08-16T06:00:00Z"},
}})
limits, _, _, _ = scanner.fetch_limits("sk-test", "https://stub")
assert limits and limits[0]["percent"] == 0.1, limits

scanner.urllib.request.urlopen = http_error(429)
limits, usage_status, auth_help, retry = scanner.fetch_limits("sk-test", "https://stub")
assert limits and limits[0]["percent"] == 0.1, limits
assert usage_status == "OpenCode Go limits stale" and auth_help == "" and retry is True, (usage_status, auth_help, retry)

scanner.urllib.request.urlopen = http_error(503)
limits, usage_status, auth_help, retry = scanner.fetch_limits("sk-test", "https://stub")
assert limits and limits[0]["percent"] == 0.1, limits
assert usage_status == "OpenCode Go limits stale" and auth_help == "" and retry is True, (usage_status, auth_help, retry)

def url_error(*a, **k):
  raise urllib.error.URLError("network down")

scanner.urllib.request.urlopen = url_error
limits, usage_status, auth_help, retry = scanner.fetch_limits("sk-test", "https://stub")
assert limits and limits[0]["percent"] == 0.1, limits
assert usage_status == "OpenCode Go limits stale" and auth_help == "" and retry is True, (usage_status, auth_help, retry)

# OPENCODE_API_KEY wins over opencode's own auth.json.
os.environ["XDG_DATA_HOME"] = sys.argv[2]
auth_path = Path(sys.argv[2]) / "opencode" / "auth.json"
auth_path.parent.mkdir(parents=True, exist_ok=True)
auth_path.write_text(json.dumps({"opencode-go": {"key": "sk-from-auth-file"}}))
os.environ["OPENCODE_API_KEY"] = "sk-from-env"
assert scanner.api_key() == "sk-from-env"
os.environ.pop("OPENCODE_API_KEY")
assert scanner.api_key() == "sk-from-auth-file"

print("limits and key checks ok")
PY
then
  fail "OpenCode Go collector limits and key resolution checks"
fi
pass "OpenCode Go collector maps limits, scales percent, and resolves keys"
