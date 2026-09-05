#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.pi/agent/sessions/project"

today="$(date +%Y-%m-%d)"
timestamp="${today}T12:00:00Z"

# One session file exercises the whole scan contract:
#   a  zai, today, with reasoning + cache tokens        -> counted, today
#   b  zhipu, today                                     -> counted, today
#   c  openai provider                                  -> ignored
#   d  zai but a user turn                              -> ignored
#   a' a repeated message id                            -> deduped
#   f  zai, no top-level timestamp, message.timestamp   -> counted, NOT today
#   e  malformed JSON                                   -> skipped, rest survive
session="$TEST_HOME/.pi/agent/sessions/project/pi.jsonl"
cat >"$session" <<EOF
{"type":"message","id":"a","timestamp":"$timestamp","message":{"role":"assistant","provider":"zai","model":"glm-5.3","usage":{"input":10,"output":4,"reasoning":6,"cacheRead":3,"cacheWrite":2}}}
{"type":"message","id":"b","timestamp":"$timestamp","message":{"role":"assistant","provider":"zhipu","model":"glm-4.7","usage":{"input":20,"output":5}}}
{"type":"message","id":"c","timestamp":"$timestamp","message":{"role":"assistant","provider":"openai","model":"gpt","usage":{"input":999,"output":999}}}
{"type":"message","id":"d","timestamp":"$timestamp","message":{"role":"user","provider":"zai","model":"glm-5.3","usage":{"input":500,"output":500}}}
{"type":"message","id":"a","timestamp":"$timestamp","message":{"role":"assistant","provider":"zai","model":"glm-5.3","usage":{"input":77,"output":77}}}
{"type":"message","id":"f","message":{"role":"assistant","provider":"zai","model":"glm-4.6","timestamp":"2020-01-01T00:00:00Z","usage":{"input":7}}}
{"type":"message","id":"e","message":{"role":"assistant","provider":"zai","usage":{ broken
EOF

run() {
  env -u ZAI_API_KEY -u ZHIPU_API_KEY -u ZHIPUAI_API_KEY \
    HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" XDG_CACHE_HOME="$TEST_HOME/.cache" \
    "$ROOT/bin/omarchy-agent-usage-zai" "$@"
}

result=$(run)

[[ $(jq -r '.id + "/" + .name + "/" + (.limits|tostring) + "/" + (.ready|tostring)' <<<"$result") == "zai/Z.ai/[]/true" ]] ||
  fail "Z.ai collector identifies itself and is ready on local stats alone (no key)" "$result"
pass "Z.ai collector reports itself, empty limits, ready on local stats"

# Reasoning tokens fold into output; cache tokens split out; the repeated id is
# counted once, so the glm-5.3 bucket is exactly message a.
[[ $(jq -Sc '.modelUsage["glm-5.3"]' <<<"$result") == '{"cacheCreationInputTokens":2,"cacheReadInputTokens":3,"inputTokens":10,"outputTokens":10}' ]] ||
  fail "Z.ai collector adds reasoning to output and dedups repeated message ids" "$result"
pass "Z.ai collector adds reasoning to output and dedups repeated ids"

# a + b land today (25 + 25); f is an old day and must not inflate today.
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "50" && $(jq -r '.todayPrompts' <<<"$result") == "2" ]] ||
  fail "Z.ai collector keeps a message.timestamp-dated turn out of today's totals" "$result"
[[ $(jq -r '.totalPrompts' <<<"$result") == "3" && $(jq -r '.activeDays' <<<"$result") == "2" ]] ||
  fail "Z.ai collector still counts the old-dated turn in all-time totals" "$result"
pass "Z.ai collector dates turns by message.timestamp, not a dead ts fallback"

# openai (wrong provider), the user turn, and the malformed line all drop out.
[[ $(jq -Sc '.modelUsage | keys' <<<"$result") == '["glm-4.6","glm-4.7","glm-5.3"]' ]] ||
  fail "Z.ai collector filters to Z.ai assistant turns and survives a malformed line" "$result"
pass "Z.ai collector filters providers/roles and survives malformed lines"

# The scan is cached so the panel's per-open --limits-only does not re-walk
# every session file; --force bypasses it.
cache_file=$(ls "$TEST_HOME/.cache/omarchy/agent-usage/"zai-scan-*.json 2>/dev/null | head -n 1)
[[ -n $cache_file && $(jq -r '.schemaVersion' "$cache_file") == "1" && $(jq -r '.stats.todayTotalTokens' "$cache_file") == "50" ]] ||
  fail "Z.ai collector writes a versioned local-stats cache on first scan" "$result"
pass "Z.ai collector writes a local-stats cache on first scan"

# A new turn arrives; --limits-only must reuse the cache instead of rescanning.
cat >>"$session" <<EOF
{"type":"message","id":"g","timestamp":"$timestamp","message":{"role":"assistant","provider":"zai","model":"glm-5.3","usage":{"input":100}}}
EOF

result=$(run --limits-only)
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "50" ]] ||
  fail "Z.ai collector --limits-only reuses the cached scan" "$result"
pass "Z.ai collector --limits-only reuses cached local stats"

result=$(run --force)
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "150" ]] ||
  fail "Z.ai collector --force rescans past the cache" "$result"
pass "Z.ai collector --force rescans past the cache"

result=$(run --limits-only)
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "150" ]] ||
  fail "Z.ai collector --limits-only sees the cache refreshed by --force" "$result"
pass "Z.ai collector --limits-only sees a refreshed cache after --force"
