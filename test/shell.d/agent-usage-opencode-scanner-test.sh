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
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

collector_path = str(Path(sys.argv[1]))
test_home = Path(sys.argv[2])

os.environ["TZ"] = "UTC"
time.tzset()
os.environ.pop("OPENCODE_GO_API_KEY", None)
os.environ["XDG_CACHE_HOME"] = str(test_home / "cache" / "default")

loader = importlib.machinery.SourceFileLoader("opencode_collector", collector_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)
RealGoUsageClient = scanner.GoUsageClient

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
  scanner.normalize_percent(2, True), scanner.normalize_percent(0.5, True),
  scanner.normalize_percent(100, True), scanner.normalize_percent(-1, True), scanner.normalize_percent("x", True),
]

# The scale is settled payload-wide, the way the claude collector does it: any
# value reaching 1 means the payload speaks percentages, so a lone 1 is 1% and
# a 0.5 beside a 2 is 0.5%, while an all-fraction payload keeps its values.
summary["onePercent"] = [w["percent"] for w in scanner.parse_usage_payload(
  {"usage": {"rolling": {"status": "ok", "percent": 1, "resetsAt": ""}}})]
summary["mixedScale"] = [w["percent"] for w in scanner.parse_usage_payload(
  {"usage": {"rolling": {"status": "ok", "percent": 0.5}, "weekly": {"status": "ok", "percent": 2}}})]
summary["mixedScaleLegacy"] = [w["percent"] for w in scanner.parse_usage_payload(
  {"rollingUsage": {"status": "ok", "usagePercent": 0.5}, "weeklyUsage": {"status": "ok", "usagePercent": 2}})]
summary["fractionScale"] = [w["percent"] for w in scanner.parse_usage_payload(
  {"usage": {"rolling": {"status": "ok", "percent": 0.25}, "weekly": {"status": "ok", "percent": 0.8}}})]

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
    raise scanner.GoUsageError("OpenCode Go rejected the API key", auth=True)

class OfflineClient:
  def __init__(self, api_key, base_url):
    pass
  def probe(self):
    raise scanner.GoUsageError("Could not reach OpenCode's usage endpoint", transport=True)

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

# A cached window only stands in for a failed probe while it is still open: a
# window whose reset time has passed describes a period that is over and must
# drop out instead of sitting on the panel as a dead meter.
def seed_probe_cache(limits, age_seconds=3600):
  cache_dir = Path(os.environ["XDG_CACHE_HOME"]) / "omarchy" / "agent-usage"
  cache_dir.mkdir(parents=True, exist_ok=True)
  (cache_dir / "opencode-go-limits.json").write_text(json.dumps(
    {"fetchedAtMs": int((time.time() - age_seconds) * 1000), "limits": limits}))

open_window = {"label": "Weekly (7-day)", "percent": 0.4,
               "resetsAt": (datetime.now(timezone.utc) + timedelta(hours=6)).isoformat()}
closed_window = {"label": "Session (5-hour)", "percent": 0.9,
                 "resetsAt": (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()}
# A missing or unreadable timestamp is no reason to throw away a real number.
unstamped_window = {"label": "Monthly (30-day)", "percent": 0.2, "resetsAt": ""}
odd_window = {"label": "Session (5-hour)", "percent": 0.1, "resetsAt": "not-a-date"}

os.environ["XDG_CACHE_HOME"] = str(fresh_cache("stale"))
seed_probe_cache([closed_window, open_window, unstamped_window, odd_window])
scanner.GoUsageClient = OfflineClient
stale = scanner.collect_limits("sk_fixture", "https://example.invalid", False)
summary["staleCache"] = {
  "labels": [w["label"] for w in stale["limits"]],
  "usageStatusText": stale["usageStatusText"],
  "retryAdvised": stale.get("retryAdvised") is True,
}

# A fresh-but-expired cache must not satisfy the probe-reuse window either;
# the collector re-probes and shows the live numbers.
os.environ["XDG_CACHE_HOME"] = str(fresh_cache("expired-fresh"))
seed_probe_cache([closed_window], age_seconds=0)
scanner.GoUsageClient = LiveClient
summary["expiredCacheReprobes"] = [w["label"] for w in scanner.collect_limits("sk_fixture", "https://example.invalid", False)["limits"]]

# A fresh cache of open windows satisfies the reuse window without a request;
# a forced refresh probes anyway — that is what the user asked for.
class CountingClient:
  calls = 0
  def __init__(self, api_key, base_url):
    pass
  def probe(self):
    CountingClient.calls += 1
    return live_payload

os.environ["XDG_CACHE_HOME"] = str(fresh_cache("reuse"))
seed_probe_cache([open_window], age_seconds=0)
scanner.GoUsageClient = CountingClient
reused = scanner.collect_limits("sk_fixture", "https://example.invalid", False)
calls_after_reuse = CountingClient.calls
forced = scanner.collect_limits("sk_fixture", "https://example.invalid", True)
summary["probeReuse"] = {
  "reusedLabels": [w["label"] for w in reused["limits"]],
  "callsAfterReuse": calls_after_reuse,
  "forcedLabels": [w["label"] for w in forced["limits"]],
  "callsAfterForce": CountingClient.calls,
}

# A payload with no recognizable windows is a failure too: still-open cached
# numbers beat an empty section.
class EmptyClient:
  def __init__(self, api_key, base_url):
    pass
  def probe(self):
    return {}

os.environ["XDG_CACHE_HOME"] = str(fresh_cache("empty-payload"))
seed_probe_cache([closed_window, open_window])
scanner.GoUsageClient = EmptyClient
summary["emptyPayloadFallback"] = [w["label"] for w in scanner.collect_limits("sk_fixture", "https://example.invalid", False)["limits"]]

# A rejected key keeps still-open numbers but says the sign-in is bad.
os.environ["XDG_CACHE_HOME"] = str(fresh_cache("rejected-cached"))
seed_probe_cache([closed_window, open_window])
scanner.GoUsageClient = RejectingClient
rejected_cached = scanner.collect_limits("sk_fixture", "https://example.invalid", False)
summary["rejectedCached"] = {
  "labels": [w["label"] for w in rejected_cached["limits"]],
  "usageStatusText": rejected_cached["usageStatusText"],
  "authHelpText": rejected_cached["authHelpText"],
}

# So does a missing key: still-open windows outlive the key that fetched them.
os.environ["XDG_CACHE_HOME"] = str(fresh_cache("no-key-cached"))
seed_probe_cache([closed_window, open_window])
no_key_cached = scanner.collect_limits("", "https://example.invalid", False)
summary["noKeyCached"] = {
  "labels": [w["label"] for w in no_key_cached["limits"]],
  "usageStatusText": no_key_cached["usageStatusText"],
}

# The probe itself is exercised against a stubbed transport so the request
# (path, bearer, user agent) and the failure mapping are pinned too — the
# client swaps above never see them. The collector's urlopen is swapped, not
# its GoUsageClient, the way the claude limits test swaps it.
scanner.GoUsageClient = RealGoUsageClient
captured = {}
class FakeResponse:
  def __init__(self, body):
    self._body = body
  def read(self):
    return self._body
  def __enter__(self):
    return self
  def __exit__(self, *args):
    return False

def stub_urlopen(request, timeout=None):
  captured["url"] = request.full_url
  captured["headers"] = {name.lower(): value for name, value in request.header_items()}
  if stub_urlopen.error is not None:
    raise stub_urlopen.error
  return FakeResponse(stub_urlopen.body)
stub_urlopen.error = None
stub_urlopen.body = b"{}"
scanner.urllib.request.urlopen = stub_urlopen

probe_client = scanner.GoUsageClient("sk_probe", "https://example.invalid")
stub_urlopen.body = json.dumps(live_payload).encode()
payload = probe_client.probe()
summary["probe"] = {
  "payloadIsLive": isinstance(payload, dict) and payload.get("usage") is not None,
  "url": captured["url"],
  "auth": captured["headers"].get("authorization", ""),
  "ua": captured["headers"].get("user-agent", ""),
  "accept": captured["headers"].get("accept", ""),
}

def error_text(error):
  flags = (":auth" if error.auth else "") + (":transport" if error.transport else "")
  return type(error).__name__ + ":" + str(error) + flags

stub_urlopen.error = scanner.urllib.error.HTTPError("https://example.invalid", 401, "Unauthorized", {}, None)
try:
  probe_client.probe()
  summary["probe401"] = "no-error"
except scanner.GoUsageError as error:
  summary["probe401"] = error_text(error)
stub_urlopen.error = scanner.urllib.error.HTTPError("https://example.invalid", 403, "Forbidden", {}, None)
try:
  probe_client.probe()
  summary["probe403"] = "no-error"
except scanner.GoUsageError as error:
  summary["probe403"] = error_text(error)
stub_urlopen.error = scanner.urllib.error.HTTPError("https://example.invalid", 500, "Server Error", {}, None)
try:
  probe_client.probe()
  summary["probe500"] = "no-error"
except scanner.GoUsageError as error:
  summary["probe500"] = error_text(error)
stub_urlopen.error = scanner.urllib.error.URLError(OSError("no route to host"))
try:
  probe_client.probe()
  summary["probeOffline"] = "no-error"
except scanner.GoUsageError as error:
  summary["probeOffline"] = error_text(error)
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

[[ $(jq -c '.percentScaling' <<<"$result") == '[0.02,0.005,1.0,null,null]' ]] ||
  fail "OpenCode collector scales every value once the payload speaks percentages" "$result"
pass "OpenCode collector scales every value once the payload speaks percentages"

{ [[ $(jq -c '.onePercent' <<<"$result") == '[0.01]' ]] && [[ $(jq -c '.mixedScale' <<<"$result") == '[0.005,0.02]' ]] &&
  [[ $(jq -c '.mixedScaleLegacy' <<<"$result") == '[0.005,0.02]' ]] && [[ $(jq -c '.fractionScale' <<<"$result") == '[0.25,0.8]' ]]; } ||
  fail "OpenCode collector settles the percent scale payload-wide" "$result"
pass "OpenCode collector settles the percent scale payload-wide"

[[ $(jq -r '(.envKeyWins | tostring) + ":" + .authJsonKey + ":" + .missingKey' <<<"$result") == "true:sk_fixture:" ]] ||
  fail "OpenCode collector reads the key from the environment or the opencode auth store" "$result"
pass "OpenCode collector reads the key from the environment or the opencode auth store"

[[ $(jq -r '.noKeyStatus' <<<"$result") == "Waiting for auth" ]] ||
  fail "OpenCode collector says so when no key exists" "$result"
pass "OpenCode collector says so when no key exists"

[[ $(jq -c '.rejected | {ready, limits, usageStatusText, totalPrompts}' <<<"$result") == \
  '{"ready":true,"limits":[],"usageStatusText":"Sign-in rejected","totalPrompts":3}' ]] ||
  fail "OpenCode collector keeps local stats when the endpoint rejects the key" "$result"
pass "OpenCode collector keeps local stats when the endpoint rejects the key"

[[ $(jq -r '.rejected.authHelpText' <<<"$result") == *"rejected"* ]] ||
  fail "OpenCode collector explains a rejected key" "$result"
pass "OpenCode collector explains a rejected key"

[[ $(jq -r '(.offline.retryAdvised | tostring) + ":" + (.offline.totalPrompts | tostring)' <<<"$result") == "true:3" ]] ||
  fail "OpenCode collector asks for a sooner retry after a transport failure" "$result"
pass "OpenCode collector asks for a sooner retry after a transport failure"

[[ $(jq -c '.staleCache' <<<"$result") == \
  '{"labels":["Weekly (7-day)","Monthly (30-day)","Session (5-hour)"],"usageStatusText":"","retryAdvised":true}' ]] ||
  fail "OpenCode collector drops cached windows that have reset when a probe fails" "$result"
pass "OpenCode collector drops cached windows that have reset when a probe fails"

[[ $(jq -c '.probeReuse' <<<"$result") == \
  '{"reusedLabels":["Weekly (7-day)"],"callsAfterReuse":0,"forcedLabels":["Session (5-hour)","Weekly (7-day)","Monthly (30-day)"],"callsAfterForce":1}' ]] ||
  fail "OpenCode collector reuses a fresh probe unless the refresh is forced" "$result"
pass "OpenCode collector reuses a fresh probe unless the refresh is forced"

[[ $(jq -r '.expiredCacheReprobes | join(",")' <<<"$result") == "Session (5-hour),Weekly (7-day),Monthly (30-day)" ]] ||
  fail "OpenCode collector re-probes instead of reusing a cache of expired windows" "$result"
pass "OpenCode collector re-probes instead of reusing a cache of expired windows"

[[ $(jq -c '.emptyPayloadFallback' <<<"$result") == '["Weekly (7-day)"]' ]] ||
  fail "OpenCode collector keeps open windows when the endpoint returns none" "$result"
pass "OpenCode collector keeps open windows when the endpoint returns none"

[[ $(jq -c '.rejectedCached | {labels, usageStatusText}' <<<"$result") == \
  '{"labels":["Weekly (7-day)"],"usageStatusText":"Sign-in rejected"}' ]] ||
  fail "OpenCode collector keeps open windows and flags the sign-in when the key is rejected" "$result"
pass "OpenCode collector keeps open windows and flags the sign-in when the key is rejected"

{ [[ $(jq -r '.rejectedCached.authHelpText' <<<"$result") == *"last known limits"* ]] &&
  [[ $(jq -r '.rejectedCached.authHelpText' <<<"$result") == *"opencode auth login"* ]]; } ||
  fail "OpenCode collector says the shown limits are the last known ones and how to fix the key" "$result"
pass "OpenCode collector says the shown limits are the last known ones and how to fix the key"

[[ $(jq -c '.noKeyCached' <<<"$result") == '{"labels":["Weekly (7-day)"],"usageStatusText":"Waiting for auth"}' ]] ||
  fail "OpenCode collector keeps open windows while waiting for auth" "$result"
pass "OpenCode collector keeps open windows while waiting for auth"

[[ $(jq -r '.probe.url' <<<"$result") == "https://example.invalid/zen/go/v1/usage" ]] ||
  fail "OpenCode probe hits the official usage path" "$result"
pass "OpenCode probe hits the official usage path"

[[ $(jq -r '.probe.auth + ":" + .probe.accept + ":" + .probe.ua' <<<"$result") == "Bearer sk_probe:application/json:omarchy-agent-usage/1" ]] ||
  fail "OpenCode probe sends the bearer, accept, and user-agent headers" "$result"
pass "OpenCode probe sends the bearer, accept, and user-agent headers"

[[ $(jq -r '.probe.payloadIsLive' <<<"$result") == "true" ]] ||
  fail "OpenCode probe decodes the deployed response shape" "$result"
pass "OpenCode probe decodes the deployed response shape"

{ [[ $(jq -r '.probe401' <<<"$result") == "GoUsageError:OpenCode Go rejected the API key:auth" ]] &&
  [[ $(jq -r '.probe403' <<<"$result") == "GoUsageError:OpenCode Go rejected the API key:auth" ]] &&
  [[ $(jq -r '.probe500' <<<"$result") == "GoUsageError:OpenCode's usage endpoint returned status 500" ]] &&
  [[ $(jq -r '.probeOffline' <<<"$result") == "GoUsageError:Could not reach OpenCode's usage endpoint:transport" ]]; } ||
  fail "OpenCode probe maps rejected keys, status errors, and transport failures distinctly" "$result"
pass "OpenCode probe maps rejected keys, status errors, and transport failures distinctly"
