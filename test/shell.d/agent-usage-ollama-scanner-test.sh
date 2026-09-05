#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# Without credentials the collector must still print a full, hidden-by-default
# record: the update runner writes whatever valid JSON appears on stdout.
no_key=$(HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" XDG_CACHE_HOME="$TEST_HOME/.cache" \
  OLLAMA_API_KEY="" "$ROOT/bin/omarchy-agent-usage-ollama" --force)

[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + .usageStatusText' <<<"$no_key") == "ollama:false:Waiting for auth" ]] ||
  fail "Ollama collector prints a valid record without credentials" "$no_key"
pass "Ollama collector prints a valid record without credentials"

# Pi and omp sessions on the ollama-cloud provider are the local stats; other
# providers in the same files must not leak in, and model version tags merge.
PI_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$PI_HOME"' EXIT
mkdir -p "$PI_HOME/.pi/agent/sessions/project" "$PI_HOME/.omp/agent/sessions/project"

timestamp="$(date +%Y-%m-%d)T12:00:00Z"
cat >"$PI_HOME/.pi/agent/sessions/project/pi.jsonl" <<EOF
{"type":"message","id":"pi-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"ollama-cloud","model":"deepseek-v4-pro:0813","usage":{"input":10,"output":4,"cacheRead":3,"cacheWrite":2,"totalTokens":19}}}
{"type":"message","id":"pi-2","timestamp":"$timestamp","message":{"role":"assistant","provider":"ollama-cloud","model":"deepseek-v4-pro:0731","usage":{"input":5,"output":1,"cacheRead":0,"cacheWrite":0,"totalTokens":6}}}
{"type":"message","id":"pi-3","timestamp":"$timestamp","message":{"role":"assistant","provider":"anthropic","model":"claude-test","usage":{"input":999,"output":999}}}
{"type":"message","id":"pi-4","timestamp":"$timestamp","message":{"role":"user","provider":"ollama-cloud","model":"deepseek-v4-pro:0813","usage":{"input":999,"output":999}}}
{"type":"message","id":"pi-5","timestamp":"$timestamp","message":{"role":"assistant","provider":"ollama-cloud","model":"deepseek-v4-pro:0813","usage":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"totalTokens":0}}}
EOF
cat >"$PI_HOME/.omp/agent/sessions/project/omp.jsonl" <<EOF
{ "type": "message", "id": "omp-1", "timestamp": "$timestamp", "message": { "role": "assistant", "provider": "ollama-cloud", "model": "kimi-k3", "usage": { "input": 20, "output": 5, "cacheRead": 4, "cacheWrite": 1, "totalTokens": 30 } } }
EOF

result=$(HOME="$PI_HOME" XDG_CONFIG_HOME="$PI_HOME/.config" XDG_CACHE_HOME="$PI_HOME/.cache" \
  OLLAMA_API_KEY="" "$ROOT/bin/omarchy-agent-usage-ollama" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "55" ]] ||
  fail "Ollama collector counts usage from pi and omp sessions" "$result"
pass "Ollama collector counts usage from pi and omp sessions"

[[ $(jq -c '.modelUsage' <<<"$result") == '{"deepseek-v4-pro":{"cacheCreationInputTokens":2,"cacheReadInputTokens":3,"inputTokens":15,"outputTokens":5},"kimi-k3":{"cacheCreationInputTokens":1,"cacheReadInputTokens":4,"inputTokens":20,"outputTokens":5}}' ]] ||
  fail "Ollama collector filters to the ollama-cloud provider and merges model tags" "$result"
pass "Ollama collector filters to the ollama-cloud provider and merges model tags"

# A configured model prefix restricts the local stats to matching models.
mkdir -p "$PI_HOME/.config/omarchy/agents"
cat >"$PI_HOME/.config/omarchy/agents/ollama.json" <<'EOF'
{ "modelPrefix": "kimi" }
EOF

result=$(HOME="$PI_HOME" XDG_CONFIG_HOME="$PI_HOME/.config" XDG_CACHE_HOME="$PI_HOME/.cache" \
  OLLAMA_API_KEY="" "$ROOT/bin/omarchy-agent-usage-ollama" --force)

[[ $(jq -c '.modelUsage' <<<"$result") == '{"kimi-k3":{"cacheCreationInputTokens":1,"cacheReadInputTokens":4,"inputTokens":20,"outputTokens":5}}' ]] ||
  fail "Ollama collector honors the configured model prefix" "$result"
pass "Ollama collector honors the configured model prefix"

# probe_limits reaches Ollama, so the reader that interprets its answer is
# exercised on its own: the collector loads as a module, and a recorded
# payload stands in for the response.
read_limits() {
  COLLECTOR="$ROOT/bin/omarchy-agent-usage-ollama" PAYLOAD="$1" python3 - <<'PY'
import importlib.machinery, importlib.util, io, json, os

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

collector.urllib.request.urlopen = lambda request, timeout=None: io.BytesIO(os.environ["PAYLOAD"].encode())

print(json.dumps(collector.probe_limits("key")))
PY
}

limits=$(read_limits '{
  "activity": { "cost": "0.00" },
  "limits": {
    "session": { "usage": 0.434, "models": [{ "name": "deepseek-v4-pro:0813", "request_count": 340 }] },
    "weekly": { "usage": 0.298, "models": [{ "name": "kimi-k3", "request_count": 377 }] }
  }
}')

[[ $(jq -c '[.limits[].label]' <<<"$limits") == '["Session (5-hour)","Weekly (7-day)"]' ]] ||
  fail "Ollama collector reads the session and weekly windows" "$limits"
[[ $(jq -c '[.limits[].percent]' <<<"$limits") == "[0.434,0.298]" ]] ||
  fail "Ollama collector keeps the endpoint's 0..1 fractions" "$limits"
pass "Ollama collector reads the session and weekly fractions"

# Reset times are computed, not fetched: session windows are epoch-aligned
# 5-hour blocks and weekly windows end Monday 00:00 UTC.
resets=$(python3 - "$ROOT/bin/omarchy-agent-usage-ollama" <<'PY'
import datetime as dt
import importlib.machinery, importlib.util, sys

loader = importlib.machinery.SourceFileLoader("collector", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

session = dt.datetime.fromisoformat(collector.reset_iso(collector.SESSION_WINDOW_SECONDS))
weekly = dt.datetime.fromisoformat(collector.reset_iso(collector.WEEKLY_WINDOW_SECONDS, collector.WEEKLY_EPOCH_OFFSET_SECONDS))
print(f"{session.timestamp() % collector.SESSION_WINDOW_SECONDS == 0}:{weekly.strftime('%A')}:{weekly.hour}:{weekly.minute}")
PY
)

[[ "$resets" == "True:Monday:0:0" ]] ||
  fail "Ollama collector computes epoch-aligned session and Monday-midnight weekly resets" "$resets"
pass "Ollama collector computes epoch-aligned session and Monday-midnight weekly resets"

# A payload with no usable windows explains itself instead of printing none.
empty=$(read_limits '{"limits": {"session": {"usage": "unknown"}, "weekly": null}}')
[[ $(jq -r '.ok' <<<"$empty") == "false" && $(jq -r '.helpText' <<<"$empty") == *"no limits"* ]] ||
  fail "Ollama collector reports a payload without usable limits" "$empty"
pass "Ollama collector reports a payload without usable limits"

# collect_limits drives the probe, the plan lookup, and the cache. A mocked
# urlopen answers both endpoints, and the cache decides reuse and fallback.
CACHE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$PI_HOME" "$CACHE_HOME"' EXIT

collect_limits() {
  COLLECTOR="$ROOT/bin/omarchy-agent-usage-ollama" FORCE="$1" CACHED="$2" MODE="$3" \
    XDG_CACHE_HOME="$CACHE_HOME" python3 - <<'PY'
import importlib.machinery, importlib.util, io, json, os

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

cache = collector.cache_root() / "ollama-limits.json"
cached = os.environ["CACHED"]
if cached:
  cache.write_text(cached, encoding="utf-8")
elif cache.exists():
  cache.unlink()

probes = []

def urlopen(request, timeout=None):
  probes.append(request.full_url)
  mode = os.environ["MODE"]
  if mode == "transport":
    raise OSError("no route to host")
  if mode == "rejected":
    raise collector.urllib.error.HTTPError(request.full_url, 401, "Unauthorized", {}, io.BytesIO(b""))
  if request.full_url.endswith("/api/me"):
    return io.BytesIO(b'{"Plan":"pro"}')
  return io.BytesIO(b'{"limits":{"session":{"usage":0.44},"weekly":{"usage":0.11}}}')

collector.urllib.request.urlopen = urlopen
result = collector.collect_limits("key", os.environ["FORCE"] == "true")
print(json.dumps({
  "result": result,
  "probes": probes,
  "cached": json.loads(cache.read_text(encoding="utf-8")) if cache.exists() else None,
}))
PY
}

fresh=$(jq -nc --argjson now "$(python3 -c 'import time; print(round(time.time() * 1000))')" '{
  fetchedAtMs: $now,
  limits: [{ label: "Weekly (7-day)", percent: 0.11, resetsAt: "" }],
  plan: "Pro"
}')
stale=$(jq -nc '{
  fetchedAtMs: 1,
  limits: [{ label: "Weekly (7-day)", percent: 0.11, resetsAt: "" }],
  plan: "Pro"
}')

# A live key that cannot reach the endpoint keeps the cached window and asks
# the shell to retry sooner than its regular interval.
unreachable=$(collect_limits false "$stale" transport)
[[ $(jq -c '[.result.limits[].label]' <<<"$unreachable") == '["Weekly (7-day)"]' ]] ||
  fail "Ollama collector falls back to cache when the probe cannot connect" "$unreachable"
[[ $(jq -r '.result.retryAdvised' <<<"$unreachable") == "true" ]] ||
  fail "Ollama collector advises a retry after a transport failure" "$unreachable"
pass "Ollama collector falls back to cache when the probe cannot connect"

# A rejected key says so instead of pretending the endpoint is down.
rejected=$(collect_limits false "" rejected)
[[ $(jq -r '.result.usageStatusText' <<<"$rejected") == "Ollama limits unavailable" ]] ||
  fail "Ollama collector reports a rejected key" "$rejected"
[[ $(jq -r '.result.authHelpText' <<<"$rejected") == *"rejected"* ]] ||
  fail "Ollama collector explains a rejected key" "$rejected"
pass "Ollama collector reports a rejected key"

# A fresh cache answers repeated panel opens without a request apiece.
reused=$(collect_limits false "$fresh" normal)
[[ $(jq -r '.probes | length' <<<"$reused") == "0" && $(jq -c '[.result.limits[].percent]' <<<"$reused") == "[0.11]" ]] ||
  fail "Ollama collector reuses a cache younger than the probe interval" "$reused"
pass "Ollama collector reuses a cache younger than the probe interval"

# --force is someone pressing refresh, so the reuse window must not outrank it.
forced=$(collect_limits true "$fresh" normal)
[[ $(jq -r '.probes | length' <<<"$forced") == "2" ]] ||
  fail "Ollama collector re-probes limits and plan on --force despite a fresh cache" "$forced"
[[ $(jq -c '[.result.limits[].percent]' <<<"$forced") == "[0.44,0.11]" && $(jq -r '.result.tierLabel' <<<"$forced") == "Pro" ]] ||
  fail "Ollama collector returns the forced probe's numbers and plan" "$forced"
pass "Ollama collector re-probes on --force despite a fresh cache"

# A probe that lands becomes the next run's fallback.
[[ $(jq -c '[.cached.limits[].percent]' <<<"$forced") == "[0.44,0.11]" && $(jq -r '.cached.plan' <<<"$forced") == "Pro" ]] ||
  fail "Ollama collector caches a successful probe" "$forced"
pass "Ollama collector caches a successful probe"
