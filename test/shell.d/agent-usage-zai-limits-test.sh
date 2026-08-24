#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

# fetch_limits/collect_limits reach Z.ai, so the readers that interpret the
# response are exercised on their own: the collector loads as a module and a
# recorded payload (or a raised error) stands in for the network.
CACHE_HOME=$(mktemp -d)
trap 'rm -rf "$CACHE_HOME"' EXIT

read_limits() {
  COLLECTOR="$ROOT/bin/omarchy-agent-usage-zai" PAYLOAD="$1" python3 - <<'PY'
import importlib.machinery, importlib.util, io, json, os

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

collector.urllib.request.urlopen = lambda request, timeout=None: io.BytesIO(os.environ["PAYLOAD"].encode())
print(json.dumps(collector.fetch_limits("token", "zai")))
PY
}

# force, cached-json, mode (success|transport|http401), payload -> {result, probes, cached}
drive() {
  COLLECTOR="$ROOT/bin/omarchy-agent-usage-zai" FORCE="$1" CACHED="$2" MODE="$3" PAYLOAD="$4" \
    XDG_CACHE_HOME="$CACHE_HOME" python3 - <<'PY'
import importlib.machinery, importlib.util, io, json, os, urllib.error

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

cache = collector.cache_root() / "zai-limits.json"
cached = os.environ["CACHED"]
if cached:
  cache.write_text(cached, encoding="utf-8")
elif cache.exists():
  cache.unlink()

probes = []
mode = os.environ["MODE"]

def urlopen(request, timeout=None):
  probes.append(1)
  if mode == "transport":
    raise urllib.error.URLError("no route to host")
  if mode == "http401":
    raise urllib.error.HTTPError("u", 401, "no", {}, None)
  return io.BytesIO(os.environ["PAYLOAD"].encode())

collector.urllib.request.urlopen = urlopen
result = collector.collect_limits("token", "zai", os.environ["FORCE"] == "true")
out = {"result": result, "probes": len(probes)}
if cache.exists():
  out["cached"] = json.loads(cache.read_text(encoding="utf-8"))
print(json.dumps(out))
PY
}

soon_ms=$(python3 -c 'import time; print(round((time.time() + 3*3600) * 1000))')
week_sec=$(python3 -c 'import time; print(round(time.time() + 5*86400))')
week_date=$(python3 -c "import datetime; print(datetime.datetime.fromtimestamp($week_sec, datetime.timezone.utc).date().isoformat())")
open_at=$(python3 -c 'import datetime as dt; print((dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=3)).isoformat())')
past_at=$(python3 -c 'import datetime as dt; print((dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=3)).isoformat())')

# The mapped session + weekly windows, then the entries that must drop: a window
# tagged with an unmapped (unit, number) and one whose percentage will not parse.
# nextResetTime is milliseconds for the first and plain seconds for the second,
# to prove a seconds epoch is not rendered 1000x in the future.
payload=$(jq -nc --argjson sm "$soon_ms" --argjson ws "$week_sec" '{
  data: { level: "pro", limits: [
    { type: "CREDIT_LIMIT", unit: 3, number: 5, percentage: 42.0, nextResetTime: $sm },
    { type: "TOKENS_LIMIT", unit: 6, number: 1, percentage: 10, nextResetTime: $ws },
    { type: "CREDIT_LIMIT", unit: 9, number: 9, percentage: 5, nextResetTime: $sm },
    { type: "CREDIT_LIMIT", unit: 3, number: 5, percentage: null, nextResetTime: $sm }
  ] }
}')
limits=$(read_limits "$payload")

[[ $(jq -c '[.limits[] | {label, percent}]' <<<"$limits") == '[{"label":"Session (5-hour)","percent":0.42},{"label":"Weekly (7-day)","percent":0.1}]' ]] ||
  fail "Z.ai collector maps both windows and drops the unmapped and unparseable rows" "$limits"
[[ $(jq -r '.tierLabel' <<<"$limits") == "Pro" ]] ||
  fail "Z.ai collector titles the plan tier" "$limits"
[[ $(jq -r '.limits[1].resetsAt' <<<"$limits") == "$week_date"* ]] ||
  fail "Z.ai collector reads a plain-seconds reset time, not milliseconds" "$limits"
pass "Z.ai collector reads windows, tier, seconds/ms resets, and drops bad rows"

# A key with no plan explains the empty section without blaming the key.
noplan=$(drive false "" success '{"success":false,"msg":"This API key has no coding plan"}')
[[ $(jq -r '.result.usageStatusText' <<<"$noplan") == "No GLM Coding Plan on this key" ]] ||
  fail "Z.ai collector reports a key without a coding plan" "$noplan"
[[ $(jq -r '.result.authHelpText' <<<"$noplan") == "" && $(jq -r '.result.retryAdvised' <<<"$noplan") == "false" ]] ||
  fail "Z.ai collector does not tell a working key to set a key" "$noplan"
pass "Z.ai collector reports a no-plan key without blaming it"

# A rejected key is the one case that should point back at the key.
rejected=$(drive false "" http401 "")
[[ $(jq -r '.result.authHelpText' <<<"$rejected") == *"rejected the saved API key"* ]] ||
  fail "Z.ai collector blames the key only when the key is rejected" "$rejected"
pass "Z.ai collector points at the key only on a 401"

# A transport failure with an open cached window keeps the last known figures,
# drops the window that already reset, and asks the shell to retry sooner.
cache=$(jq -nc --arg open "$open_at" --arg past "$past_at" '{
  fetchedAtMs: 1, tierLabel: "Pro", limits: [
    { label: "Session (5-hour)", percent: 0.31, resetsAt: $past },
    { label: "Weekly (7-day)", percent: 0.11, resetsAt: $open }
  ]
}')
unreachable=$(drive false "$cache" transport "")
[[ $(jq -c '[.result.limits[].label]' <<<"$unreachable") == '["Weekly (7-day)"]' ]] ||
  fail "Z.ai collector keeps only cached windows that have not reset" "$unreachable"
[[ $(jq -r '.result.tierLabel' <<<"$unreachable") == "Pro" && $(jq -r '.result.retryAdvised' <<<"$unreachable") == "true" ]] ||
  fail "Z.ai collector keeps the cached tier and advises a retry after a transport failure" "$unreachable"
pass "Z.ai collector serves the last known limits and advises a retry when offline"

# Repeated panel opens inside the probe interval share one answer; --force does not.
fresh=$(jq -nc --arg open "$open_at" --argjson now "$(python3 -c 'import time; print(round(time.time() * 1000))')" '{
  fetchedAtMs: $now, tierLabel: "Pro", limits: [{ label: "Weekly (7-day)", percent: 0.11, resetsAt: $open }]
}')
success_payload=$(jq -nc --argjson sm "$soon_ms" '{ data: { level: "max", limits: [
  { type: "CREDIT_LIMIT", unit: 3, number: 5, percentage: 44.0, nextResetTime: $sm }
] } }')

reused=$(drive false "$fresh" success "$success_payload")
[[ $(jq -r '.probes' <<<"$reused") == "0" && $(jq -c '[.result.limits[].percent]' <<<"$reused") == "[0.11]" ]] ||
  fail "Z.ai collector reuses a cache younger than the probe interval" "$reused"
pass "Z.ai collector reuses a probe younger than the interval"

forced=$(drive true "$fresh" success "$success_payload")
[[ $(jq -r '.probes' <<<"$forced") == "1" && $(jq -c '[.result.limits[].percent]' <<<"$forced") == "[0.44]" ]] ||
  fail "Z.ai collector re-probes on --force despite a fresh cache" "$forced"
[[ $(jq -c '[.cached.limits[].percent]' <<<"$forced") == "[0.44]" && $(jq -r '.cached.tierLabel' <<<"$forced") == "Max" ]] ||
  fail "Z.ai collector caches a successful probe for the next run" "$forced"
pass "Z.ai collector re-probes on --force and caches the result"
