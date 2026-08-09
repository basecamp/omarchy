#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

test_root=$(mktemp -d)
server_pid=""
trap '[[ -n $server_pid ]] && kill "$server_pid" 2>/dev/null || true; rm -rf "$test_root"' EXIT

cat >"$test_root/server.py" <<'PY'
import json
import sys
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

port_file = sys.argv[1]

class Handler(BaseHTTPRequestHandler):
  def send_json(self, body, status=200, cookie=""):
    payload = json.dumps(body).encode()
    self.send_response(status)
    self.send_header("Content-Type", "application/json")
    self.send_header("Content-Length", str(len(payload)))
    if cookie:
      self.send_header("Set-Cookie", cookie)
    self.end_headers()
    self.wfile.write(payload)

  def do_GET(self):
    request = urlparse(self.path)
    path = request.path.removeprefix("/locked")
    locked = request.path.startswith("/locked/")
    protected = path.startswith("/api/analytics/") or path.startswith("/api/sessions")
    if locked and protected and "session=good" not in self.headers.get("Cookie", ""):
      self.send_json({"detail": "Unauthorized"}, 401)
      return
    if path == "/api/auth/providers":
      self.send_json({"providers": [{"name": "basic", "supports_password": True}]})
      return
    if path == "/api/auth/me":
      if "session=good" not in self.headers.get("Cookie", ""):
        self.send_json({"detail": "Unauthorized"}, 401)
      else:
        self.send_json({"display_name": "Meter Tester"})
      return
    if path == "/api/sessions":
      now = datetime.now().astimezone()
      rows = [{
          "id": "today",
          "started_at": now.timestamp(),
          "input_tokens": 100,
          "output_tokens": 40,
          "cache_read_tokens": 20,
          "reasoning_tokens": 12,
          "api_call_count": 5,
        }, {
          "id": "yesterday",
          "started_at": (now - timedelta(days=1)).timestamp(),
          "input_tokens": 30,
          "output_tokens": 10,
          "cache_read_tokens": 0,
          "reasoning_tokens": 0,
          "api_call_count": 1,
        }]
      offset = int(parse_qs(request.query).get("offset", ["0"])[0])
      limit = int(parse_qs(request.query).get("limit", ["20"])[0])
      body = {
        "sessions": rows[offset:offset + limit],
        "total": len(rows),
        "offset": offset,
        "limit": limit,
      }
    elif path.startswith("/api/analytics/models"):
      body = {"models": [{
        "provider": "ollama",
        "model": "future-coder:42b",
        "input_tokens": 100,
        "output_tokens": 40,
        "cache_read_tokens": 20,
        "reasoning_tokens": 12,
        "sessions": 2,
        "api_calls": 5,
      }]}
    else:
      self.send_error(404)
      return
    self.send_json(body)

  def do_POST(self):
    path = self.path.removeprefix("/locked")
    if path != "/auth/password-login":
      self.send_error(404)
      return
    length = int(self.headers.get("Content-Length", "0"))
    body = json.loads(self.rfile.read(length) or b"{}")
    if body.get("username") != "tester" or body.get("password") != "secret":
      self.send_json({"ok": False}, 401)
      return
    self.send_json({"ok": True}, cookie="session=good; Path=/; HttpOnly")

  def log_message(self, _format, *_args):
    pass

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="utf-8") as stream:
  stream.write(str(server.server_port))
server.serve_forever()
PY

python3 "$test_root/server.py" "$test_root/port" &
server_pid=$!
for _ in {1..50}; do
  [[ -s $test_root/port ]] && break
  sleep 0.05
done
[[ -s $test_root/port ]] || fail "fake Hermes analytics server did not start"
port=$(<"$test_root/port")

cat >"$test_root/config.json" <<EOF
{
  "sources": {
    "hermes": {
      "type": "hermes",
      "url": "http://127.0.0.1:$port",
      "name": "Hermes"
    },
    "locked": {
      "type": "hermes",
      "url": "http://127.0.0.1:$port/locked",
      "name": "Locked Hermes"
    }
  }
}
EOF

XDG_CONFIG_HOME="$test_root/config" XDG_STATE_HOME="$test_root/state" \
  "$ROOT/bin/omarchy-agent-meter" --config "$test_root/config.json" collect >/dev/null

record="$test_root/state/omarchy/agents/usage/hermes.json"
[[ -f $record ]] || fail "meter did not write an agents-panel record"
[[ $(jq -r '.todayTotalTokens' "$record") == 160 ]] ||
  fail "meter did not group timestamped token usage into the local day"
[[ $(jq -r '.todayPrompts' "$record") == 5 && $(jq -r '.todaySessions' "$record") == 1 ]] ||
  fail "meter did not group timestamped activity into the local day"
[[ $(jq -r --arg today "$(date +%F)" '.recentDays[] | select(.date == $today) | .messageCount' "$record") == 160 ]] ||
  fail "meter did not preserve the standard current-day row"
[[ $(jq -c '.modelLabels["ollama::future-coder:42b"]' "$record") == '{"provider":"ollama","model":"future-coder:42b"}' ]] ||
  fail "meter did not preserve dynamic provider and model attribution"
[[ $(jq -r '.modelUsage["ollama::future-coder:42b"].reasoningOutputTokens' "$record") == 12 ]] ||
  fail "meter did not preserve reasoning detail"
pass "system-wide meter converts remote Hermes sessions into local calendar days"

locked_record="$test_root/state/omarchy/agents/usage/locked.json"
[[ $(jq -r '.authRequired' "$locked_record") == true ]] ||
  fail "meter does not publish a login action when remote authentication expires"
pass "system-wide meter exposes remote authentication state"

printf '%s\n' '{"username":"tester","password":"secret"}' | \
  XDG_CONFIG_HOME="$test_root/config" XDG_STATE_HOME="$test_root/state" \
  "$ROOT/bin/omarchy-agent-meter" --config "$test_root/config.json" login locked --stdin >/dev/null ||
  fail "meter does not accept popup credentials over stdin"

XDG_CONFIG_HOME="$test_root/config" XDG_STATE_HOME="$test_root/state" \
  "$ROOT/bin/omarchy-agent-meter" --config "$test_root/config.json" collect locked >/dev/null ||
  fail "meter cannot collect after an inline login"
[[ $(jq -r '.authRequired' "$locked_record") == false ]] ||
  fail "meter remains unauthenticated after an inline login"
[[ $(stat -c '%a' "$test_root/state/omarchy/agent-meter/credentials/locked.cookies") == 600 ]] ||
  fail "meter credentials are not private"
pass "inline login restores remote collection without exposing credentials in argv"

fresh_config="$test_root/fresh-config/agent-meter.json"
printf '%s\n' "{\"url\":\"127.0.0.1:$port/locked\",\"username\":\"tester\",\"password\":\"secret\"}" | \
  XDG_CONFIG_HOME="$test_root/fresh-config" XDG_STATE_HOME="$test_root/fresh-state" \
  "$ROOT/bin/omarchy-agent-meter" --config "$fresh_config" login hermes --stdin >/dev/null ||
  fail "first-time popup login cannot create gateway configuration"
[[ $(jq -r '.sources.hermes.url' "$fresh_config") == "http://127.0.0.1:$port/locked" ]] ||
  fail "first-time popup login does not retain the gateway URL"
[[ $(stat -c '%a' "$fresh_config") == 600 ]] ||
  fail "gateway configuration permissions are not private"
pass "first-time popup login creates central gateway configuration"

XDG_CONFIG_HOME="$test_root/fresh-config" XDG_STATE_HOME="$test_root/fresh-state" \
  "$ROOT/bin/omarchy-agent-meter" --config "$fresh_config" local hermes >/dev/null ||
  fail "popup cannot switch back to local Hermes usage"
[[ $(jq -r '.sources.hermes.enabled' "$fresh_config") == false ]] ||
  fail "local usage does not disable remote collection"
[[ $(jq -r '.sources.hermes.url' "$fresh_config") == "http://127.0.0.1:$port/locked" ]] ||
  fail "local usage forgets the previous remote gateway URL"
pass "local usage preserves the remote gateway for later reconnection"

cookie_path="$test_root/fresh-state/omarchy/agent-meter/credentials/hermes.cookies"
cookie_before=$(sha256sum "$cookie_path" | cut -d' ' -f1)
XDG_CONFIG_HOME="$test_root/fresh-config" XDG_STATE_HOME="$test_root/fresh-state" \
  "$ROOT/bin/omarchy-agent-meter" --config "$fresh_config" remote hermes >/dev/null ||
  fail "switching back to remote usage does not reuse the saved login"
[[ $(jq -r '.sources.hermes.enabled' "$fresh_config") == true ]] ||
  fail "remote usage does not re-enable the saved gateway"
[[ $(jq -r '.authRequired' "$test_root/fresh-state/omarchy/agents/usage/hermes.json") == false ]] ||
  fail "remote usage asks for credentials despite a valid saved login"
cookie_after=$(sha256sum "$cookie_path" | cut -d' ' -f1)
[[ $cookie_after == "$cookie_before" ]] ||
  fail "switching usage sources replaced the saved gateway login"
pass "local and remote usage switches preserve a valid gateway login"
