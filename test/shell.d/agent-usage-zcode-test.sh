#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

# The collector reads nothing but $HOME-relative paths and its cache root, so
# a planted home is a complete ZCode install for its purposes.
TEST_HOME=$(mktemp -d)
PROBE_CACHES=("$TEST_HOME/probe-cache-empty")
trap 'rm -rf "$TEST_HOME" "${PROBE_CACHES[@]}"' EXIT
export XDG_CACHE_HOME="$TEST_HOME/.cache"

python3 - "$TEST_HOME/.zcode/cli/db/db.sqlite" <<'PY'
import sqlite3
import sys
import time
from pathlib import Path

db = Path(sys.argv[1])
db.parent.mkdir(parents=True, exist_ok=True)
now_ms = int(time.time() * 1000)

conn = sqlite3.connect(db)
conn.execute("""CREATE TABLE model_usage (
  session_id text,
  model_id text,
  started_at integer,
  input_tokens integer,
  output_tokens integer,
  cache_read_input_tokens integer,
  cache_creation_input_tokens integer
)""")
conn.execute("""CREATE TABLE turn_usage (
  session_id text,
  turn_id text,
  started_at integer
)""")
conn.executemany("INSERT INTO model_usage VALUES (?, ?, ?, ?, ?, ?, ?)", [
  # Today, two requests on one model whose input_tokens carry a large cached
  # portion: (100 input incl. 30 cache-read, 10 cache-write) and (50 incl. 5).
  ("ses_1", "GLM-5.2", now_ms, 100, 20, 30, 10),
  ("ses_1", "GLM-5.2", now_ms, 50, 10, 5, 0),
  # Well before the week window: history for the all-time totals only.
  ("ses_0", "GLM-4.7", now_ms - 30 * 24 * 3600 * 1000, 999, 999, 0, 0),
])
conn.executemany("INSERT INTO turn_usage VALUES (?, ?, ?)", [
  ("ses_1", "turn_1", now_ms),
  ("ses_1", "turn_2", now_ms),
  ("ses_2", "turn_3", now_ms - 36 * 3600 * 1000),
])
conn.commit()
conn.close()
PY

result=$(HOME="$TEST_HOME" "$ROOT/bin/omarchy-agent-usage-zcode" 2>/dev/null)

# ZCode's input_tokens contains the cached portion of the prompt, so the day
# chart counts input + output and the model split ships input cache-free —
# every token once, the way the subscription page counts.
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "180" ]] ||
  fail "ZCode collector counts each token once per day" "$result"
pass "ZCode collector counts each token once per day"

[[ $(jq -c '.todayTokensByModel' <<<"$result") == '{"GLM-5.2":180}' ]] ||
  fail "ZCode collector groups today's tokens by model" "$result"
pass "ZCode collector groups today's tokens by model"

[[ $(jq -c '.modelUsage["GLM-5.2"]' <<<"$result") == '{"inputTokens":105,"outputTokens":30,"cacheReadInputTokens":35,"cacheCreationInputTokens":10}' ]] ||
  fail "ZCode collector splits usage with input cache-free" "$result"
pass "ZCode collector splits usage with input cache-free"

[[ $(jq -c '.modelUsage | keys' <<<"$result") == '["GLM-4.7","GLM-5.2"]' ]] ||
  fail "ZCode collector keeps models outside the week in the all-time totals" "$result"
pass "ZCode collector keeps models outside the week in the all-time totals"

[[ $(jq '.recentDays | length' <<<"$result") == "7" ]] ||
  fail "ZCode collector always reports a full week of days" "$result"
pass "ZCode collector always reports a full week of days"

[[ $(jq -r '[.recentDays[].messageCount] | add' <<<"$result") == "180" ]] ||
  fail "ZCode collector leaves the week window outside the day chart" "$result"
pass "ZCode collector leaves the week window outside the day chart"

[[ $(jq -r '.todayPrompts == 2 and .todaySessions == 1 and .totalPrompts == 3 and .totalSessions == 2 and .activeDays == 2' <<<"$result") == "true" ]] ||
  fail "ZCode collector counts turns as prompts and distinct sessions" "$result"
pass "ZCode collector counts turns as prompts and distinct sessions"

[[ $(jq -r '.id + "/" + .tierLabel + "/" + .usageStatusText' <<<"$result") == "zcode//Waiting for sign-in" ]] ||
  fail "ZCode collector identifies itself and asks for a sign-in without one" "$result"
pass "ZCode collector identifies itself and asks for a sign-in without one"

# The quota endpoint is Z.ai's, so its answer is interpreted on its own: a
# recorded payload through the collector loaded as a module.
read_quota() {
  COLLECTOR="$ROOT/bin/omarchy-agent-usage-zcode" LIMITS="$1" python3 - <<'PY'
import importlib.machinery, importlib.util, json, os

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

limits = json.loads(os.environ["LIMITS"])
print(json.dumps({"limits": collector.map_limits({"limits": limits}), "tier": collector.tier_label("pro")}))
PY
}

# A whole-second timestamp keeps the mapped ISO string fraction-free.
future_ms=$(( ( $(date +%s) + 3600 ) * 1000 ))
limits=$(read_quota "[
    {\"type\": \"TIME_LIMIT\", \"unit\": 5, \"number\": 1, \"usage\": 1000, \"currentValue\": 13, \"remaining\": 987, \"percentage\": 1, \"nextResetTime\": $future_ms, \"usageDetails\": [{\"modelCode\": \"search-prime\", \"usage\": 13}]},
    {\"type\": \"TOKENS_LIMIT\", \"unit\": 9, \"percentage\": 17, \"nextResetTime\": $future_ms},
    {\"type\": \"TOKENS_LIMIT\", \"unit\": 3, \"number\": 5, \"percentage\": 8, \"nextResetTime\": $future_ms},
    {\"type\": \"SOMETHING_ELSE\", \"percentage\": 50, \"nextResetTime\": $future_ms},
    {\"type\": \"TOKENS_LIMIT\", \"unit\": 6, \"percentage\": 42, \"nextResetTime\": $future_ms},
    {\"type\": \"TOKENS_LIMIT\", \"percentage\": \"unknown\"}
  ]")

reset_iso="$(date -u -d "@$(( future_ms / 1000 ))" +%Y-%m-%dT%H:%M:%S)+00:00"
expected=$(jq -cn --arg reset "$reset_iso" '{limits: [
    {label: "Session (5-hour)", title: "Session", percent: 0.08, resetsAt: $reset},
    {label: "Weekly", title: "Weekly", percent: 0.42, resetsAt: $reset},
    {label: "Tools (monthly)", title: "Tools", percent: 0.01, resetsAt: $reset},
    {label: "Prompts", title: "Prompts", percent: 0.17, resetsAt: $reset}
  ], tier: "GLM Coding Pro"}')
[[ $(jq -c '.' <<<"$limits") == "$expected" ]] ||
  fail "ZCode collector reads the payload's three windows in the app's order and vocabulary" "$limits"
pass "ZCode collector reads the payload's three windows in the app's order and vocabulary"

# The tool quota falls back to its per-mille fields when the payload carries
# no percentage.
per_mille=$(read_quota "[{\"type\": \"TIME_LIMIT\", \"unit\": 5, \"number\": 1, \"currentValue\": 13, \"remaining\": 987, \"nextResetTime\": $future_ms}]")

[[ $(jq -c '[.limits[].percent]' <<<"$per_mille") == "[0.013]" ]] ||
  fail "ZCode collector reads the tool quota's per-mille fields without a percentage" "$per_mille"
pass "ZCode collector reads the tool quota's per-mille fields without a percentage"

# A probe that cannot reach Z.ai keeps serving the last reading whose window
# has not reset, and only advises a retry once nothing usable is left. Each
# probe plants its own cache root so one answer cannot leak into the next.
probe_unreachable() {
  local cache_home
  cache_home=$(mktemp -d)
  PROBE_CACHES+=("$cache_home")

  XDG_CACHE_HOME="$cache_home" COLLECTOR="$ROOT/bin/omarchy-agent-usage-zcode" CACHE_PAYLOAD="$1" python3 - <<'PY'
import importlib.machinery, importlib.util, json, os, time, urllib.error

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

def unreachable(request, timeout=None):
  raise urllib.error.URLError("network is down")

collector.urllib.request.urlopen = unreachable
if os.environ["CACHE_PAYLOAD"]:
  future_ms = (int(time.time()) + 3600) * 1000
  payload = json.loads(os.environ["CACHE_PAYLOAD"].replace("@FUTURE@", str(future_ms)))
  collector.write_json(collector.cache_root() / "zcode-quota.json", {"fetchedAtMs": 0, "payload": payload})
print(json.dumps(collector.collect_limits("key", "https://z.ai/api/monitor/usage/quota/limit", True)))
PY
}

open_payload='{"code":200,"data":{"level":"pro","limits":[{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":8,"nextResetTime":@FUTURE@}]}}'
[[ $(probe_unreachable "$open_payload" | jq -r '.limits[0].title + "/" + (.retryAdvised // "none")') == "Session/none" ]] ||
  fail "ZCode collector keeps a cached reading whose window is still open" "$(probe_unreachable "$open_payload")"
pass "ZCode collector keeps a cached reading whose window is still open"

[[ $(probe_unreachable "" | jq -r '.usageStatusText + "/" + (.retryAdvised|tostring)') == "ZCode limits unavailable/true" ]] ||
  fail "ZCode collector flags a dead probe for the panel's early retry" "$(probe_unreachable "")"
pass "ZCode collector flags a dead probe for the panel's early retry"

# The key and endpoint come from the app's own config, with the base URL
# derived from whatever Anthropic endpoint the plan uses.
CONFIG_HOME=$(mktemp -d)
PROBE_CACHES+=("$CONFIG_HOME")
mkdir -p "$CONFIG_HOME/.zcode/v2"
cat >"$CONFIG_HOME/.zcode/v2/config.json" <<'EOF'
{
  "provider": {
    "builtin:bigmodel-coding-plan": {
      "name": "BigModel - Coding Plan",
      "options": {"apiKey": "", "baseURL": "https://open.bigmodel.cn/api/anthropic"}
    },
    "builtin:zai-coding-plan": {
      "name": "Z.ai - Coding Plan",
      "options": {"apiKey": "Bearer sk-test-key", "baseURL": "https://api.z.ai/api/anthropic"}
    }
  }
}
EOF

credentials=$(HOME="$CONFIG_HOME" COLLECTOR="$ROOT/bin/omarchy-agent-usage-zcode" python3 - <<'PY'
import importlib.machinery, importlib.util, json, os

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)
print(json.dumps(collector.resolve_credentials()))
PY
)

[[ $(jq -r '.[0]' <<<"$credentials") == "sk-test-key" ]] ||
  fail "ZCode collector reads the Z.ai coding-plan key and strips its scheme" "$credentials"
pass "ZCode collector reads the Z.ai coding-plan key and strips its scheme"

[[ $(jq -r '.[1]' <<<"$credentials") == "https://api.z.ai/api/monitor/usage/quota/limit" ]] ||
  fail "ZCode collector derives the quota endpoint from the plan's base URL" "$credentials"
pass "ZCode collector derives the quota endpoint from the plan's base URL"
