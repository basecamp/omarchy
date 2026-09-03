#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

no_key=$(HOME="$TEST_HOME" GROK_HOME="$TEST_HOME/.grok" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + .usageStatusText' <<<"$no_key") == "grok:false:Waiting for auth" ]] ||
  fail "Grok collector prints a valid record without sessions or credentials" "$no_key"
pass "Grok collector prints a valid record without sessions or credentials"

timestamp="$(date +%Y-%m-%d)T12:00:00Z"
unix=$(date +%s)
session="$TEST_HOME/.grok/sessions/example/session-1"
mkdir -p "$session"
cat >"$session/updates.jsonl" <<EOF
{"timestamp":$unix,"params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"prompt-1","usage":{"inputTokens":100,"outputTokens":20,"reasoningTokens":5,"cachedReadTokens":40,"cacheCreationTokens":10,"totalTokens":120,"modelUsage":{"grok-4.6-build":{"inputTokens":100}}}}}}
{"timestamp":$unix,"params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"prompt-1","usage":{"inputTokens":100,"outputTokens":20,"reasoningTokens":5,"cachedReadTokens":40,"cacheCreationTokens":10,"totalTokens":120,"modelUsage":{"grok-4.6-build":{"inputTokens":100}}}}}}
{"timestamp":$unix,"params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"prompt-2","session_kind":"subagent","usage":{"inputTokens":999,"outputTokens":999,"totalTokens":1998,"modelUsage":{"grok-4.6-build":{}}}}}}
{"timestamp":$unix,"params":{"session_relationship":"subagent_fork","update":{"sessionUpdate":"turn_completed","prompt_id":"prompt-3","usage":{"inputTokens":888,"outputTokens":1,"totalTokens":889}}}}
{"timestamp":$unix,"params":{"update":{"sessionUpdate":"tool_call","usage":{"inputTokens":1}}}}
EOF

result=$(HOME="$TEST_HOME" GROK_HOME="$TEST_HOME/.grok" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "175" ]] ||
  fail "Grok collector counts each completed turn once and skips subagents" "$result"
pass "Grok collector counts each completed turn once and skips subagents"

[[ $(jq -c '.modelUsage["grok-4.6"]' <<<"$result") == '{"cacheCreationInputTokens":10,"cacheReadInputTokens":40,"inputTokens":100,"outputTokens":25}' ]] ||
  fail "Grok collector keeps exclusive token buckets and strips the -build suffix" "$result"
pass "Grok collector keeps exclusive token buckets and strips the -build suffix"

[[ $(jq -r '.todayPrompts' <<<"$result") == "1" ]] ||
  fail "Grok collector treats duplicate prompt_id as one prompt" "$result"
pass "Grok collector treats duplicate prompt_id as one prompt"

billing=$(python3 - "$ROOT/bin/omarchy-agent-usage-grok" <<'PY'
import importlib.util
import json
import sys
from importlib.machinery import SourceFileLoader

spec = importlib.util.spec_from_loader("grok_collector", SourceFileLoader("grok_collector", sys.argv[1]))
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)

limits, _ = collector.limits_from_billing({
  "config": {
    "creditUsagePercent": 5.0,
    "currentPeriod": {
      "type": "USAGE_PERIOD_TYPE_WEEKLY",
      "end": "2026-09-09T13:21:22.402072+00:00",
    },
    "productUsage": [
      {"product": "GrokBuild", "usagePercent": 4.0},
      {"product": "GrokChat", "usagePercent": 1.0},
    ],
  }
})
print(json.dumps({
  "tier": collector.friendly_tier("SuperGrokPlus"),
  "weekly": limits[0],
  "build": limits[1],
  "count": len(limits),
}))
PY
)

[[ $(jq -r '.tier' <<<"$billing") == "SuperGrok Plus" ]] ||
  fail "Grok collector formats SuperGrokPlus as SuperGrok Plus" "$billing"
pass "Grok collector formats SuperGrokPlus as SuperGrok Plus"

[[ $(jq -r '.count' <<<"$billing") == "2" ]] ||
  fail "Grok collector reports weekly pool and Grok Build, not every product" "$billing"
pass "Grok collector reports weekly pool and Grok Build, not every product"

[[ $(jq -r '.weekly.percent' <<<"$billing") == "0.05" ]] ||
  fail "Grok collector scales creditUsagePercent 5 into a 0-1 meter" "$billing"
pass "Grok collector scales creditUsagePercent 5 into a 0-1 meter"

[[ $(jq -r '.build.title + ":" + (.build.percent|tostring)' <<<"$billing") == "Grok Build:0.04" ]] ||
  fail "Grok collector includes the Grok Build weekly slice" "$billing"
pass "Grok collector includes the Grok Build weekly slice"
