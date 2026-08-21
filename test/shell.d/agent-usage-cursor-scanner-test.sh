#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.config/cursor"
cat >"$TEST_HOME/.config/cursor/auth.json" <<'EOF'
{"accessToken":"test-token"}
EOF

mkdir -p "$TEST_HOME/projects/demo/agent-transcripts/session-1"
cat >"$TEST_HOME/projects/demo/agent-transcripts/session-1/session-1.jsonl" <<'EOF'
{"role":"user","message":{"content":[{"type":"text","text":"<timestamp>Friday, Aug 21, 2026, 2:00 PM (UTC)</timestamp>\nhello"}]}}
{"role":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}
EOF

COLLECTOR="$ROOT/bin/omarchy-agent-usage-cursor"

signed_in=$(HOME="$TEST_HOME" CURSOR_CONFIG_DIR="$TEST_HOME/.config/cursor" CURSOR_PROJECTS_DIR="$TEST_HOME/projects" \
  COLLECTOR="$COLLECTOR" python3 - <<'PY'
import importlib.machinery
import importlib.util
import io
import json
import os
import urllib.error

loader = importlib.machinery.SourceFileLoader("cursor_collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

def urlopen(request, timeout=None):
  path = request.full_url.rsplit("/", 1)[-1]
  if path == "GetCurrentPeriodUsage":
    return io.BytesIO(json.dumps({
      "billingCycleEnd": "1789577156000",
      "displayMessage": "You have used 41% of your included usage",
      "planUsage": {
        "totalPercentUsed": 41.0,
        "autoPercentUsed": 8.0,
        "apiPercentUsed": 0,
        "limit": 40000,
        "remaining": 23600,
        "totalSpend": 16400
      }
    }).encode())
  if path == "GetPlanInfo":
    return io.BytesIO(json.dumps({"planInfo": {"planName": "Ultra", "price": "$200/mo"}}).encode())
  raise AssertionError(request.full_url)

collector.urllib.request.urlopen = urlopen
print(json.dumps(collector.collect_limits("token")))
PY
)

[[ $(jq -r '.tierLabel' <<<"$signed_in") == "Ultra (\$200/mo)" ]] ||
  fail "Cursor collector reads plan tier from dashboard API" "$signed_in"
[[ $(jq -r '.usageStatusText + "|" + .authHelpText' <<<"$signed_in") == "|" ]] ||
  fail "Cursor collector leaves status fields empty when signed in" "$signed_in"
[[ $(jq -c '.limits[0]' <<<"$signed_in") == '{"label":"Billing cycle","percent":0.41,"resetsAt":"2026-09-16T16:45:56+00:00"}' ]] ||
  fail "Cursor collector maps billing cycle usage to limits" "$signed_in"
[[ $(jq -c '.balance' <<<"$signed_in") == '{"remaining":236.0,"funded":400.0,"spent":164.0,"currency":"USD","estimated":false}' ]] ||
  fail "Cursor collector maps included spend to balance" "$signed_in"
pass "Cursor collector maps signed-in dashboard usage"

expired=$(HOME="$TEST_HOME" COLLECTOR="$COLLECTOR" python3 - <<'PY'
import importlib.machinery
import importlib.util
import io
import json
import os
import urllib.error

loader = importlib.machinery.SourceFileLoader("cursor_collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

def urlopen(request, timeout=None):
  raise urllib.error.HTTPError(request.full_url, 401, "Unauthorized", hdrs=None, fp=io.BytesIO(b""))

collector.urllib.request.urlopen = urlopen
print(json.dumps(collector.collect_limits("token")))
PY
)

[[ $(jq -r '.usageStatusText' <<<"$expired") == "Sign-in expired" ]] ||
  fail "Cursor collector reports expired auth" "$expired"
pass "Cursor collector reports expired auth"

record=$(HOME="$TEST_HOME" CURSOR_CONFIG_DIR="$TEST_HOME/.config/cursor" CURSOR_PROJECTS_DIR="$TEST_HOME/projects" \
  XDG_CACHE_HOME="$TEST_HOME/.cache" COLLECTOR="$COLLECTOR" python3 - <<'PY'
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import urllib.error

loader = importlib.machinery.SourceFileLoader("cursor_collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

def urlopen(request, timeout=None):
  path = request.full_url.rsplit("/", 1)[-1]
  if path == "GetCurrentPeriodUsage":
    return io.BytesIO(json.dumps({
      "billingCycleEnd": "1789577156000",
      "planUsage": {"totalPercentUsed": 10, "autoPercentUsed": 0, "apiPercentUsed": 0, "limit": 0}
    }).encode())
  if path == "GetPlanInfo":
    return io.BytesIO(json.dumps({"planInfo": {"planName": "Pro", "price": "$20/mo"}}).encode())
  if path == "GetAggregatedUsageEvents":
    return io.BytesIO(json.dumps({
      "aggregations": [{
        "modelIntent": "composer-2.5",
        "inputTokens": "100",
        "outputTokens": "20",
        "cacheReadTokens": "5"
      }]
    }).encode())
  raise AssertionError(request.full_url)

collector.urllib.request.urlopen = urlopen
sys.argv = ["omarchy-agent-usage-cursor", "--force"]
raise SystemExit(collector.main())
PY
)

[[ $(jq -r '.totalPrompts' <<<"$record") == "1" ]] ||
  fail "Cursor collector counts agent CLI user prompts" "$record"
[[ $(jq -r '.modelUsage["composer-2.5"].inputTokens' <<<"$record") == "100" ]] ||
  fail "Cursor collector reads per-model usage from dashboard API" "$record"
pass "Cursor collector merges local transcripts with dashboard model usage"

no_auth_home=$(mktemp -d)
no_auth=$(HOME="$no_auth_home" XDG_CACHE_HOME="$no_auth_home/.cache" "$COLLECTOR" --force)
rm -rf "$no_auth_home"

[[ $(jq -r '.usageStatusText' <<<"$no_auth") == "Not signed in" ]] ||
  fail "Cursor collector reports missing auth" "$no_auth"
pass "Cursor collector reports missing auth"
