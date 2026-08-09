#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.kimi-code/sessions/wd_test/session_aaaa/agents/kimi" \
         "$TEST_HOME/.pi/agent/sessions/wd_test"
now_ms=$(( $(date +%s) * 1000 ))
old_ms=$(( ($(date +%s) - 3 * 86400) * 1000 ))

cat >"$TEST_HOME/.kimi-code/sessions/wd_test/session_aaaa/agents/kimi/wire.jsonl" <<EOF
{"type":"usage.record","model":"kimi-code/k3","usage":{"inputOther":1000,"output":200,"inputCacheRead":300,"inputCacheCreation":0},"time":$now_ms}
{"type":"usage.record","model":"opencode-go/kimi-k3","usage":{"inputOther":500,"output":100,"inputCacheRead":100,"inputCacheCreation":50},"time":$now_ms}
{"type":"usage.record","model":"kimi-code/k2","usage":{"inputOther":50,"output":10,"inputCacheRead":0,"inputCacheCreation":0},"time":$old_ms}
EOF

cat >"$TEST_HOME/.pi/agent/sessions/wd_test/session-pi.jsonl" <<EOF
{"type":"message","id":"pi-1","timestamp":"$(date -u -d "@$((now_ms / 1000))" +%Y-%m-%dT%H:%M:%SZ)","message":{"role":"assistant","provider":"kimi-coding","model":"k3","usage":{"input":400,"output":100,"cacheRead":50,"cacheWrite":0,"totalTokens":550}}}
EOF

result=$(HOME="$TEST_HOME" KIMI_CODE_HOME="$TEST_HOME/.kimi-code" \
  "$ROOT/bin/omarchy-agent-usage-kimi" --local-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "2800" ]] ||
  fail "Kimi sums native and pi usage without double-counting" "$result"
[[ $(jq -r '.modelUsage.k3.inputTokens' <<<"$result") == "1900" ]] ||
  fail "Kimi buckets k3 input tokens once from native+pi" "$result"
[[ $(jq -r '.modelUsage.k3.outputTokens' <<<"$result") == "400" ]] ||
  fail "Kimi buckets k3 output tokens once from native+pi" "$result"
[[ $(jq -r '.modelUsage.k3.cacheReadInputTokens' <<<"$result") == "450" ]] ||
  fail "Kimi buckets k3 cache reads once from native+pi" "$result"
[[ $(jq -r '.modelUsage.k3.cacheCreationInputTokens' <<<"$result") == "50" ]] ||
  fail "Kimi buckets k3 cache writes once from native+pi" "$result"
[[ $(jq -c '.modelUsage.k2.inputTokens' <<<"$result") == "50" ]] ||
  fail "Kimi keeps the older k2 model in its own bucket" "$result"
[[ $(jq -c '.id' <<<"$result") == '"kimi"' ]] ||
  fail "Kimi record identifies itself" "$result"
pass "Kimi local scan merges native+pi into one model"

# ---------------------------------------------------------------- limits
# The CLI's FileTokenStorage shape: a non-expired token so the collector
# goes straight to the /usages endpoint instead of the OAuth refresh flow.
expires_at=$(( $(date +%s) + 86400 ))
mkdir -p "$TEST_HOME/.kimi-code/credentials"
cat >"$TEST_HOME/.kimi-code/credentials/kimi-code.json" <<EOF
{
  "access_token": "test-access-token",
  "refresh_token": "test-refresh-token",
  "expires_at": $expires_at
}
EOF

# Recorded /usages payload: weekly summary plus a 300-minute rolling window.
mkdir -p "$TEST_HOME/www"
cat >"$TEST_HOME/www/usages" <<'EOF'
{"user":{"membership":{"level":"LEVEL_INTERMEDIATE"}},"usage":{"limit":"100","used":"50","resetTime":"2026-07-25T15:18:36.503407Z"},"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"100","remaining":"100","resetTime":"2026-07-24T21:18:36.503407Z"}}]}
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

quota=$(HOME="$TEST_HOME" KIMI_CODE_HOME="$TEST_HOME/.kimi-code" \
  KIMI_CODE_BASE_URL="http://127.0.0.1:$PORT" \
  "$ROOT/bin/omarchy-agent-usage-kimi")

[[ $(jq -c '[.limits[].label]' <<<"$quota") == '["Weekly limit","5h limit"]' ]] ||
  fail "Kimi normalizes weekly + rolling window limits" "$quota"
[[ $(jq -c '.limits[0].percent' <<<"$quota") == "0.5" ]] ||
  fail "Kimi reports the weekly fraction" "$quota"
[[ $(jq -r '.tierLabel' <<<"$quota") == "Intermediate" ]] ||
  fail "Kimi reports the membership plan" "$quota"
[[ $(jq -r '.ready' <<<"$quota") == "true" ]] ||
  fail "Kimi marks the record ready with limits" "$quota"
pass "Kimi probe reports official quota limits"