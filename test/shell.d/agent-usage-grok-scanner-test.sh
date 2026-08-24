#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

session_dir="$TEST_HOME/.grok/sessions/%2Fhome%2Fers%2Fproj/01a0"
mkdir -p "$session_dir" "$TEST_HOME/.cache"

cat >"$TEST_HOME/.grok/auth.json" <<'EOF'
{
  "https://auth.x.ai::abc": {
    "auth_mode": "oidc",
    "key": "test-bearer-token",
    "expires_at": "2999-01-01T00:00:00Z"
  }
}
EOF

# One turn today, one turn yesterday, per-model split, both in the same
# session so totalSessions == 1 while activeDays == 2.
today_ts=$(date -d "today 12:00" +%s)
yesterday_ts=$(date -d "yesterday 12:00" +%s)
cat >"$session_dir/updates.jsonl" <<EOF
{"timestamp":$yesterday_ts,"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"turn_completed","prompt_id":"a","stop_reason":"end_turn","usage":{"inputTokens":100,"outputTokens":50,"cachedReadTokens":40,"cacheCreationTokens":0,"totalTokens":150,"modelUsage":{"grok-4.6":{"inputTokens":100,"outputTokens":50,"cachedReadTokens":40,"cacheCreationTokens":0}}}}}}
{"timestamp":$today_ts,"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"turn_completed","prompt_id":"b","stop_reason":"end_turn","usage":{"inputTokens":200,"outputTokens":75,"cachedReadTokens":100,"cacheCreationTokens":0,"totalTokens":275,"modelUsage":{"grok-4.6":{"inputTokens":200,"outputTokens":75,"cachedReadTokens":100,"cacheCreationTokens":0}}}}}}
{"timestamp":$today_ts,"method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"turn_started"}}}
EOF

result=$(python3 - "$ROOT/bin/omarchy-agent-usage-grok" "$TEST_HOME" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import sys
import urllib.error
from pathlib import Path
from unittest import mock

collector_path = str(Path(sys.argv[1]))
test_home = Path(sys.argv[2])
os.environ["HOME"] = str(test_home)
os.environ["GROK_HOME"] = str(test_home / ".grok")
os.environ["XDG_CACHE_HOME"] = str(test_home / ".cache")
os.environ.pop("XAI_API_KEY", None)

loader = importlib.machinery.SourceFileLoader("grok_collector", collector_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)

summary = {}

# The scanner used by the panel is called with a mock billing client so the
# test never touches the network. A working client returns the credits config.
class WorkingClient:
  def __init__(self, token, base_url):
    summary.setdefault("clientToken", token)

  def credits(self):
    return {
      "currentPeriod": {
        "type": "USAGE_PERIOD_TYPE_WEEKLY",
        "end": "2026-08-25T06:15:57+00:00",
      },
      "creditUsagePercent": 42.5,
      "onDemandCap": {"val": 100},
      "onDemandUsed": {"val": 25},
      "billingPeriodEnd": "2026-08-25T06:15:57+00:00",
    }

class ExpiredClient(WorkingClient):
  def credits(self):
    raise scanner.GrokAuthError("Grok session expired")

class ForbiddenClient(WorkingClient):
  def credits(self):
    raise scanner.GrokAuthError("Grok billing scope denied")

class NetworkFailureClient(WorkingClient):
  def credits(self):
    raise scanner.GrokAuthError("Could not reach the Grok billing API")

record = scanner.scan(0, client_cls=WorkingClient)
summary["record"] = {
  "schemaVersion": record["schemaVersion"],
  "id": record["id"],
  "ready": record["ready"],
  "hasLocalStats": record["hasLocalStats"],
  "tierLabel": record["tierLabel"],
  "usageStatusText": record["usageStatusText"],
  "authHelpText": record["authHelpText"],
  "limits": record["limits"],
  "todayPrompts": record["todayPrompts"],
  "todaySessions": record["todaySessions"],
  "activeDays": record["activeDays"],
  "totalSessions": record["totalSessions"],
  "todayTokensByModel": record["todayTokensByModel"],
  "modelUsage": record["modelUsage"],
}

# --limits-only skips session scanning; totals go to zero even with sessions on disk.
limits_only = scanner.scan(0, limits_only=True, client_cls=WorkingClient)
summary["limitsOnlySkipsScan"] = (
  limits_only["todayTotalTokens"] == 0
  and limits_only["totalPrompts"] == 0
  and limits_only["limits"] == record["limits"]
)

# 401 from billing shows the session-expired message and reasserts the auth
# help without blowing away the local stats the user already earned.
expired = scanner.scan(0, client_cls=ExpiredClient)
summary["expired"] = {
  "usageStatusText": expired["usageStatusText"],
  "authHelpText": expired["authHelpText"],
  "limits": expired["limits"],
  "hasLocalStats": expired["hasLocalStats"],
}

forbidden = scanner.scan(0, client_cls=ForbiddenClient)
summary["forbidden"] = forbidden["usageStatusText"]

network = scanner.scan(0, client_cls=NetworkFailureClient)
summary["networkFailure"] = network["usageStatusText"]

# XAI_API_KEY overrides the disk token even when the CLI is logged in, so an
# operator can point the collector at a separate account without touching
# their signed-in session.
os.environ["XAI_API_KEY"] = "env-key"
token, tier, status, _ = scanner.credentials(test_home / ".grok" / "auth.json")
summary["envKeyWins"] = token == "env-key" and tier == "xAI API" and status == ""
os.environ.pop("XAI_API_KEY", None)

# An expired disk token drops ready to False but leaves the token available
# so a retry with fresh credentials does not have to re-parse the file.
expired_auth = test_home / ".grok" / "auth.json"
expired_auth.write_text(json.dumps({
  "https://auth.x.ai::abc": {
    "auth_mode": "oidc",
    "key": "stale",
    "expires_at": "2000-01-01T00:00:00Z",
  }
}))
token, tier, status, help_text = scanner.credentials(expired_auth)
summary["expiredAuth"] = {
  "token": token,
  "tier": tier,
  "status": status,
  "help": help_text,
}

# The signed-out case is a valid record with a hint, never a crash.
missing_auth = test_home / "missing.json"
token, tier, status, help_text = scanner.credentials(missing_auth)
summary["missingAuth"] = {"token": token, "status": status, "help": help_text}

# limits_from_billing rounds the percent, honors on-demand only when a cap
# exists, and reads billingPeriodEnd when currentPeriod is missing.
weekly = scanner.limits_from_billing({
  "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY", "end": "2026-08-25T00:00:00Z"},
  "creditUsagePercent": 250,
})
summary["percentClamped"] = weekly[0]["percent"] == 1.0

no_ondemand = scanner.limits_from_billing({
  "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY", "end": "x"},
  "creditUsagePercent": 5,
  "onDemandCap": {"val": 0},
  "onDemandUsed": {"val": 3},
})
summary["ondemandHiddenWithoutCap"] = len(no_ondemand) == 1

fallback_end = scanner.limits_from_billing({
  "currentPeriod": {"type": "USAGE_PERIOD_TYPE_UNKNOWN"},
  "creditUsagePercent": 5,
  "billingPeriodEnd": "2026-09-01T00:00:00Z",
})
summary["unknownPeriodLabel"] = fallback_end[0]["label"] == "Period"
summary["resetFallsBackToBillingPeriod"] = fallback_end[0]["resetsAt"] == "2026-09-01T00:00:00Z"

# GrokBillingClient maps HTTP status codes onto GrokAuthError kinds; the
# collector then translates those into the panel's status/help text.
def http_error(code):
  return urllib.error.HTTPError("https://example", code, "boom", {}, None)

client = scanner.GrokBillingClient("t", "https://example.invalid")
with mock.patch("urllib.request.urlopen", side_effect=http_error(401)):
  try:
    client.credits()
    summary["mapped401"] = False
  except scanner.GrokAuthError as e:
    summary["mapped401"] = "expired" in str(e).lower()

with mock.patch("urllib.request.urlopen", side_effect=http_error(403)):
  try:
    client.credits()
    summary["mapped403"] = False
  except scanner.GrokAuthError as e:
    summary["mapped403"] = "scope" in str(e).lower() or "forbidden" in str(e).lower()

print(json.dumps(summary, separators=(",", ":")))
PY
)

[[ $(jq -r '.record.todayPrompts' <<<"$result") == "1" ]] ||
  fail "Grok collector counts each turn_completed once" "$result"
pass "Grok collector counts each turn_completed once"

[[ $(jq -r '.record.activeDays' <<<"$result") == "2" ]] ||
  fail "Grok collector spans multiple days into activeDays" "$result"
pass "Grok collector spans multiple days into activeDays"

[[ $(jq -r '.record.totalSessions' <<<"$result") == "1" ]] ||
  fail "Grok collector counts one session per session directory" "$result"
pass "Grok collector counts one session per session directory"

[[ $(jq -c '.record.todayTokensByModel' <<<"$result") == '{"grok-4.6":275}' ]] ||
  fail "Grok collector groups today's tokens by model" "$result"
pass "Grok collector groups today's tokens by model"

[[ $(jq -c '.record.modelUsage["grok-4.6"]' <<<"$result") == '{"inputTokens":160,"outputTokens":125,"cacheReadInputTokens":140,"cacheCreationInputTokens":0}' ]] ||
  fail "Grok collector splits cached reads out of inputTokens for the model table" "$result"
pass "Grok collector splits cached reads out of inputTokens for the model table"

[[ $(jq -c '.record.limits' <<<"$result") == '[{"label":"Weekly","percent":0.425,"resetsAt":"2026-08-25T06:15:57+00:00"},{"label":"On-demand","percent":0.25,"resetsAt":"2026-08-25T06:15:57+00:00"}]' ]] ||
  fail "Grok collector emits weekly + on-demand limits from the billing config" "$result"
pass "Grok collector emits weekly + on-demand limits from the billing config"

[[ $(jq -r '.record.tierLabel + ":" + (.record.ready | tostring)' <<<"$result") == "grok.com:true" ]] ||
  fail "Grok collector labels an OIDC session as grok.com and marks it ready" "$result"
pass "Grok collector labels an OIDC session as grok.com and marks it ready"

[[ $(jq -r '.limitsOnlySkipsScan' <<<"$result") == "true" ]] ||
  fail "Grok collector's --limits-only skips the local scan but still fetches limits" "$result"
pass "Grok collector's --limits-only skips the local scan but still fetches limits"

[[ $(jq -r '.expired.usageStatusText' <<<"$result") == "Grok session expired" ]] ||
  fail "Grok collector surfaces 401 as a session-expired message" "$result"
[[ $(jq -r '.expired.hasLocalStats' <<<"$result") == "true" ]] ||
  fail "Grok collector preserves local stats when billing 401s" "$result"
pass "Grok collector preserves local stats when billing 401s"

[[ $(jq -r '.forbidden' <<<"$result") =~ "scope" ]] ||
  fail "Grok collector distinguishes 403 from expired" "$result"
pass "Grok collector distinguishes 403 from expired"

[[ $(jq -r '.networkFailure' <<<"$result") =~ "reach" ]] ||
  fail "Grok collector surfaces network failure as billing status" "$result"
pass "Grok collector surfaces network failure as billing status"

[[ $(jq -r '.envKeyWins' <<<"$result") == "true" ]] ||
  fail "Grok collector honors XAI_API_KEY over the disk auth" "$result"
pass "Grok collector honors XAI_API_KEY over the disk auth"

[[ $(jq -r '.expiredAuth.status' <<<"$result") == "Grok session expired" ]] ||
  fail "Grok collector flags an expired disk auth" "$result"
[[ $(jq -r '.expiredAuth.token' <<<"$result") == "stale" ]] ||
  fail "Grok collector still returns the expired token so a retry can decide what to do" "$result"
pass "Grok collector flags an expired disk auth without discarding the token"

[[ $(jq -r '.missingAuth.status' <<<"$result") == "Grok signed out" ]] ||
  fail "Grok collector reports signed-out when auth.json is missing" "$result"
pass "Grok collector reports signed-out when auth.json is missing"

[[ $(jq -r '.percentClamped' <<<"$result") == "true" ]] ||
  fail "Grok collector clamps limits.percent to at most 1.0" "$result"
pass "Grok collector clamps limits.percent to at most 1.0"

[[ $(jq -r '.ondemandHiddenWithoutCap' <<<"$result") == "true" ]] ||
  fail "Grok collector hides the on-demand bar when no cap is configured" "$result"
pass "Grok collector hides the on-demand bar when no cap is configured"

[[ $(jq -r '.unknownPeriodLabel' <<<"$result") == "true" ]] ||
  fail "Grok collector falls back to a generic label for unknown period types" "$result"
[[ $(jq -r '.resetFallsBackToBillingPeriod' <<<"$result") == "true" ]] ||
  fail "Grok collector falls back to billingPeriodEnd when currentPeriod.end is missing" "$result"
pass "Grok collector falls back to billingPeriodEnd when currentPeriod.end is missing"

[[ $(jq -r '.mapped401' <<<"$result") == "true" ]] ||
  fail "GrokBillingClient maps HTTP 401 onto a session-expired GrokAuthError" "$result"
pass "GrokBillingClient maps HTTP 401 onto a session-expired GrokAuthError"

[[ $(jq -r '.mapped403' <<<"$result") == "true" ]] ||
  fail "GrokBillingClient maps HTTP 403 onto a scope-denied GrokAuthError" "$result"
pass "GrokBillingClient maps HTTP 403 onto a scope-denied GrokAuthError"
