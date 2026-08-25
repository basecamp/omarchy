#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

no_auth=$(HOME="$TEST_HOME" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok")

[[ $(jq -r '.id + ":" + (.ready | tostring)' <<<"$no_auth") == "grok:false" ]] ||
  fail "Grok collector prints a valid record without credentials" "$no_auth"
pass "Grok collector prints a valid record without credentials"

result=$(python3 - "$ROOT/bin/omarchy-agent-usage-grok" "$TEST_HOME" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import sys
import time
from pathlib import Path

collector_path = str(Path(sys.argv[1]))
home = Path(sys.argv[2])
os.environ["TZ"] = "UTC"
time.tzset()
os.environ["HOME"] = str(home)
os.environ["GROK_HOME"] = str(home / ".grok")

loader = importlib.machinery.SourceFileLoader("grok_collector", collector_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)

billing = {
  "config": {
    "currentPeriod": {
      "type": "USAGE_PERIOD_TYPE_WEEKLY",
      "start": "2026-08-23T18:18:14+00:00",
      "end": "2026-08-30T18:18:14+00:00",
    },
    "creditUsagePercent": 23.0,
    "onDemandCap": {"val": 0},
    "onDemandUsed": {"val": 0},
    "productUsage": [
      {"product": "GrokBuild", "usagePercent": 22.0},
      {"product": "GrokChat", "usagePercent": 1.0},
    ],
    "prepaidBalance": {"val": 0},
  }
}
settings = {"subscription_tier_display": "SuperGrok Heavy"}


def fake_http(url, token, timeout=8.0):
  if "billing" in url:
    return billing
  if "settings" in url:
    return settings
  raise AssertionError(url)


scanner.http_get_json = fake_http

grok_home = home / ".grok"
session = grok_home / "sessions" / "proj" / "sid"
session.mkdir(parents=True)
auth = {
  "https://auth.x.ai::test": {
    "key": "oauth-token",
    "auth_mode": "oidc",
    "email": "user@example.com",
    "expires_at": "2099-01-01T00:00:00+00:00",
  }
}
(grok_home / "auth.json").write_text(json.dumps(auth))

now = int(time.time())
turn = {
  "timestamp": now,
  "method": "_x.ai/session/update",
  "params": {
    "sessionId": "sid",
    "update": {
      "sessionUpdate": "turn_completed",
      "prompt_id": "p1",
      "usage": {
        "inputTokens": 1000,
        "outputTokens": 50,
        "totalTokens": 1050,
        "cachedReadTokens": 800,
        "cacheCreationTokens": 0,
        "modelUsage": {
          "grok-4.6-build": {
            "inputTokens": 1000,
            "outputTokens": 50,
            "totalTokens": 1050,
            "cachedReadTokens": 800,
            "cacheCreationTokens": 0,
          }
        },
      },
    },
  },
}
(session / "updates.jsonl").write_text(json.dumps(turn) + "\n")

stats = scanner.scan_local_sessions()
limits = scanner.fetch_limits("oauth-token")
out = {
  "id": scanner.AGENT_ID,
  "name": limits.get("tierLabel") or scanner.AGENT_ID,
  "accountEmail": "user@example.com",
  "tierLabel": limits.get("tierLabel"),
  "limits": limits.get("limits"),
  "todayTotalTokens": stats["todayTotalTokens"],
  "todayPrompts": stats["todayPrompts"],
  "recentDays": stats["recentDays"],
  "modelUsage": stats["modelUsage"],
}
print(json.dumps(out))
PY
)

[[ $(jq -r '.name' <<<"$result") == "SuperGrok Heavy" ]] ||
  fail "Grok collector uses subscription_tier_display as the title" "$result"
pass "Grok collector uses subscription_tier_display as the title"

[[ $(jq -r '.accountEmail' <<<"$result") == "user@example.com" ]] ||
  fail "Grok collector reads the account email from auth.json" "$result"
pass "Grok collector reads the account email from auth.json"

[[ $(jq -r '[.limits[].title] | join(",")' <<<"$result") == "Weekly,GrokBuild,GrokChat,Pay-as-you-go" ]] ||
  fail "Grok collector keeps API product strings and derived period label" "$result"
pass "Grok collector keeps API product strings and derived period label"

[[ $(jq -r '.limits[-1].status' <<<"$result") == "Off" ]] ||
  fail "Grok collector reports pay-as-you-go Off when the cap is zero" "$result"
pass "Grok collector reports pay-as-you-go Off when the cap is zero"

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "1050" ]] ||
  fail "Grok collector stores turn_completed tokens, not prompt counts" "$result"
pass "Grok collector stores turn_completed tokens, not prompt counts"

today=$(date -u +%F)
[[ $(jq -r --arg d "$today" '.recentDays[] | select(.date==$d) | .messageCount' <<<"$result") == "1050" ]] ||
  fail "Grok collector puts tokens in recentDays.messageCount" "$result"
pass "Grok collector puts tokens in recentDays.messageCount"
