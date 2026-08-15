#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.config/cursor" "$TEST_HOME/.cache"

# Without credentials the collector must still print a full record so the
# updater can write it and the panel can hide an empty tab.
no_key=$(HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  CURSOR_API_KEY="" "$ROOT/bin/omarchy-agent-usage-cursor")

[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + .usageStatusText' <<<"$no_key") == "cursor:false:Waiting for auth" ]] ||
  fail "Cursor collector prints a valid record without credentials" "$no_key"
pass "Cursor collector prints a valid record without credentials"

result=$(python3 - "$ROOT/bin/omarchy-agent-usage-cursor" "$TEST_HOME" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import sys
import time
from datetime import date, datetime, timezone
from pathlib import Path

collector_path = Path(sys.argv[1])
test_home = Path(sys.argv[2])
os.environ["HOME"] = str(test_home)
os.environ["XDG_CONFIG_HOME"] = str(test_home / ".config")
os.environ["XDG_CACHE_HOME"] = str(test_home / ".cache")
os.environ["TZ"] = "UTC"
time.tzset()
os.environ.pop("CURSOR_API_KEY", None)

auth = test_home / ".config" / "cursor" / "auth.json"
auth.parent.mkdir(parents=True, exist_ok=True)
auth.write_text(json.dumps({"accessToken": "test-token", "refreshToken": "refresh"}))

loader = importlib.machinery.SourceFileLoader("cursor_collector", str(collector_path))
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)

period = {
  "billingCycleStart": "1784201744000",
  "billingCycleEnd": "1786880144000",
  "planUsage": {
    "totalSpend": 10912,
    "includedSpend": 2000,
    "bonusSpend": 8912,
    "limit": 2000,
    "autoPercentUsed": 36.37,
    "apiPercentUsed": 0,
    "totalPercentUsed": 31.63,
  },
}
plan = {"planInfo": {"planName": "Pro", "includedAmountCents": 2000, "price": "$20/mo"}}
# Two events on 2026-08-15 UTC, one earlier in the week.
events = [
  {
    "timestamp": "1786797690055",
    "model": "cursor-grok-4.5-high-fast",
    "conversationId": "chat-a",
    "tokenUsage": {"inputTokens": 100, "outputTokens": 50, "cacheReadTokens": 20},
  },
  {
    "timestamp": "1786797691055",
    "model": "cursor-grok-4.5-high-fast",
    "conversationId": "chat-a",
    "tokenUsage": {"inputTokens": 10, "outputTokens": 5, "cacheReadTokens": 0},
  },
  {
    "timestamp": "1786360000000",
    "model": "default",
    "conversationId": "chat-b",
    "tokenUsage": {"inputTokens": 40, "outputTokens": 10, "cacheReadTokens": 0},
  },
]
aggregated = {
  "aggregations": [
    {
      "modelIntent": "cursor-grok-4.5-high-fast",
      "inputTokens": "5890021",
      "outputTokens": "533298",
      "cacheReadTokens": "84395776",
    },
    {"modelIntent": "default", "inputTokens": "255508", "outputTokens": "10844", "cacheReadTokens": "727552"},
  ]
}

calls = []

class FakeClient:
  def __init__(self, token, api_base_url=scanner.API_BASE_URL):
    self.token = token
    self.api_base_url = api_base_url

  def request(self, method, payload=None):
    calls.append(method)
    if method == "GetCurrentPeriodUsage":
      return period
    if method == "GetPlanInfo":
      return plan
    if method == "GetFilteredUsageEvents":
      return {"usageEventsDisplay": events, "totalUsageEventsCount": len(events)}
    if method == "GetAggregatedUsageEvents":
      return aggregated
    raise scanner.CursorError(f"unexpected {method}")

scanner.CursorClient = FakeClient

# Pin "today" for summarize_events by monkeypatching date resolution through
# local_day_from_ms timestamps already chosen above (2026-08-15 / 2026-08-10).
stats = scanner.summarize_events(events, today=date(2026, 8, 15))
limits = scanner.plan_limits(period)
assert abs(limits[0]["percent"] - 0.3163) < 1e-6, limits
assert limits[0]["label"] == "Included", limits
assert abs(limits[1]["percent"] - 0.3637) < 1e-6, limits
assert limits[2]["percent"] == 0.0, limits

# Without totalPercentUsed, fall back to includedSpend/limit like Cursor's UI.
fallback = scanner.plan_limits({
  "billingCycleEnd": "1786880144000",
  "planUsage": {"includedSpend": 500, "limit": 2000},
})
assert abs(fallback[0]["percent"] - 0.25) < 1e-6, fallback

record = scanner.scan("test-token", scanner.API_BASE_URL, force=True, limits_only=False)
record["_calls"] = calls
record["_token"] = scanner.read_access_token(auth)
record["_stats"] = stats
print(json.dumps(record))
PY
)

[[ $(jq -r '.id + "/" + .name + "/" + .tierLabel + "/" + (.ready|tostring) + "/" + (.scope // "")' <<<"$result") == "cursor/Cursor/Pro/true/account" ]] ||
  fail "Cursor collector prints the display-ready record contract" "$result"
pass "Cursor collector prints the display-ready record contract"

[[ $(jq -r '._token' <<<"$result") == "test-token" ]] ||
  fail "Cursor collector reads the access token from auth.json" "$result"
pass "Cursor collector reads the access token from auth.json"

[[ $(jq -r '
  ([.limits[].percent] | map(. * 10000 | round / 10000)) as $p
  | if $p == [0.3163, 0.3637, 0.0] then "ok" else ($p|tostring) end
' <<<"$result") == "ok" ]] ||
  fail "Cursor collector maps included/auto/API percentages onto 0-1 meters" "$result"
pass "Cursor collector maps included/auto/API percentages onto 0-1 meters"

[[ $(jq -r '.limits[0].label + "/" + .limits[0].resetsAt' <<<"$result") == "Included/2026-08-16T11:35:44+00:00" ]] ||
  fail "Cursor collector labels the included meter and converts its reset time" "$result"
pass "Cursor collector labels the included meter and converts its reset time"



[[ $(jq -r '.todayPrompts|tostring' <<<"$result") == "2" ]] ||
  fail "Cursor collector counts today's prompts from usage events" "$result"
[[ $(jq -r '.todaySessions|tostring' <<<"$result") == "1" ]] ||
  fail "Cursor collector counts today's sessions from conversation ids" "$result"
pass "Cursor collector counts today's prompts and sessions from usage events"

[[ $(jq -r '.modelUsage["cursor-grok-4.5-high-fast"].inputTokens|tostring' <<<"$result") == "5890021" ]] ||
  fail "Cursor collector prefers billing-period model aggregations when they are wider" "$result"
pass "Cursor collector prefers billing-period model aggregations when they are wider"

[[ $(jq -c '[._calls[]]' <<<"$result") == '["GetCurrentPeriodUsage","GetPlanInfo","GetFilteredUsageEvents","GetAggregatedUsageEvents"]' ]] ||
  fail "Cursor collector probes plan, events, and aggregations" "$result"
pass "Cursor collector probes plan, events, and aggregations"

expired=$(python3 - "$ROOT/bin/omarchy-agent-usage-cursor" "$TEST_HOME" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import sys
from pathlib import Path

collector_path = Path(sys.argv[1])
test_home = Path(sys.argv[2])
os.environ["HOME"] = str(test_home)
os.environ["XDG_CONFIG_HOME"] = str(test_home / ".config")
os.environ["XDG_CACHE_HOME"] = str(test_home / ".cache")
os.environ.pop("CURSOR_API_KEY", None)

loader = importlib.machinery.SourceFileLoader("cursor_collector", str(collector_path))
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)

class ExpiredClient:
  def __init__(self, token, api_base_url=scanner.API_BASE_URL):
    pass
  def request(self, method, payload=None):
    raise scanner.CursorError("Sign-in expired")

scanner.CursorClient = ExpiredClient
print(json.dumps(scanner.scan("stale", scanner.API_BASE_URL, force=True, limits_only=False)))
PY
)

[[ $(jq -r '.ready|tostring' <<<"$expired") == "false" && $(jq -r '.usageStatusText' <<<"$expired") == "Sign-in expired" ]] ||
  fail "Cursor collector reports an expired sign-in without fabricating usage" "$expired"
pass "Cursor collector reports an expired sign-in without fabricating usage"
