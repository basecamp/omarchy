#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

GROK_HOME="$TEST_HOME/.grok"
mkdir -p "$GROK_HOME/sessions/%2Fhome%2Fdev%2Fone/session-a" \
  "$GROK_HOME/sessions/%2Fhome%2Fdev%2Ftwo/session-b" \
  "$GROK_HOME/logs"

now=$(date +%s)

usage_line() {
  local prompt_id="$1" models="$2"
  jq -cn --argjson ts "$now" --arg id "$prompt_id" --argjson models "$models" \
    '{timestamp: $ts, method: "_x.ai/session/update", params: {update: {
      sessionUpdate: "turn_completed", prompt_id: $id, stop_reason: "end_turn",
      usage: {modelUsage: $models}}}}'
}

# Grok reports each completed turn on its own, with cache reads folded into
# inputTokens. Every record on disk also carries cacheCreationTokens, always
# zero so far, so the non-zero one below assumes it nests inside inputTokens
# the way cache reads do — symmetry, not an observed shape. The same
# prompt_id appears twice to stand in for a resumed or replayed transcript. A
# cancelled turn has no usage and is not a prompt.
{
  usage_line p1 '{"grok-4.5-build":{"inputTokens":100,"cachedReadTokens":60,"outputTokens":20,"reasoningTokens":5,"totalTokens":120}}'
  usage_line p1 '{"grok-4.5-build":{"inputTokens":100,"cachedReadTokens":60,"outputTokens":20,"reasoningTokens":5,"totalTokens":120}}'
  usage_line p2 '{"grok-4.5-build":{"inputTokens":80,"cachedReadTokens":50,"cacheCreationTokens":10,"outputTokens":10,"totalTokens":90}}'
  echo '{"timestamp":'"$now"',"method":"_x.ai/session/update","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"cancelled","stop_reason":"cancelled"}}}'
} >"$GROK_HOME/sessions/%2Fhome%2Fdev%2Fone/session-a/updates.jsonl"

# One turn answered by two models, plus a line the prefilter must skip.
{
  echo '{"timestamp":0,"method":"session/update","params":{"update":{"sessionUpdate":"agent_message_chunk","content":"noise"}}}'
  usage_line p3 '{"grok-4.5-build":{"inputTokens":200,"cachedReadTokens":150,"outputTokens":40,"totalTokens":240},"grok-4.5":{"inputTokens":100,"cachedReadTokens":0,"outputTokens":10,"totalTokens":110}}'
} >"$GROK_HOME/sessions/%2Fhome%2Fdev%2Ftwo/session-b/updates.jsonl"

credits_record() {
  local percent="$1" start="$2" end="$3"
  jq -cn --argjson percent "$percent" --arg start "$start" --arg end "$end" \
    '{ts: "2026-01-01T00:00:00Z", src: "shell", lvl: "info",
      msg: "billing: fetched credits config",
      ctx: {config: ({currentPeriod: {type: "USAGE_PERIOD_TYPE_WEEKLY", start: $start, end: $end}}
                     + (if $percent < 0 then {} else {creditUsagePercent: $percent} end)),
            subscriptionTier: "SuperGrok"}}'
}

write_credits_log() {
  credits_record "$@" >"$GROK_HOME/logs/unified.jsonl"
}

open_period_start=$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%S+00:00)
open_period_end=$(date -u -d '5 days' +%Y-%m-%dT%H:%M:%S+00:00)

# Port 9 is the discard port: the live credits call reaches nothing there,
# standing in for an xAI outage or a network the bar cannot see. Every run below
# needs a base URL of its own, or the collector would call the real endpoint.
run_collector() {
  HOME="$TEST_HOME" GROK_HOME="$GROK_HOME" \
    GROK_CLI_CHAT_PROXY_BASE_URL="${STUB_BASE:-http://127.0.0.1:9/v1}" \
    "$ROOT/bin/omarchy-agent-usage-grok" "$@"
}

# Without a usable token the collector never opens a socket, so every live case
# below would quietly become a no-token case instead of the one it names.
cat >"$GROK_HOME/auth.json" <<EOF
{"https://auth.x.ai::test": {"key": "test-token", "expires_at": "$(date -u -d '5 hours' +%Y-%m-%dT%H:%M:%SZ)"}}
EOF

# Serves one canned credits body so the live call can be given a reply that
# parses but cannot be used. The request path is recorded so a collector that
# wanders off /billing?format=credits cannot hide behind a 200.
cat >"$TEST_HOME/stub.py" <<'EOF'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

body = sys.argv[1].encode()
port_file = sys.argv[2]


class Handler(BaseHTTPRequestHandler):
  def do_GET(self):
    with open(port_file + ".path", "w") as handle:
      handle.write(self.path)
    self.send_response(200)
    self.send_header("Content-Type", "application/json")
    self.send_header("Content-Length", str(len(body)))
    self.end_headers()
    self.wfile.write(body)

  def log_message(self, *args):
    pass


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w") as handle:
  handle.write(str(server.server_port))
server.serve_forever()
EOF

STUB_PID=""
STUB_BASE=""
start_stub() {
  local port_file="$TEST_HOME/stub.port"
  rm -f "$port_file"
  python3 "$TEST_HOME/stub.py" "$1" "$port_file" &
  STUB_PID=$!
  for _ in $(seq 1 60); do
    [[ -s $port_file ]] && break
    sleep 0.1
  done
  [[ -s $port_file ]] || fail "Grok collector test could not start its stub credits endpoint" ""
  STUB_BASE="http://127.0.0.1:$(cat "$port_file")/v1"
}

stop_stub() {
  [[ -n $STUB_PID ]] && kill "$STUB_PID" 2>/dev/null
  wait "$STUB_PID" 2>/dev/null
  STUB_PID=""
  STUB_BASE=""
}

trap 'stop_stub; rm -rf "$TEST_HOME"' EXIT

write_credits_log 22.0 "$open_period_start" "$open_period_end"
result=$(run_collector)

# 120 + 90 from session-a, 350 from the two-model turn in session-b.
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "560" ]] ||
  fail "Grok collector sums each turn once" "$result"
pass "Grok collector sums each turn once"

[[ $(jq -r '.totalPrompts' <<<"$result") == "3" ]] ||
  fail "Grok collector counts one prompt per turn and ignores repeated prompt ids" "$result"
pass "Grok collector counts one prompt per turn and ignores repeated prompt ids"

[[ $(jq -r '.totalSessions' <<<"$result") == "2" ]] ||
  fail "Grok collector counts sessions by transcript" "$result"
pass "Grok collector counts sessions by transcript"

[[ $(jq -c '.modelUsage["grok-4.5-build"]' <<<"$result") == '{"inputTokens":110,"outputTokens":70,"cacheReadInputTokens":260,"cacheCreationInputTokens":10}' ]] ||
  fail "Grok collector does not double-count cache or reasoning tokens" "$result"
pass "Grok collector does not double-count cache or reasoning tokens"

[[ $(jq -c '.modelUsage["grok-4.5"]' <<<"$result") == '{"inputTokens":100,"outputTokens":10,"cacheReadInputTokens":0,"cacheCreationInputTokens":0}' ]] ||
  fail "Grok collector splits a turn across the models that served it" "$result"
pass "Grok collector splits a turn across the models that served it"

contract='{"schemaVersion":1,"id":"grok","name":"Grok","ready":true,"hasLocalStats":true,"recentDays":7,"usageStatusText":""}'
[[ $(jq -c '{schemaVersion, id, name, ready, hasLocalStats, recentDays: (.recentDays | length), usageStatusText}' <<<"$result") == "$contract" ]] ||
  fail "Grok collector prints the display-ready record contract" "$result"
pass "Grok collector prints the display-ready record contract"

[[ $(jq -c '.limits' <<<"$result") == '[{"label":"Weekly (7-day)","percent":0.22,"resetsAt":"'"$open_period_end"'"}]' ]] &&
  [[ $(jq -r '.tierLabel' <<<"$result") == "SuperGrok" ]] ||
  fail "Grok collector reads the weekly credit allowance from the CLI log" "$result"
pass "Grok collector reads the weekly credit allowance from the CLI log"

# A cached percentage belongs to the period it was fetched in. Once that period
# has ended the figure is the wrong week's, so the meter has to disappear.
write_credits_log 22.0 "$(date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%S+00:00)" \
  "$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S+00:00)"
expired=$(run_collector)

[[ $(jq -r '.limits | length' <<<"$expired") == "0" ]] ||
  fail "Grok collector drops a credit reading from a period that has ended" "$expired"
pass "Grok collector drops a credit reading from a period that has ended"

# Grok logs a config on every startup and not all of them carry a percentage,
# so the meter must come from the newest reading that has one — still this
# period's, because a closed period is rejected above.
{
  credits_record 20.0 "$open_period_start" "$open_period_end"
  credits_record -1 "$open_period_start" "$open_period_end"
} >"$GROK_HOME/logs/unified.jsonl"
walked_back=$(run_collector)

[[ $(jq -r '.limits[0].percent' <<<"$walked_back") == "0.2" ]] ||
  fail "Grok collector walks back to the newest usable credit reading" "$walked_back"
pass "Grok collector walks back to the newest usable credit reading"

# The live call must degrade to the log rather than lose the meter.
write_credits_log 22.0 "$open_period_start" "$open_period_end"
offline=$(run_collector)

[[ $(jq -r '.limits[0].percent' <<<"$offline") == "0.22" ]] &&
  [[ $(jq -r '.tierLabel' <<<"$offline") == "SuperGrok" ]] ||
  fail "Grok collector falls back to the log when the live credits call fails" "$offline"
pass "Grok collector falls back to the log when the live credits call fails"

# A 200 is not the same as an answer. This is the body grok 1.0.0 actually
# returns — the current window, no percentage anywhere — and it has to yield
# to the log rather than blank the meter.
start_stub "{\"config\":{\"currentPeriod\":{\"type\":\"USAGE_PERIOD_TYPE_WEEKLY\",\"start\":\"$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S+00:00)\",\"end\":\"$(date -u -d '6 days' +%Y-%m-%dT%H:%M:%S+00:00)\"},\"prepaidBalance\":{\"val\":0},\"onDemandCap\":{\"val\":0},\"onDemandUsed\":{\"val\":0},\"isUnifiedBillingUser\":true}}"
unusable=$(run_collector)
stop_stub

[[ $(jq -r '.limits[0].percent' <<<"$unusable") == "0.22" ]] ||
  fail "Grok collector falls back to the log when the live body carries no percentage" "$unusable"
pass "Grok collector falls back to the log when the live body carries no percentage"

# And a live body that is usable has to win over the log's older number.
start_stub "{\"config\":{\"creditUsagePercent\":44.0,\"currentPeriod\":{\"type\":\"USAGE_PERIOD_TYPE_WEEKLY\",\"start\":\"$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S+00:00)\",\"end\":\"$(date -u -d '6 days' +%Y-%m-%dT%H:%M:%S+00:00)\"}}}"
live=$(run_collector)
stop_stub

[[ $(jq -r '.limits[0].percent' <<<"$live") == "0.44" ]] &&
  [[ $(jq -r '.tierLabel' <<<"$live") == "SuperGrok" ]] &&
  [[ $(cat "$TEST_HOME/stub.port.path") == "/v1/billing?format=credits" ]] ||
  fail "Grok collector prefers a usable live reading over the log" "$live"
pass "Grok collector prefers a usable live reading over the log"

rm -f "$GROK_HOME/logs/unified.jsonl"
missing=$(run_collector)

[[ $(jq -r '.limits | length' <<<"$missing") == "0" ]] &&
  [[ $(jq -r '.totalPrompts' <<<"$missing") == "3" ]] &&
  [[ $(jq -r '.usageStatusText' <<<"$missing") == "Grok limits unavailable" ]] ||
  fail "Grok collector still reports tokens with no log to read limits from" "$missing"
pass "Grok collector still reports tokens with no log to read limits from"

# A turn from yesterday must not inflate today. local_day is easy to get
# wrong around UTC midnight — this machine's sessions stamp unix seconds.
mkdir -p "$GROK_HOME/sessions/%2Fhome%2Fdev%2Fthree/session-c"
yesterday=$(date -d 'yesterday 15:00:00' +%s)
yesterday_date=$(date -d 'yesterday 15:00:00' +%Y-%m-%d)
jq -cn --argjson ts "$yesterday" \
  '{timestamp: $ts, method: "_x.ai/session/update", params: {update: {
    sessionUpdate: "turn_completed", prompt_id: "old", stop_reason: "end_turn",
    usage: {modelUsage: {"grok-4.5-build":{"inputTokens":30,"outputTokens":10,"totalTokens":40}}}}}}' \
  >"$GROK_HOME/sessions/%2Fhome%2Fdev%2Fthree/session-c/updates.jsonl"
dated=$(run_collector)

[[ $(jq -r '.todayPrompts' <<<"$dated") == "3" ]] &&
  [[ $(jq -r '.todayTotalTokens' <<<"$dated") == "560" ]] &&
  [[ $(jq -r --arg day "$yesterday_date" '.recentDays[] | select(.date == $day) | .messageCount' <<<"$dated") == "40" ]] ||
  fail "Grok collector files a turn on the local day it happened" "$dated"
pass "Grok collector files a turn on the local day it happened"

# Interrupting a prompt and running it again reuses the prompt id, and the
# turn that spent the tokens is the second one. The cancelled record carries
# no usage key, so the prefilter is what drops it here.
mkdir -p "$GROK_HOME/sessions/%2Fhome%2Fdev%2Ffour/session-d"
{
  echo '{"timestamp":'"$now"',"method":"_x.ai/session/update","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"p4","stop_reason":"cancelled"}}}'
  usage_line p4 '{"grok-4.5-build":{"inputTokens":30,"cachedReadTokens":0,"outputTokens":10,"totalTokens":40}}'
} >"$GROK_HOME/sessions/%2Fhome%2Fdev%2Ffour/session-d/updates.jsonl"
retried=$(run_collector)

[[ $(jq -r '.todayTotalTokens' <<<"$retried") == "600" ]] &&
  [[ $(jq -r '.todayPrompts' <<<"$retried") == "4" ]] ||
  fail "Grok collector counts a retried turn whose cancelled attempt shared its id" "$retried"
pass "Grok collector counts a retried turn whose cancelled attempt shared its id"

# No sessions and no log is a machine that has never signed in: a full record
# the update runner can write, with nothing in it for the panel to show.
empty=$(GROK_HOME="$TEST_HOME/.grok-empty" HOME="$TEST_HOME" \
  GROK_CLI_CHAT_PROXY_BASE_URL="http://127.0.0.1:9/v1" "$ROOT/bin/omarchy-agent-usage-grok")

[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + (.totalPrompts | tostring)' <<<"$empty") == "grok:false:0" ]] ||
  fail "Grok collector prints a valid record with nothing installed" "$empty"
pass "Grok collector prints a valid record with nothing installed"
