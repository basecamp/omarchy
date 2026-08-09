#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# Local session files: two turns. The first today (grok-4.5, two chunks whose
# cumulative totalTokens peak at 1200), the second two days ago under another
# model. events.jsonl maps each turn start to its model id.
now_ms=$(( $(date +%s) * 1000 ))
old_ms=$(( ($(date +%s) - 2 * 86400) * 1000 ))
SESSION="$TEST_HOME/.grok/sessions/project/session-aaa"
mkdir -p "$SESSION"
cat >"$SESSION/events.jsonl" <<EOF
{"ts":"$(date -u -d "@$((now_ms / 1000))" +%Y-%m-%dT%H:%M:%SZ)","type":"turn_started","turn_number":0,"model_id":"grok-4.5","schema_version":"1.0"}
{"ts":"$(date -u -d "@$((old_ms / 1000))" +%Y-%m-%dT%H:%M:%SZ)","type":"turn_started","turn_number":1,"model_id":"grok-3","schema_version":"1.0"}
EOF
cat >"$SESSION/updates.jsonl" <<EOF
{"timestamp":$now_ms,"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_thought_chunk"},"_meta":{"totalTokens":1000,"promptId":"p1","turnStartMs":$now_ms,"streamStartMs":$now_ms,"updateType":"AgentThoughtChunk","chunkId":1}}}
{"timestamp":$((now_ms + 100)),"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk"},"_meta":{"totalTokens":1200,"promptId":"p1","turnStartMs":$now_ms,"streamStartMs":$now_ms,"updateType":"AgentMessageChunk","chunkId":2}}}
{"timestamp":$old_ms,"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk"},"_meta":{"totalTokens":500,"promptId":"p2","turnStartMs":$old_ms,"streamStartMs":$old_ms,"updateType":"AgentMessageChunk","chunkId":3}}}
EOF

# pi transcripts: an assistant message routed through the xai (Grok) provider,
# carrying a full input/output/cache split for the same grok-4.5 model.
mkdir -p "$TEST_HOME/.pi/agent/sessions/project"
cat >"$TEST_HOME/.pi/agent/sessions/project/session-pi.jsonl" <<EOF
{"type":"message","id":"pi-1","parentId":null,"timestamp":"$(date -u -d "@$((now_ms / 1000))" +%Y-%m-%dT%H:%M:%SZ)","message":{"role":"assistant","provider":"xai","model":"grok-4.5","usage":{"input":300,"output":100,"cacheRead":400,"cacheWrite":0,"totalTokens":800}}}
EOF

result=$(HOME="$TEST_HOME" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --local-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "2000" ]] ||
  fail "Grok takes the peak cumulative tokens per turn" "$result"
[[ $(jq -c '.totalPrompts' <<<"$result") == "3" ]] ||
  fail "Grok counts session turns plus pi" "$result"
[[ $(jq -c '.todayPrompts' <<<"$result") == "2" ]] ||
  fail "Grok counts today's turns" "$result"
[[ $(jq -r '.modelUsage["grok-4.5"].inputTokens' <<<"$result") == "1500" ]] ||
  fail "Grok reports the turn total as input tokens" "$result"
[[ $(jq -r '.modelUsage["grok-4.5"].outputTokens' <<<"$result") == "100" ]] ||
  fail "Grok adds pi output onto the native turn" "$result"
[[ $(jq -r '.modelUsage["grok-4.5"].cacheReadInputTokens' <<<"$result") == "400" ]] ||
  fail "Grok keeps the pi cache split separate" "$result"
[[ $(jq -r '.modelUsage["grok-3"].inputTokens' <<<"$result") == "500" ]] ||
  fail "Grok maps turns to their model" "$result"
[[ $(jq -c '.id' <<<"$result") == '"grok"' ]] ||
  fail "Grok record identifies itself" "$result"
pass "Grok local scan aggregates native+pi per model"

# ---------------------------------------------------------------- billing
# The CLI's auth.json shape: a grok-com entry with a non-expired token so the
# collector goes straight to the billing endpoint instead of refreshing.
mkdir -p "$TEST_HOME/.grok"
cat >"$TEST_HOME/.grok/auth.json" <<'EOF'
{
  "https://auth.x.ai::grok-com": {
    "key": "test-access-token",
    "refresh_token": "test-refresh-token",
    "user_id": "user-1",
    "expires_at": "2030-01-01T00:00:00Z",
    "oidc_issuer": "https://auth.x.ai",
    "oidc_client_id": "grok-com"
  }
}
EOF

# Recorded billing?format=credits payload: a single-product weekly pool.
mkdir -p "$TEST_HOME/www"
cat >"$TEST_HOME/www/billing" <<'EOF'
{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-21T02:33:55.961189+00:00","end":"2026-07-28T02:33:55.961189+00:00"},"creditUsagePercent":10.0,"onDemandCap":{"val":0},"onDemandUsed":{"val":0},"productUsage":[{"product":"GrokChat","usagePercent":10.0}],"isUnifiedBillingUser":true}}
EOF

PORT=$(python3 - <<'PYEOF'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PYEOF
)

python3 -m http.server "$PORT" --directory "$TEST_HOME/www" >/dev/null 2>&1 &
SERVER_PID=$!
trap 'rm -rf "$TEST_HOME"; [[ -n ${SERVER_PID:-} ]] && kill "$SERVER_PID" 2>/dev/null' EXIT
for _ in $(seq 1 50); do
  (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null && { exec 3>&-; break; }
  sleep 0.1
done

billing=$(HOME="$TEST_HOME" GROK_HOME="$TEST_HOME/.grok" \
  _CLI_CHAT_PROXY_BASE_URL="http://127.0.0.1:$PORT" \
  "$ROOT/bin/omarchy-agent-usage-grok")

[[ $(jq -c '[.limits[].label]' <<<"$billing") == '["Weekly credits"]' ]] ||
  fail "Grok reports a single-product pool once" "$billing"
[[ $(jq -c '.limits[0].percent' <<<"$billing") == "0.1" ]] ||
  fail "Grok reports the credit fraction" "$billing"
[[ $(jq -r '.limits[0].resetsAt' <<<"$billing") == "2026-07-28T02:33:55Z" ]] ||
  fail "Grok reports the pool reset time" "$billing"
pass "Grok probe reports official billing limits"