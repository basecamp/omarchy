#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# Without credentials the collector must still print a full, hidden-by-default
# record: the update runner writes whatever valid JSON appears on stdout.
no_key=$(HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  OPENCODE_GO_API_KEY="" "$ROOT/bin/omarchy-agent-usage-opencode-go")

[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + .name + ":" + .tierLabel' <<<"$no_key") == "opencode-go:false:OpenCode:Go" ]] ||
  fail "OpenCode collector prints a valid record without credentials" "$no_key"
pass "OpenCode collector prints a valid record without credentials"

result=$(python3 - "$ROOT/bin/omarchy-agent-usage-opencode-go" "$TEST_HOME" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import sqlite3
import sys
import time
from datetime import date, datetime, timedelta
from pathlib import Path

collector_path = str(Path(sys.argv[1]))
test_home = Path(sys.argv[2])

os.environ["TZ"] = "UTC"
time.tzset()
os.environ.pop("OPENCODE_GO_API_KEY", None)

loader = importlib.machinery.SourceFileLoader("opencode_collector", collector_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)

data_home = test_home / "data"
auth_path = data_home / "opencode" / "auth.json"
auth_path.parent.mkdir(parents=True, exist_ok=True)
auth_path.write_text(json.dumps({"opencode-go": {"type": "api", "key": "sk_fixture"}}))

# A fixture opencode database: assistant messages on the opencode-go provider
# carry the model, token split, and a millisecond timestamp; everything else
# (user rows, other providers, zero-token rows) must be skipped.
db = data_home / "opencode" / "opencode.db"
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, data TEXT NOT NULL)")
now_ms = int(time.time() * 1000)
def day_offset(days):
  return now_ms - days * 86400 * 1000
rows = [
  ("m1", "s1", {"role": "assistant", "providerID": "opencode-go", "modelID": "deepseek-v4-flash",
                "tokens": {"input": 1000, "output": 500, "reasoning": 100, "cache": {"read": 200, "write": 50}},
                "time": {"created": day_offset(0)}}),
  ("m2", "s2", {"role": "assistant", "providerID": "opencode-go", "modelID": "deepseek-v4-flash",
                "tokens": {"input": 100, "output": 20, "cache": {"read": 0, "write": 0}},
                "time": {"created": day_offset(2)}}),
  ("m3", "s3", {"role": "assistant", "providerID": "opencode-go", "modelID": "deepseek-v4-flash",
                "tokens": {"input": 50, "output": 10},
                "time": {"created": day_offset(8)}}),
  ("m4", "s4", {"role": "user", "providerID": "opencode-go", "modelID": "deepseek-v4-flash",
                "tokens": {"input": 9999, "output": 9999},
                "time": {"created": day_offset(0)}}),
  ("m5", "s5", {"role": "assistant", "providerID": "anthropic", "modelID": "claude-opus-4-8",
                "tokens": {"input": 9999, "output": 9999},
                "time": {"created": day_offset(0)}}),
  ("m6", "s6", {"role": "assistant", "providerID": "opencode-go", "modelID": "deepseek-v4-flash",
                "tokens": {"input": 0, "output": 0},
                "time": {"created": day_offset(0)}}),
]
conn.executemany("INSERT INTO message (id, session_id, data) VALUES (?, ?, ?)",
                 [(mid, sid, json.dumps(data)) for mid, sid, data in rows])
conn.commit()
conn.close()

summary = {}
summary["dbStats"] = scanner.scan_opencode_db(db)

# The official endpoint nests the windows under "usage"; the merged PR shape
# spelled them "<window>Usage" with resetInSec. Both must parse to the same
# panel contract, and a rate-limited window reports 100%.
live_payload = {
  "usage": {
    "rolling": {"status": "ok", "percent": 2, "resetsAt": "2026-08-13T00:15:17.598Z"},
    "weekly": {"status": "ok", "percent": 3, "resetsAt": "2026-08-17T00:00:00.598Z"},
    "monthly": {"status": "ok", "percent": 38, "resetsAt": "2026-08-27T01:24:06.598Z"},
  }
}
pr_payload = {
  "rollingUsage": {"status": "ok", "usagePercent": 19, "resetInSec": 7200},
  "weeklyUsage": {"status": "ok", "usagePercent": 5, "resetInSec": 3600},
}
summary["liveLimits"] = scanner.parse_usage_payload(live_payload)
summary["prLimits"] = scanner.parse_usage_payload(pr_payload)
summary["rateLimited"] = scanner.parse_usage_payload(
  {"usage": {"rolling": {"status": "rate-limited", "percent": 88, "resetsAt": "2026-08-13T00:15:17.598Z"}}}
)
summary["percentScaling"] = [
  scanner.normalize_percent(2), scanner.normalize_percent(0.5),
  scanner.normalize_percent(100), scanner.normalize_percent(-1), scanner.normalize_percent("x"),
]

# The env var is an explicit override; the opencode auth.json entry is the
# native source. Empty store means no key at all.
os.environ["OPENCODE_GO_API_KEY"] = "sk_env"
summary["envKeyWins"] = scanner.credentials(auth_path) == "sk_env"
os.environ.pop("OPENCODE_GO_API_KEY", None)
summary["authJsonKey"] = scanner.credentials(auth_path)
empty_auth = test_home / "empty-auth.json"
empty_auth.write_text("{}")
summary["missingKey"] = scanner.credentials(empty_auth)
summary["noKeyStatus"] = scanner.collect_limits("", "https://example.invalid", False)["usageStatusText"]

def fresh_cache(name):
  return test_home / "cache" / name

class LiveClient:
  def __init__(self, api_key, base_url):
    pass
  def probe(self):
    return live_payload

class RejectingClient:
  def __init__(self, api_key, base_url):
    pass
  def probe(self):
    raise scanner.GoUsageError("OpenCode Go rejected the API key")

class OfflineClient:
  def __init__(self, api_key, base_url):
    pass
  def probe(self):
    raise scanner.GoUsageError("Could not reach OpenCode's usage endpoint")

os.environ["XDG_CACHE_HOME"] = str(fresh_cache("live"))
scanner.GoUsageClient = LiveClient
live_record = scanner.scan(auth_path, db, "https://example.invalid")
summary["record"] = {
  "schemaVersion": live_record["schemaVersion"],
  "id": live_record["id"],
  "name": live_record["name"],
  "ready": live_record["ready"],
  "hasLocalStats": live_record["hasLocalStats"],
  "scope": live_record["scope"],
  "hasPromptStats": live_record["hasPromptStats"],
  "tierLabel": live_record["tierLabel"],
  "limits": live_record["limits"],
}

os.environ["XDG_CACHE_HOME"] = str(fresh_cache("reject"))
scanner.GoUsageClient = RejectingClient
rejected = scanner.scan(auth_path, db, "https://example.invalid")
summary["rejected"] = {
  "ready": rejected["ready"],
  "limits": rejected["limits"],
  "usageStatusText": rejected["usageStatusText"],
  "authHelpText": rejected["authHelpText"],
  "totalPrompts": rejected["totalPrompts"],
}

os.environ["XDG_CACHE_HOME"] = str(fresh_cache("offline"))
scanner.GoUsageClient = OfflineClient
offline = scanner.scan(auth_path, db, "https://example.invalid")
summary["offline"] = {
  "retryAdvised": offline.get("retryAdvised") is True,
  "totalPrompts": offline["totalPrompts"],
}
print(json.dumps(summary, separators=(",", ":")))
PY
)

[[ $(jq -r '.record | {schemaVersion, id, name, ready, hasLocalStats, scope, hasPromptStats, tierLabel} | tostring' <<<"$result") == \
  '{"schemaVersion":1,"id":"opencode-go","name":"OpenCode","ready":true,"hasLocalStats":true,"scope":"device","hasPromptStats":true,"tierLabel":"Go"}' ]] ||
  fail "OpenCode collector prints the display-ready record contract" "$result"
pass "OpenCode collector prints the display-ready record contract"

[[ $(jq -r '.dbStats.todayTotalTokens' <<<"$result") == "1850" ]] ||
  fail "OpenCode collector totals today's input, output, reasoning, and cache tokens once" "$result"
pass "OpenCode collector totals today's input, output, reasoning, and cache tokens once"

[[ $(jq -r '.dbStats.todayPrompts' <<<"$result") == "1" ]] ||
  fail "OpenCode collector counts one prompt for today" "$result"
pass "OpenCode collector counts one prompt for today"

[[ $(jq -r '.dbStats.totalPrompts' <<<"$result") == "3" ]] ||
  fail "OpenCode collector keeps user rows, other providers, and zero-token rows out" "$result"
pass "OpenCode collector keeps user rows, other providers, and zero-token rows out"

[[ $(jq -r '.dbStats.activeDays' <<<"$result") == "3" ]] ||
  fail "OpenCode collector counts every distinct day with usage" "$result"
pass "OpenCode collector counts every distinct day with usage"

[[ $(jq -r '.dbStats.recentDays[-1].messageCount' <<<"$result") == "1850" ]] ||
  fail "OpenCode collector builds the seven-day token series" "$result"
pass "OpenCode collector builds the seven-day token series"

[[ $(jq -c '.dbStats.modelUsage["deepseek-v4-flash"]' <<<"$result") == \
  '{"inputTokens":1150,"outputTokens":630,"cacheReadInputTokens":200,"cacheCreationInputTokens":50}' ]] ||
  fail "OpenCode collector keeps cache and reasoning split in model totals" "$result"
pass "OpenCode collector keeps cache and reasoning split in model totals"

[[ $(jq -c '[.liveLimits[].percent]' <<<"$result") == '[0.02,0.03,0.38]' ]] ||
  fail "OpenCode collector scales endpoint percentages into 0..1" "$result"
pass "OpenCode collector scales endpoint percentages into 0..1"

[[ $(jq -r '[.liveLimits[].label] | join(",")' <<<"$result") == "Session (5-hour),Weekly (7-day),Monthly (30-day)" ]] ||
  fail "OpenCode collector labels the rolling, weekly, and monthly windows" "$result"
pass "OpenCode collector labels the rolling, weekly, and monthly windows"

[[ $(jq -r '.liveLimits[0].resetsAt' <<<"$result") == "2026-08-13T00:15:17.598Z" ]] ||
  fail "OpenCode collector passes reset timestamps through" "$result"
pass "OpenCode collector passes reset timestamps through"

[[ $(jq -r '[.prLimits[].percent] | join(",")' <<<"$result") == "0.19,0.05" ]] ||
  fail "OpenCode collector parses the merged PR shape" "$result"
pass "OpenCode collector parses the merged PR shape"

[[ $(jq -r '.prLimits[0].resetsAt | length > 10' <<<"$result") == "true" ]] ||
  fail "OpenCode collector turns resetInSec into a timestamp" "$result"
pass "OpenCode collector turns resetInSec into a timestamp"

[[ $(jq -r '.rateLimited[0].percent' <<<"$result") == "1.0" ]] ||
  fail "OpenCode collector reports a rate-limited window at 100%" "$result"
pass "OpenCode collector reports a rate-limited window at 100%"

[[ $(jq -c '.percentScaling' <<<"$result") == '[0.02,0.5,1.0,null,null]' ]] ||
  fail "OpenCode collector distinguishes percent and fraction scales" "$result"
pass "OpenCode collector distinguishes percent and fraction scales"

[[ $(jq -r '(.envKeyWins | tostring) + ":" + .authJsonKey + ":" + .missingKey' <<<"$result") == "true:sk_fixture:" ]] ||
  fail "OpenCode collector reads the key from the environment or the opencode auth store" "$result"
pass "OpenCode collector reads the key from the environment or the opencode auth store"

[[ $(jq -r '.noKeyStatus' <<<"$result") == "Waiting for auth" ]] ||
  fail "OpenCode collector says so when no key exists" "$result"
pass "OpenCode collector says so when no key exists"

[[ $(jq -c '.rejected | {ready, limits, usageStatusText, totalPrompts}' <<<"$result") == \
  '{"ready":true,"limits":[],"usageStatusText":"OpenCode Go limits unavailable","totalPrompts":3}' ]] ||
  fail "OpenCode collector keeps local stats when the endpoint rejects the key" "$result"
pass "OpenCode collector keeps local stats when the endpoint rejects the key"

[[ $(jq -r '.rejected.authHelpText' <<<"$result") == *"rejected"* ]] ||
  fail "OpenCode collector explains a rejected key" "$result"
pass "OpenCode collector explains a rejected key"

[[ $(jq -r '(.offline.retryAdvised | tostring) + ":" + (.offline.totalPrompts | tostring)' <<<"$result") == "true:3" ]] ||
  fail "OpenCode collector asks for a sooner retry after a transport failure" "$result"
pass "OpenCode collector asks for a sooner retry after a transport failure"
