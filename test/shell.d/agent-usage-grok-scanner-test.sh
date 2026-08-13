#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# Without credentials or sessions the collector must still print a full
# record: the update runner writes whatever valid JSON appears on stdout.
no_data=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + .usageStatusText' <<<"$no_data") == "grok:false:Waiting for auth" ]] ||
  fail "Grok collector prints a valid record without credentials" "$no_data"
pass "Grok collector prints a valid record without credentials"

session="$TEST_HOME/.grok/sessions/%2Ftmp%2Fproject/session-1"
mkdir -p "$session"
cat >"$session/summary.json" <<'EOF'
{"info":{"id":"session-1","cwd":"/tmp/project"},"created_at":"2026-08-13T10:00:00Z","updated_at":"2026-08-13T12:00:00Z"}
EOF

# turn_completed usage is per-turn, not a running session total. Summing the
# last value alone would drop the first turn's 100 tokens.
python3 - "$session/updates.jsonl" <<'PY'
import json
import sys
import time
from pathlib import Path

now = int(time.time())
path = Path(sys.argv[1])

def event(usage):
  return {
    "timestamp": now,
    "method": "session/update",
    "params": {"update": {"sessionUpdate": "turn_completed", "usage": usage}},
  }

def usage(input_tokens, output_tokens, cache_read, cache_write, model):
  bucket = {
    "inputTokens": input_tokens,
    "outputTokens": output_tokens,
    "cachedReadTokens": cache_read,
    "cacheCreationTokens": cache_write,
  }
  return {**bucket, "modelUsage": {model: bucket}}

lines = [
  json.dumps({"timestamp": now, "params": {"update": {"sessionUpdate": "agent_message_chunk"}}}),
  "not-json",
  json.dumps(event(usage(80, 20, 10, 5, "grok-4.6-build"))),
  json.dumps(event(usage(40, 10, 0, 0, "grok-4.6-build"))),
]
path.write_text("\n".join(lines) + "\n")
PY

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "165" ]] ||
  fail "Grok collector sums each turn_completed once" "$result"
pass "Grok collector sums each turn_completed once"

[[ $(jq -c '.modelUsage["grok-4.6-build"]' <<<"$result") == '{"cacheCreationInputTokens":5,"cacheReadInputTokens":10,"inputTokens":120,"outputTokens":30}' ]] ||
  fail "Grok collector keeps mutually exclusive token categories" "$result"
pass "Grok collector keeps mutually exclusive token categories"

[[ $(jq -r '(.todayPrompts|tostring) + "/" + (.todaySessions|tostring) + "/" + (.totalSessions|tostring)' <<<"$result") == "2/1/1" ]] ||
  fail "Grok collector counts prompts and sessions from turn events" "$result"
pass "Grok collector counts prompts and sessions from turn events"

# A session with only summary.json still happened.
idle="$TEST_HOME/.grok/sessions/%2Ftmp%2Fother/session-idle"
mkdir -p "$idle"
cat >"$idle/summary.json" <<EOF
{"info":{"id":"session-idle"},"created_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","updated_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.totalSessions' <<<"$result") == "2" ]] ||
  fail "Grok collector counts sessions that have no usage events" "$result"
pass "Grok collector counts sessions that have no usage events"

# Billing figures reshape into the shared monthly-limit and prepaid-balance
# contract. Import the collector so the HTTP client can be stubbed.
probe=$(python3 - "$ROOT/bin/omarchy-agent-usage-grok" "$TEST_HOME" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import sys
import time
from pathlib import Path

collector_path = sys.argv[1]
home = Path(sys.argv[2])
os.environ["HOME"] = str(home)
os.environ["XDG_CACHE_HOME"] = str(home / ".cache")
os.environ["GROK_HOME"] = str(home / ".grok")

loader = importlib.machinery.SourceFileLoader("grok_collector", collector_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)

(home / ".grok").mkdir(parents=True, exist_ok=True)
(home / ".grok" / "auth.json").write_text(json.dumps({
  "https://auth.x.ai::client": {
    "key": "tok_test",
    "expires_at": "2099-01-01T00:00:00Z",
    "auth_mode": "oidc",
  }
}))

calls = []

def fake_request(url, access_token):
  calls.append(url)
  if url.endswith("/billing"):
    return {"ok": True, "payload": {"config": {
      "monthlyLimit": {"val": 20},
      "used": {"val": 5},
      "onDemandCap": {"val": 10},
      "onDemandUsed": {"val": 2.5},
      "prepaidBalance": {"val": 12.5},
      "funded": {"val": 20},
      "billingPeriodEnd": "2026-09-01T00:00:00+00:00",
    }}}
  if url.endswith("/settings"):
    return {"ok": True, "payload": {"subscription_tier_display": "SuperGrok"}}
  return {"ok": False, "helpText": "unexpected " + url}

scanner.request_json = fake_request
record = scanner.collect_limits("tok_test", time.time() + 3600, True)
login_token, expires = scanner.oauth_login(home / ".grok")

# A zero monthly allowance is a SuperGrok-style subscription, not a meter.
empty = scanner.parse_billing({"config": {"monthlyLimit": {"val": 0}, "used": {"val": 0}}})

print(json.dumps({
  "monthly": record["limits"][0],
  "onDemand": record["limits"][1],
  "balance": record["balance"],
  "plan": record["tierLabel"],
  "tokenOk": login_token == "tok_test" and expires > 0,
  "emptyLimits": empty["limits"],
  "probedBilling": any(url.endswith("/billing") for url in calls),
  "probedSettings": any(url.endswith("/settings") for url in calls),
}, separators=(",", ":")))
PY
)

[[ $(jq -r '.monthly.label + "/" + (.monthly.percent|tostring) + "/" + .monthly.resetsAt' <<<"$probe") == "Monthly/0.25/2026-09-01T00:00:00+00:00" ]] ||
  fail "Grok collector maps prepaid monthly credit onto a Monthly limit" "$probe"
pass "Grok collector maps prepaid monthly credit onto a Monthly limit"

[[ $(jq -r '.onDemand.label + "/" + (.onDemand.percent|tostring)' <<<"$probe") == "On-demand/0.25" ]] ||
  fail "Grok collector maps the on-demand cap when one is configured" "$probe"
pass "Grok collector maps the on-demand cap when one is configured"

[[ $(jq -r '(.balance.remaining == 12.5 and .balance.funded == 20 and .balance.spent == 7.5 and .balance.currency == "USD" and .balance.estimated == false) | tostring' <<<"$probe") == "true" ]] ||
  fail "Grok collector reports a live prepaid balance" "$probe"
pass "Grok collector reports a live prepaid balance"

[[ $(jq -r '.plan + "/" + (.tokenOk|tostring) + "/" + (.emptyLimits|tostring)' <<<"$probe") == "SuperGrok/true/[]" ]] ||
  fail "Grok collector reads the plan label and ignores a zero monthly allowance" "$probe"
pass "Grok collector reads the plan label and ignores a zero monthly allowance"

# An expired token must not hit the network; local stats still print.
expired=$(python3 - "$ROOT/bin/omarchy-agent-usage-grok" "$TEST_HOME" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import sys
from pathlib import Path

loader = importlib.machinery.SourceFileLoader("grok_collector", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)
os.environ["XDG_CACHE_HOME"] = str(Path(sys.argv[2]) / ".cache")

called = []
scanner.request_json = lambda url, token: called.append(url) or {"ok": True, "payload": {}}
result = scanner.collect_limits("tok_old", 1, True)
print(json.dumps({"status": result["usageStatusText"], "called": called}, separators=(",", ":")))
PY
)

[[ $(jq -r '.status + "/" + (.called|tostring)' <<<"$expired") == "Waiting for auth/[]" ]] ||
  fail "Grok collector skips billing when the saved login has expired" "$expired"
pass "Grok collector skips billing when the saved login has expired"

# --limits-only must reuse a fresh session scan instead of walking jsonl again.
# Stamp the cache after a first force run, then mutate the transcript: the
# cheap path has to keep the original total.
first=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
echo '{"timestamp":1,"params":{"update":{"sessionUpdate":"turn_completed","usage":{"inputTokens":9999,"outputTokens":1,"modelUsage":{"grok-4.6-build":{"inputTokens":9999,"outputTokens":1}}}}}}' >>"$session/updates.jsonl"
cached=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$first") == "$(jq -r '.todayTotalTokens' <<<"$cached")" ]] ||
  fail "Grok collector --limits-only reuses the session scan cache" "$cached"
pass "Grok collector --limits-only reuses the session scan cache"
