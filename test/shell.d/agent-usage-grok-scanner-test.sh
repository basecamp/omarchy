#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.grok/logs" "$TEST_HOME/.config/omarchy/agents"

# Without a local log and without a management key, the collector must still
# print a full, hidden-by-default record rather than nothing at all.
no_data=$(HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" XAI_MANAGEMENT_KEY="" \
  "$ROOT/bin/omarchy-agent-usage-grok")

[[ $(jq -r '.id + ":" + (.ready | tostring)' <<<"$no_data") == "grok:false" ]] ||
  fail "Grok collector prints a valid record without a log or a key" "$no_data"
pass "Grok collector prints a valid record without a log or a key"

result=$(HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" python3 - "$ROOT/bin/omarchy-agent-usage-grok" "$TEST_HOME" <<'PY'
import importlib.machinery
import importlib.util
import io
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

collector_path = str(Path(sys.argv[1]))
home = Path(sys.argv[2])

loader = importlib.machinery.SourceFileLoader("grok_collector", collector_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

summary = {}

# A live account showed prepaidBalance.val: 638 against an actual $6.38
# balance, and creditUsagePercent: 100.0 for a fully used weekly allowance —
# the fixture below reproduces both real numbers, plus an on-demand pool and
# an older, superseded snapshot the scanner must skip in favor of the newest.
log_path = home / ".grok" / "logs" / "unified.jsonl"
older = {
  "ts": "2026-08-30T04:50:46.895Z",
  "msg": "billing: fetched credits config",
  "ctx": {
    "config": {
      "creditUsagePercent": 31.0,
      "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY", "start": "2026-08-28T06:16:57+00:00", "end": "2026-09-04T06:16:57+00:00"},
      "onDemandCap": {"val": 0},
      "onDemandUsed": {"val": 0},
      "prepaidBalance": {"val": 0},
    },
    "subscriptionTier": "SuperGrok",
  },
}
newest_ts = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
newest = {
  "ts": newest_ts,
  "msg": "billing: fetched credits config",
  "ctx": {
    "config": {
      "creditUsagePercent": 100.0,
      "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY", "start": "2026-08-28T06:16:57+00:00", "end": "2026-09-04T06:16:57+00:00"},
      "onDemandCap": {"val": 5},
      "onDemandUsed": {"val": 2},
      "prepaidBalance": {"val": 638},
    },
    "subscriptionTier": "SuperGrok",
  },
}
log_path.write_text(json.dumps(older) + "\n" + json.dumps(newest) + "\n")

record = collector.scan()
summary["record"] = {
  "id": record["id"],
  "ready": record["ready"],
  "tierLabel": record["tierLabel"],
  "limits": record["limits"],
  "balance": record["balance"],
  "usageStatusText": record["usageStatusText"],
}

# latest_credits_config() must pick the newest line by timestamp, not the
# last one physically in the file, and must skip a line whose ctx isn't a
# dict rather than crash on it.
log_path.write_text(
  json.dumps(newest) + "\n" +
  json.dumps(older) + "\n" +
  json.dumps({"ts": "2099-01-01T00:00:00Z", "msg": "billing: fetched credits config", "ctx": "not a dict"}) + "\n"
)
picked_ts, picked_ctx = collector.latest_credits_config()
summary["pickedNewestRegardlessOfFileOrder"] = picked_ts == newest_ts and picked_ctx["config"]["creditUsagePercent"] == 100.0

# A stale snapshot (older than 48h) gets a visible note; a fresh one doesn't.
stale = dict(newest)
stale["ts"] = (datetime.now(timezone.utc) - timedelta(hours=72)).isoformat().replace("+00:00", "Z")
stale_record = collector.record_from_local_billing(stale["ts"], stale["ctx"])
summary["staleNoted"] = "run `grok` to refresh" in stale_record["usageStatusText"]

fresh_record = collector.record_from_local_billing(newest["ts"], newest["ctx"])
summary["freshNotNoted"] = fresh_record["usageStatusText"] == ""

# credentials(): a configured management key wins over the CLI session, and
# still borrows the CLI session's team_id when the config doesn't set one.
auth_path = home / ".grok" / "auth.json"
auth_path.write_text(json.dumps({
  "https://auth.x.ai::agent": {
    "key": "cli_token",
    "team_id": "cli-team",
    "expires_at": (datetime.now(timezone.utc) + timedelta(days=1)).isoformat(),
  }
}))
config_path = home / ".config" / "omarchy" / "agents" / "grok.json"
config_path.write_text(json.dumps({"managementKey": "mgmt_token"}))
token, team_id, from_cli = collector.credentials()
summary["configuredKeyWinsWithCliTeamId"] = (token, team_id, from_cli) == ("mgmt_token", "cli-team", False)

log_path.unlink()

# The Management API fallback: summarize_balance's plain-decimal-string
# parse, total_spend_usd's series sum, and the 403 error path's CLI-token
# hint (the collector's own confirmed finding: the Grok CLI's OAuth token is
# inference-scoped only, so a 403 there gets an extra hint the fallback from
# a configured key does not).
config_path.write_text(json.dumps({"managementKey": "", "teamId": ""}))

balance = collector.summarize_balance({"total": {"val": "6.38"}, "changes": []})
summary["balanceParsesPlainDecimalString"] = balance == {
  "remaining": 6.0,
  "funded": 0.0,
  "spent": 0.0,
  "currency": "USD",
  "estimated": False,
}

cost_payload = {"timeSeries": [
  {"dataPoints": [{"values": [1.5]}, {"values": [2.25]}]},
  {"dataPoints": [{"values": ["not-a-number"]}]},
]}
summary["totalSpendSumsSeries"] = collector.total_spend_usd(cost_payload) == 3.75

class ForbiddenClient:
  def __init__(self, token):
    pass

  def prepaid_balance(self, team_id):
    raise collector.GrokError("This key cannot read billing data for the team")

collector.GrokClient = ForbiddenClient
fallback_record = collector.scan()
summary["forbiddenHintsCliToken"] = "session token may not be scoped" in fallback_record["authHelpText"]

print(json.dumps(summary, separators=(",", ":")))
PY
)

[[ $(jq -c '.record' <<<"$result") == '{"id":"grok","ready":true,"tierLabel":"SuperGrok","limits":[{"label":"Weekly","percent":1.0,"resetsAt":"2026-09-04T06:16:57+00:00"},{"label":"On-demand","percent":0.4,"resetsAt":"2026-09-04T06:16:57+00:00"}],"balance":{"remaining":6.38,"funded":0.0,"spent":0.0,"currency":"USD","estimated":false},"usageStatusText":""}' ]] ||
  fail "Grok collector builds the display-ready record from the local billing log" "$result"
pass "Grok collector builds the display-ready record from the local billing log"

[[ $(jq -r '.pickedNewestRegardlessOfFileOrder' <<<"$result") == "true" ]] ||
  fail "Grok collector reads the newest credits-config line by timestamp, not file order" "$result"
pass "Grok collector reads the newest credits-config line by timestamp, not file order"

[[ $(jq -r '.staleNoted' <<<"$result") == "true" && $(jq -r '.freshNotNoted' <<<"$result") == "true" ]] ||
  fail "Grok collector notes a stale local snapshot but not a fresh one" "$result"
pass "Grok collector notes a stale local snapshot but not a fresh one"

[[ $(jq -r '.configuredKeyWinsWithCliTeamId' <<<"$result") == "true" ]] ||
  fail "Grok collector prefers a configured management key, borrowing the CLI session's team_id" "$result"
pass "Grok collector prefers a configured management key, borrowing the CLI session's team_id"

[[ $(jq -r '.balanceParsesPlainDecimalString' <<<"$result") == "true" ]] ||
  fail "Grok collector parses the Management API's plain-decimal-string balance" "$result"
pass "Grok collector parses the Management API's plain-decimal-string balance"

[[ $(jq -r '.totalSpendSumsSeries' <<<"$result") == "true" ]] ||
  fail "Grok collector sums the cost-analytics series, skipping unparseable values" "$result"
pass "Grok collector sums the cost-analytics series, skipping unparseable values"

[[ $(jq -r '.forbiddenHintsCliToken' <<<"$result") == "true" ]] ||
  fail "Grok collector hints that a CLI-session token may lack billing scope on 403" "$result"
pass "Grok collector hints that a CLI-session token may lack billing scope on 403"
