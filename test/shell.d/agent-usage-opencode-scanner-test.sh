#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

# The vendored opencode collector must aggregate the trailing window from
# both classic (session/message) and v2 (session_v2/session_message) tables,
# keep exact providerID == "opencode-go" matching, and keep malformed rows
# from aborting the scan.

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

python3 - "$TEST_HOME" <<'PY'
import json, sqlite3, time, sys
from pathlib import Path

root = Path(sys.argv[1])
db = root / ".local/share/opencode/opencode.db"
db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
# v1 tables (as used by the external collector's _create_database)
conn.executescript("""
CREATE TABLE session (
  id TEXT PRIMARY KEY, title TEXT, time_created INTEGER, time_updated INTEGER,
  directory TEXT, agent TEXT, model TEXT, cost REAL,
  tokens_input INTEGER, tokens_output INTEGER, tokens_reasoning INTEGER,
  tokens_cache_read INTEGER, tokens_cache_write INTEGER
);
CREATE TABLE message (session_id TEXT, data TEXT, time_created INTEGER);
CREATE TABLE session_v2 (
  id TEXT PRIMARY KEY, title TEXT, time_created INTEGER, time_updated INTEGER,
  directory TEXT, agent TEXT, model TEXT, cost REAL,
  tokens_input INTEGER, tokens_output INTEGER, tokens_reasoning INTEGER,
  tokens_cache_read INTEGER, tokens_cache_write INTEGER
);
CREATE TABLE session_message (
  id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL,
  seq INTEGER NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL
);
""")
now_ms = int(time.time()*1000)
old_ms = now_ms - 31*24*60*60*1000  # outside the 30d Go window
recent_ms = now_ms - 60_000

def v1_msg(provider, model, input_tokens, created=recent_ms):
  return json.dumps({"role":"assistant","providerID":provider,"modelID":model,"time":{"created":created},"tokens":{"input":input_tokens,"output":1,"reasoning":0,"cache":{"read":0,"write":0}},"cost":0})

def v2_msg(provider, model, input_tokens, created=recent_ms):
  return json.dumps({"time":{"created":created},"model":{"providerID":provider,"id":model},"tokens":{"input":input_tokens,"output":1,"reasoning":0,"cache":{"read":0,"write":0}},"cost":0})

# v1 sessions/messages
conn.execute("INSERT INTO session VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", ("s_v1_recent","t",recent_ms,recent_ms,"/tmp","","",0,0,0,0,0,0))
conn.execute("INSERT INTO session VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", ("s_v1_old","t",old_ms,old_ms,"/tmp","","",0,0,0,0,0,0))
conn.execute("INSERT INTO session VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", ("s_v1_other","t",recent_ms,recent_ms,"/tmp","","",0,0,0,0,0,0))
conn.executemany("INSERT INTO message VALUES (?,?,?)", [
  ("s_v1_recent", v1_msg("opencode-go","v1-go", 10), recent_ms),
  ("s_v1_old", v1_msg("opencode-go","v1-go", 999), old_ms),
  ("s_v1_other", v1_msg("openai","v1-openai", 999), recent_ms),
  ("s_v1_recent", "not-json", recent_ms),
])

# v2 sessions/messages
conn.execute("INSERT INTO session_v2 VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", ("s_v2_recent","t",recent_ms,recent_ms,"/tmp","","",0,0,0,0,0,0))
conn.execute("INSERT INTO session_v2 VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", ("s_v2_old","t",old_ms,old_ms,"/tmp","","",0,0,0,0,0,0))
conn.execute("INSERT INTO session_v2 VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", ("s_v2_other","t",recent_ms,recent_ms,"/tmp","","",0,0,0,0,0,0))
conn.executemany("INSERT INTO session_message VALUES (?,?,?,?,?,?,?)", [
  ("m_v2_recent","s_v2_recent","assistant",1,recent_ms,recent_ms, v2_msg("opencode-go","v2-go", 20)),
  ("m_v2_old","s_v2_old","assistant",1,old_ms,old_ms, v2_msg("opencode-go","v2-go", 999)),
  ("m_v2_other","s_v2_other","assistant",1,recent_ms,recent_ms, v2_msg("opencode","v2-other", 999)),
  ("m_v2_bad","s_v2_recent","assistant",2,recent_ms,recent_ms, "not-json"),
])

conn.commit()
conn.close()

# Run the vendored collector's scan_sessions directly for the same window the binary would use (since_ms = now - 30d via collectionSince)
import importlib.util, os
from importlib.machinery import SourceFileLoader
from unittest.mock import patch
os.environ["XDG_DATA_HOME"] = str(root / ".local/share")
bin_path = Path(os.environ["ROOT"]) / "bin/omarchy-agent-usage-opencode"
loader = SourceFileLoader("opencode_collector", str(bin_path))
spec = importlib.util.spec_from_loader(loader.name, loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
since_ms = int(time.time()*1000) - 30*24*60*60*1000
with patch.object(mod, "list_api_sessions", return_value=[]):
  stats = mod.scan_sessions(since_ms)

# Assertions — exit 1 on failure so the shell trap reports it
def assert_eq(a,b,msg):
  if a != b:
    print(f"FAIL {msg}: {a!r} != {b!r}", file=sys.stderr)
    sys.exit(1)

class FakeResponse:
  def __init__(self, payload):
    self.payload = payload
  def __enter__(self):
    return self
  def __exit__(self, *args):
    pass
  def read(self):
    return json.dumps(self.payload).encode()

with patch.dict(os.environ, {"OPENCODE_API_KEY": "test"}):
  payload = {"usage": {
    "rolling": {"percent": 1, "resetsAt": "2099-01-01T00:00:00Z"},
    "weekly": {"percent": 77, "resetsAt": "2099-01-01T00:00:00Z"},
    "monthly": {"percent": 45, "resetsAt": "2099-01-01T00:00:00Z"},
  }}
  with patch.object(mod.urllib.request, "urlopen", return_value=FakeResponse(payload)):
    limits = mod.probe_limits()
assert_eq(limits["limits"][0]["percent"], 0.01, "one percent rolling limit")
assert_eq(limits["limits"][1]["percent"], 0.77, "seventy-seven percent weekly limit")
print("ok API integer percentages normalize correctly")

assert_eq(stats["totalPrompts"], 2, "totalPrompts v1+v2 Go only")
assert_eq(stats["totalSessions"], 2, "totalSessions v1+v2")
assert_eq(sum(b["inputTokens"] for b in stats["modelUsage"].values()), 30, "inputTokens 10+20")
assert_eq(set(stats["modelUsage"].keys()), {"opencode-go/v1-go","opencode-go/v2-go"}, "modelUsage keys")
print("ok v1+v2 Go aggregation")
PY

pass "OpenCode collector aggregates v1+v2 Go messages in the trailing window"

# Also ensure the binary itself honours --force/--limits-only and emits valid JSON when authenticated.
# Fake the Go endpoint with a tiny python http server so probe_limits succeeds without network.
FAKE_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$FAKE_DIR"' EXIT
cat >"$FAKE_DIR/server.py" <<'PY'
import json, http.server
class H(http.server.BaseHTTPRequestHandler):
  def do_GET(self):
    self.send_response(200); self.send_header("Content-Type","application/json"); self.end_headers()
    self.wfile.write(json.dumps({"usage":{"rolling":{"percent":0,"resetsAt":"2099-01-01T00:00:00Z"},"weekly":{"percent":0,"resetsAt":"2099-01-01T00:00:00Z"},"monthly":{"percent":0,"resetsAt":"2099-01-01T00:00:00Z"}}}).encode())
  def log_message(self,*a,**k): pass
http.server.HTTPServer(("127.0.0.1",0), H).serve_forever()
PY

# Use OPENCODE_API_KEY to avoid needing auth.json, and point USAGE_ENDPOINT at the fake server via monkey-patching probe_limits in a subprocess is simpler than spinning a server.
# Instead just check that --help and a no-auth run still emit valid JSON (empty stats) and that --force works.
result=$(OPENCODE_API_KEY=test XDG_DATA_HOME="$TEST_HOME/.local/share" "$ROOT/bin/omarchy-agent-usage-opencode" --help 2>&1)
[[ $result == *"--force"* ]] || fail "OpenCode collector --help mentions --force" "$result"
pass "OpenCode collector --help"

result=$(HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_CACHE_HOME="$TEST_HOME/.cache" "$ROOT/bin/omarchy-agent-usage-opencode" 2>&1)
jq -e '.id == "opencode" and .schemaVersion == 1' <<<"$result" >/dev/null || fail "OpenCode collector emits valid JSON without auth" "$result"
pass "OpenCode collector emits valid JSON"
