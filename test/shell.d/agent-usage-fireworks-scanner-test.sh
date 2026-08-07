#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

auth_file="$TEST_HOME/auth.ini"
cat >"$auth_file" <<'EOF'
[default]
api_key = fw_test
account_id = example
EOF

mkdir -p "$TEST_HOME/.config/omarchy/agents"
cat >"$TEST_HOME/.config/omarchy/agents/fireworks.json" <<'EOF'
{
  "accountId": "example",
  "fundedAmount": 20,
  "fundedAt": "2026-07-01"
}
EOF

# Without credentials the collector must still print a full, hidden-by-default
# record: the update runner writes whatever valid JSON appears on stdout.
no_key=$(HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" XDG_DATA_HOME="$TEST_HOME/.local/share" \
  FIREWORKS_API_KEY="" FIREWORKS_AUTH_PATH="$TEST_HOME/missing.ini" "$ROOT/bin/omarchy-agent-usage-fireworks")

[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + (.hasPromptStats | tostring)' <<<"$no_key") == "fireworks:false:false" ]] ||
  fail "Fireworks collector prints a valid record without credentials" "$no_key"
pass "Fireworks collector prints a valid record without credentials"

result=$(python3 - "$ROOT/bin/omarchy-agent-usage-fireworks" "$auth_file" "$TEST_HOME/.config" "$TEST_HOME/.local/share" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import sys
import time
from datetime import date
from decimal import Decimal
from pathlib import Path

collector_path = str(Path(sys.argv[1]))
auth_path = Path(sys.argv[2])
os.environ["XDG_CONFIG_HOME"] = sys.argv[3]
os.environ["XDG_DATA_HOME"] = sys.argv[4]

# Bucket dates resolve in local time, so pin the zone or the fixtures below
# would shift by a day depending on where the test runs. The env account id
# would override the config file, so it must not leak in from the runner.
os.environ["TZ"] = "UTC"
time.tzset()
os.environ.pop("FIREWORKS_ACCOUNT_ID", None)

loader = importlib.machinery.SourceFileLoader("fireworks_collector", collector_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)
RealFireworksClient = scanner.FireworksClient

payload = {
  "serverlessCosts": [
    {
      "startTime": "2026-07-31T00:00:00Z",
      "promptTokens": "100",
      "cachedPromptTokens": "40",
      "uncachedPromptTokens": "60",
      "completionTokens": "20",
      "group": {"model_name": "accounts/fireworks/models/kimi-k2p5"},
    },
    {
      "startTime": "2026-07-30T00:00:00Z",
      "promptTokens": "300",
      "cachedPromptTokens": "0",
      "completionTokens": "50",
      "group": {"model_name": "accounts/fireworks/models/deepseek-v3p2"},
    },
    {
      "startTime": "2026-07-20T00:00:00Z",
      "promptTokens": "500",
      "cachedPromptTokens": "0",
      "completionTokens": "100",
      "group": {"model_name": "accounts/fireworks/models/kimi-k2p5"},
    },
  ]
}

summary = scanner.summarize_usage(payload, date(2026, 7, 31))
api_key, account_id = scanner.read_auth_file(auth_path)
summary["apiKey"] = api_key
summary["accountId"] = account_id
summary["money"] = float(scanner.money_value({"units": "12", "nanos": 430000000}))

# The opencode key only wins when no explicit key or firectl login exists.
data_home = Path(os.environ["XDG_DATA_HOME"])
opencode_auth = data_home / "opencode" / "auth.json"
opencode_auth.parent.mkdir(parents=True, exist_ok=True)
opencode_auth.write_text(json.dumps({"fireworks-ai": {"type": "api", "key": "fw_opencode"}}))
os.environ.pop("FIREWORKS_API_KEY", None)
opencode_key, _ = scanner.credentials(Path("/nonexistent/auth.ini"), {})
firectl_key, _ = scanner.credentials(auth_path, {})
summary["opencodeFallback"] = opencode_key == "fw_opencode" and firectl_key == "fw_test"

class WorkingClient:
  def __init__(self, api_key, base_url):
    pass

  def request(self, path, query=None, body=None):
    raise scanner.FireworksError("The Fireworks API key cannot read billing data")

  def usage(self, account_id, start_day, end_day):
    return payload

  def account(self, account_id):
    return {}

  def spent(self, account_id, start_at, end_at):
    return Decimal("8.60")

class BalanceFailureClient(WorkingClient):
  def spent(self, account_id, start_at, end_at):
    raise scanner.FireworksError("Billing scope denied")

class LiveBalanceClient(WorkingClient):
  def request(self, path, query=None, body=None):
    assert path.endswith(":getBalance")
    return {"balance": {"units": "12", "nanos": 500000000}}

os.environ["FIREWORKS_API_KEY"] = "fw_test"

scanner.FireworksClient = WorkingClient
record = scanner.scan("https://example.invalid", auth_path)
summary["record"] = {
  "schemaVersion": record["schemaVersion"],
  "id": record["id"],
  "ready": record["ready"],
  "hasPromptStats": record["hasPromptStats"],
  "scope": record["scope"],
  "tierLabel": record["tierLabel"],
  "limits": record["limits"],
  "balance": record["balance"],
}

# billingUsage pages long ranges; usage() must follow continuation tokens.
pages = {
  "": {"serverlessCosts": [{"startTime": "2026-07-30T00:00:00Z"}], "nextPageToken": "p2"},
  "p2": {"serverlessCosts": [{"startTime": "2026-07-31T00:00:00Z"}]},
}
paging_client = RealFireworksClient("fw_test", "https://example.invalid")
paging_queries = []
def paged_request(path, query=None, body=None):
  paging_queries.append(dict(query or {}))
  return pages[str((query or {}).get("pageToken") or "")]
paging_client.request = paged_request
merged = paging_client.usage("example", date(2026, 7, 1), date(2026, 8, 1))
summary["paginationMerges"] = (
  len(merged["serverlessCosts"]) == 2
  and len(paging_queries) == 2
  and paging_queries[0]["startTime"] == "2026-07-01T00:00:00Z"
)

scanner.FireworksClient = LiveBalanceClient
live = scanner.scan("https://example.invalid", auth_path)
summary["liveBalance"] = live["balance"]

scanner.FireworksClient = BalanceFailureClient
scanned = scanner.scan("https://example.invalid", auth_path)
summary["balanceFailurePreservesTokens"] = (
  scanned["ready"] is True
  and "balance" not in scanned
  and scanned["modelUsage"]["kimi-k2.5"]["outputTokens"] == 120
  and scanned["usageStatusText"] == "Balance unavailable"
)

# East of Greenwich, a local-midnight bucket starts on the previous UTC date;
# the row must still land on the local day it names, and the query window
# must ask for local midnights expressed in UTC.
os.environ["TZ"] = "Etc/GMT-2"
time.tzset()
summary["bucketDayIsLocal"] = scanner.row_date({"startTime": "2026-07-30T22:00:00Z"}) == "2026-07-31"
summary["windowIsLocalMidnight"] = scanner.local_midnight_utc(date(2026, 7, 31)) == "2026-07-30T22:00:00Z"
print(json.dumps(summary, separators=(",", ":")))
PY
)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "120" ]] ||
  fail "Fireworks collector totals today's uncached, cached, and output tokens once" "$result"
pass "Fireworks collector totals today's token categories once"

[[ $(jq -c '.modelUsage["kimi-k2.5"]' <<<"$result") == '{"inputTokens":560,"outputTokens":120,"cacheReadInputTokens":40,"cacheCreationInputTokens":0}' ]] ||
  fail "Fireworks collector keeps cache separate in model totals" "$result"
pass "Fireworks collector keeps cache separate in model totals"

[[ $(jq -r '.recentDays[-1].messageCount' <<<"$result") == "120" ]] ||
  fail "Fireworks collector builds the seven-day token series" "$result"
pass "Fireworks collector builds the seven-day token series"

[[ $(jq -r '.activeDays' <<<"$result") == "3" ]] ||
  fail "Fireworks collector retains the 30-day model window" "$result"
pass "Fireworks collector retains the 30-day model window"

[[ $(jq -r '.apiKey + ":" + .accountId' <<<"$result") == "fw_test:example" ]] ||
  fail "Fireworks collector reads firectl credentials" "$result"
pass "Fireworks collector reads firectl credentials"

[[ $(jq -r '.money' <<<"$result") == "12.43" ]] ||
  fail "Fireworks collector parses Money units and nanos" "$result"
pass "Fireworks collector parses Money units and nanos"

[[ $(jq -c '.record | {schemaVersion, id, ready, hasPromptStats, scope, tierLabel, limits}' <<<"$result") == '{"schemaVersion":1,"id":"fireworks","ready":true,"hasPromptStats":false,"scope":"account","tierLabel":"Prepaid","limits":[]}' ]] ||
  fail "Fireworks collector prints the display-ready record contract" "$result"
pass "Fireworks collector prints the display-ready record contract"

[[ $(jq -r '.paginationMerges' <<<"$result") == "true" ]] ||
  fail "Fireworks collector follows billingUsage continuation tokens" "$result"
pass "Fireworks collector follows billingUsage continuation tokens"

[[ $(jq -r '.windowIsLocalMidnight' <<<"$result") == "true" ]] ||
  fail "Fireworks collector requests local-midnight windows in UTC" "$result"
pass "Fireworks collector requests local-midnight windows in UTC"

[[ $(jq -c '.record.balance' <<<"$result") == '{"remaining":11.4,"funded":20.0,"spent":8.6,"currency":"USD","estimated":true}' ]] ||
  fail "Fireworks collector estimates the balance from configured funding" "$result"
pass "Fireworks collector estimates the balance from configured funding"

[[ $(jq -c '.liveBalance' <<<"$result") == '{"remaining":12.5,"funded":20.0,"spent":7.5,"currency":"USD","estimated":false}' ]] ||
  fail "Fireworks collector prefers the live getBalance ledger when the key can read it" "$result"
pass "Fireworks collector prefers the live getBalance ledger when the key can read it"

[[ $(jq -r '.balanceFailurePreservesTokens' <<<"$result") == "true" ]] ||
  fail "Fireworks collector preserves tokens when balance lookup fails" "$result"
pass "Fireworks collector preserves tokens when balance lookup fails"

[[ $(jq -r '.bucketDayIsLocal' <<<"$result") == "true" ]] ||
  fail "Fireworks collector dates buckets by local day east of Greenwich" "$result"
pass "Fireworks collector dates buckets by local day east of Greenwich"

[[ $(jq -r '.opencodeFallback' <<<"$result") == "true" ]] ||
  fail "Fireworks collector falls back to the opencode key last" "$result"
pass "Fireworks collector falls back to the opencode key last"
