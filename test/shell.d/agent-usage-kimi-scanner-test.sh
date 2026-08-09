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
{"type":"message","id":"pi-1","timestamp":"2026-08-09T12:00:00Z","message":{"role":"assistant","provider":"kimi-coding","model":"k3","usage":{"input":400,"output":100,"cacheRead":50,"cacheWrite":0,"totalTokens":550}}}
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