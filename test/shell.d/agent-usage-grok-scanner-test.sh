#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

today="$(date +%Y-%m-%d)"
timestamp="${today}T12:00:00Z"
# Synthetic UUIDv7-shaped id. turn_line reads $session_id, which later tests
# overwrite, so paths that must stay on the fixture use this name.
fixture_session_id="019fb000-0000-7000-8000-000000000001"
session_id="$fixture_session_id"
session_dir="$TEST_HOME/.grok/sessions/%2Ftmp%2Fproj/$fixture_session_id"
mkdir -p "$session_dir"

write_summary() {
  local dir="$1" kind="${2:-}" parent="${3:-}"
  python3 - "$dir" "$kind" "$parent" "$today" <<'PY'
import json, sys
from pathlib import Path
directory, kind, parent, today = sys.argv[1:]
payload = {
  "info": {"id": Path(directory).name, "cwd": "/tmp/proj"},
  "created_at": f"{today}T12:00:00Z",
  "updated_at": f"{today}T12:30:00Z",
  "current_model_id": "grok-4.6",
}
if kind:
  payload["session_kind"] = kind
if parent:
  payload["parent_session_id"] = parent
Path(directory, "summary.json").write_text(json.dumps(payload) + "\n")
PY
}

turn_line() {
  local prompt="$1" model="$2" input="$3" output="$4" cache="$5" reasoning="$6" cache_write="${7:-0}"
  jq -nc --arg ts "$timestamp" --arg sid "$session_id" --arg prompt "$prompt" --arg model "$model" \
    --argjson input "$input" --argjson output "$output" --argjson cache "$cache" --argjson reasoning "$reasoning" \
    --argjson write "$cache_write" \
    '{
      timestamp: $ts,
      method: "session/update",
      params: {
        sessionId: $sid,
        update: {
          sessionUpdate: "turn_completed",
          prompt_id: $prompt,
          stop_reason: "end_turn",
          usage: {
            inputTokens: $input,
            outputTokens: $output,
            cachedReadTokens: $cache,
            cacheCreationTokens: $write,
            reasoningTokens: $reasoning,
            modelUsage: {
              ($model): {
                inputTokens: $input,
                outputTokens: $output,
                cachedReadTokens: $cache,
                cacheCreationTokens: $write,
                reasoningTokens: $reasoning
              }
            }
          }
        }
      }
    }'
}

write_summary "$session_dir"
{
  echo '{"method":"session/update","params":{"update":{"sessionUpdate":"agent_message_chunk"}}}'
  turn_line "prompt-1" "grok-4.6" 100 20 60 5
  turn_line "prompt-1" "grok-4.6" 100 20 60 5
  turn_line "prompt-2" "grok-4.6" 80 10 50 3
  echo '{not json'
  echo '{"method":"session/update","params":["turn_completed"]}'
  echo '{"method":"session/update","params":{"update":{"sessionUpdate":"turn_completed","usage":{"inputTokens":999}}}}'
} >"$session_dir/updates.jsonl"

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.id + "/" + .name' <<<"$result") == "grok/Grok Build" ]] ||
  fail "Grok collector identifies itself" "$result"
pass "Grok collector identifies itself"

# Full prompt 100 with 60 cached is 40 uncached; second turn 80/50 is 30.
# Reasoning sits inside output, so it is not added again. Duplicate prompt-1
# is ignored. The last line has no prompt_id and is counted once.
[[ $(jq -r '.todayPrompts' <<<"$result") == "3" ]] ||
  fail "Grok collector counts each turn once" "$result"
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "1209" ]] ||
  fail "Grok collector keeps uncached input, output, and cache disjoint" "$result"
[[ $(jq -c '.modelUsage["grok-4.6"]' <<<"$result") == '{"cacheCreationInputTokens":0,"cacheReadInputTokens":110,"inputTokens":70,"outputTokens":30}' ]] ||
  fail "Grok collector splits tokens by model without double-counting cache" "$result"
pass "Grok collector counts each turn once and keeps token buckets disjoint"

[[ $(jq -r '.todaySessions' <<<"$result") == "1" ]] ||
  fail "Grok collector counts the parent session once" "$result"
pass "Grok collector counts the parent session once"

# A child session writes its own updates.jsonl. Parent turn_completed already
# includes that spend, so the child file must not add another copy. Grok 1.0.x
# labels these "subagent"; older builds used "subagent_fork".
child_id="019fb000-0000-7000-8000-000000000004"
child_dir="$TEST_HOME/.grok/sessions/%2Ftmp%2Fproj/$child_id"
mkdir -p "$child_dir"
write_summary "$child_dir" "subagent" "$session_id"
session_id="$child_id" turn_line "child-1" "grok-4.6" 5000 500 4000 100 >"$child_dir/updates.jsonl"

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "1209" ]] ||
  fail "Grok collector ignores subagent sessions" "$result"
pass "Grok collector ignores subagent sessions"

fork_id="01a00057-c26d-7442-aa2a-8bb92c921e19"
fork_dir="$TEST_HOME/.grok/sessions/%2Ftmp%2Fproj/$fork_id"
mkdir -p "$fork_dir"
write_summary "$fork_dir" "subagent_fork" "$session_id"
session_id="$fork_id" turn_line "fork-1" "grok-4.6" 9000 900 8000 100 >"$fork_dir/updates.jsonl"

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "1209" ]] ||
  fail "Grok collector ignores subagent_fork sessions" "$result"
pass "Grok collector ignores subagent_fork sessions"

# GROK_HOME wins over ~/.grok under HOME.
OTHER_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OTHER_HOME"' EXIT
other_dir="$OTHER_HOME/sessions/%2Ftmp%2Fother/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
mkdir -p "$other_dir"
write_summary "$other_dir"
session_id="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" \
  turn_line "other-1" "grok-4.20" 10 4 0 0 >"$other_dir/updates.jsonl"

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$OTHER_HOME/.cache" GROK_HOME="$OTHER_HOME" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -c '.modelUsage' <<<"$result") == '{"grok-4.20":{"cacheCreationInputTokens":0,"cacheReadInputTokens":0,"inputTokens":10,"outputTokens":4}}' ]] ||
  fail "Grok collector honors GROK_HOME" "$result"
pass "Grok collector honors GROK_HOME"

# No credentials: local stats still print, and the record says how to sign in.
[[ $(jq -r '.usageStatusText' <<<"$result") == "Waiting for auth" ]] ||
  fail "Grok collector reports a missing login" "$result"
[[ $(jq -r '.authHelpText' <<<"$result") == *"grok login"* ]] ||
  fail "Grok collector says how to restore limits" "$result"
pass "Grok collector reports a missing login"

# pi/omp xAI sessions count; other providers do not. Added after the GROK_HOME
# check so HOME=$TEST_HOME cannot leak these rows into that assertion.
pi_dir="$TEST_HOME/.pi/agent/sessions/proj"
mkdir -p "$pi_dir"
now_ms=$(python3 -c 'import time; print(int(time.time() * 1000))')
cat >"$pi_dir/chat.jsonl" <<EOF
{"type":"message","id":"m1","timestamp":$now_ms,"message":{"role":"assistant","provider":"xai","model":"grok-4.6","usage":{"input":100,"output":20,"cacheRead":10,"cacheWrite":0,"reasoning":5}}}
{"type":"message","id":"m2","timestamp":$now_ms,"message":{"role":"assistant","provider":"anthropic","model":"claude","usage":{"input":999,"output":999}}}
{"type":"message","id":"m-user","timestamp":$now_ms,"message":{"role":"user","provider":"xai","model":"grok-4.6","usage":{"input":50,"output":1}}}
["usage","assistant"]
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.todayPrompts' <<<"$result") == "4" ]] ||
  fail "Grok collector counts pi xAI messages and ignores other providers" "$result"
# Native turns 1209 + pi (90 uncached + 20 output + 10 cache). Reasoning is
# already below output, so it is not added again.
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "1329" ]] ||
  fail "Grok collector merges pi xAI tokens without double-counting" "$result"
[[ $(jq -r '.todaySessions' <<<"$result") == "2" ]] ||
  fail "Grok collector counts the pi session separately" "$result"
pass "Grok collector counts pi xAI messages and ignores other providers"

# Billing and user probes are stubbed: the collector must not reach the network.
CACHE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OTHER_HOME" "$CACHE_HOME"' EXIT
mkdir -p "$CACHE_HOME/.grok/sessions/%2Ftmp%2Fproj/$session_id"
# Reuse the first session tree under a dedicated home so auth lives next to it.
cp -a "$session_dir" "$CACHE_HOME/.grok/sessions/%2Ftmp%2Fproj/"
mkdir -p "$CACHE_HOME/.grok"
python3 - "$CACHE_HOME/.grok/auth.json" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone
expires = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
payload = {
  "https://auth.x.ai::test": {
    "key": "test-token",
    "expires_at": expires,
    "auth_mode": "oidc",
  }
}
open(sys.argv[1], "w").write(json.dumps(payload))
PY

probe_record() {
  COLLECTOR="$ROOT/bin/omarchy-agent-usage-grok" HOME="$CACHE_HOME" \
    XDG_CACHE_HOME="$CACHE_HOME/.cache" GROK_HOME="$CACHE_HOME/.grok" python3 - "$@" <<'PY'
import importlib.machinery, importlib.util, io, json, os, sys, time

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

billing = json.loads(sys.argv[1])
user = json.loads(sys.argv[2])
force = sys.argv[3] == "force"
settings = json.loads(sys.argv[4]) if len(sys.argv) > 4 else {}
# Seconds from now for each banked reset's validity_end; a negative one has
# lapsed and must not be counted.
resets = json.loads(sys.argv[5]) if len(sys.argv) > 5 else []
seen = []


def varint(value):
  out = bytearray()
  while True:
    byte = value & 0x7F
    value >>= 7
    out.append(byte | (0x80 if value else 0))
    if not value:
      return bytes(out)


def tagged(number, payload):
  return varint(number << 3 | 2) + varint(len(payload)) + payload


def reset_tokens_body(offsets):
  """A grpc-web response carrying one ConsumerResetToken per offset."""
  message = b""
  for index, offset in enumerate(offsets):
    stamp = varint(collector.TIMESTAMP_SECONDS_FIELD << 3) + varint(int(time.time()) + offset)
    token = tagged(collector.RESET_TOKEN_ID_FIELD, f"token-{index}".encode())
    token += tagged(collector.RESET_TOKEN_END_FIELD, stamp)
    message += tagged(collector.RESET_TOKEN_FIELD, token)
  frame = bytes([0]) + len(message).to_bytes(4, "big") + message
  trailer = b"grpc-status:0\r\n"
  return frame + bytes([0x80]) + len(trailer).to_bytes(4, "big") + trailer

def urlopen(request, timeout=None):
  url = request.full_url
  seen.append(url)
  if url.endswith("billing?format=credits") or url.endswith("/billing?format=credits"):
    return io.BytesIO(json.dumps(billing).encode())
  if "user?include=subscription" in url:
    return io.BytesIO(json.dumps(user).encode())
  if url.endswith("/v1/settings") or url.endswith("/settings"):
    return io.BytesIO(json.dumps(settings).encode())
  if url.endswith("GetRemainingResets"):
    return io.BytesIO(reset_tokens_body(resets))
  raise AssertionError("unexpected url " + url)

collector.urllib.request.urlopen = urlopen
record = collector.build_record(force=force, limits_only=False)
record["_probed"] = seen
print(json.dumps(record))
PY
}

billing='{
  "config": {
    "currentPeriod": {
      "type": "USAGE_PERIOD_TYPE_WEEKLY",
      "start": "2026-08-08T14:46:02.562637+00:00",
      "end": "2026-08-15T14:46:02.562637+00:00"
    },
    "creditUsagePercent": 24.0,
    "onDemandCap": {"val": 10},
    "onDemandUsed": {"val": 2.5},
    "prepaidBalance": {"val": 5},
    "productUsage": [{"product": "GrokBuild", "usagePercent": 24.0}]
  }
}'
user='{"subscriptionTier":"SuperGrokPro","hasGrokCodeAccess":true}'

limits=$(probe_record "$billing" "$user" force)
[[ $(jq -r '.tierLabel' <<<"$limits") == "SuperGrok Pro" ]] ||
  fail "Grok collector labels SuperGrokPro as SuperGrok Pro" "$limits"
[[ $(jq -c '[.limits[] | {label, percent, resetsAt}]' <<<"$limits") == '[{"label":"Weekly","percent":0.24,"resetsAt":"2026-08-15T14:46:02.562637+00:00"}]' ]] ||
  fail "Grok collector reads the weekly credit pool" "$limits"
[[ $(jq -c '{remaining: .balance.remaining, funded: .balance.funded, spent: .balance.spent, currency: .balance.currency}' <<<"$limits") == '{"remaining":12.5,"funded":15.0,"spent":2.5,"currency":"USD"}' ]] ||
  fail "Grok collector reports prepaid and leftover on-demand credits" "$limits"
[[ $(jq -r '._probed | length' <<<"$limits") == "4" ]] ||
  fail "Grok collector probes billing, user, settings, and reset tokens once" "$limits"

# Banked resets: two are still inside their validity window, one lapsed.
banked=$(probe_record "$billing" "$user" force '{}' '[3600, 86400, -3600]')
[[ $(jq -r '.resetCreditsAvailable' <<<"$banked") == "2" ]] ||
  fail "Grok collector counts only banked resets that have not lapsed" "$banked"
pass "Grok collector counts only banked resets that have not lapsed"

none=$(probe_record "$billing" "$user" force '{}' '[]')
[[ $(jq -r '.resetCreditsAvailable' <<<"$none") == "0" ]] ||
  fail "Grok collector reports no banked resets as zero" "$none"
pass "Grok collector reports no banked resets as zero"
pass "Grok collector reads weekly limits and extra credits"

# The live display string from /v1/settings beats the machine subscriptionTier.
display=$(probe_record "$billing" "$user" force '{"subscription_tier_display":"SuperGrok Heavy"}')
[[ $(jq -r '.tierLabel' <<<"$display") == "SuperGrok Heavy" ]] ||
  fail "Grok collector prefers subscription_tier_display" "$display"
pass "Grok collector prefers subscription_tier_display"

# creditUsagePercent is a 0-100 percentage, so 0.4 is under one percent used.
fraction=$(probe_record '{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-08-15T14:46:02.562637+00:00"},"creditUsagePercent":0.4}}' "$user" force)
[[ $(jq -r '.limits[0].percent' <<<"$fraction") == "0.004" ]] ||
  fail "Grok collector reads creditUsagePercent as a percentage" "$fraction"
pass "Grok collector reads creditUsagePercent as a percentage"

# An expired token must not hit the network.
EXPIRED_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OTHER_HOME" "$CACHE_HOME" "$EXPIRED_HOME"' EXIT
mkdir -p "$EXPIRED_HOME/.grok/sessions/%2Ftmp%2Fproj"
cp -a "$session_dir" "$EXPIRED_HOME/.grok/sessions/%2Ftmp%2Fproj/"
python3 - "$EXPIRED_HOME/.grok/auth.json" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone
expires = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
open(sys.argv[1], "w").write(json.dumps({
  "https://auth.x.ai::test": {"key": "stale", "expires_at": expires, "auth_mode": "oidc"}
}))
PY

expired=$(COLLECTOR="$ROOT/bin/omarchy-agent-usage-grok" HOME="$EXPIRED_HOME" \
  XDG_CACHE_HOME="$EXPIRED_HOME/.cache" GROK_HOME="$EXPIRED_HOME/.grok" python3 - <<'PY'
import importlib.machinery, importlib.util, json, os

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

def unreachable(request, timeout=None):
  raise AssertionError("expired token must not probe")

collector.urllib.request.urlopen = unreachable
print(json.dumps(collector.build_record(force=True, limits_only=False)))
PY
)

[[ $(jq -r '.usageStatusText' <<<"$expired") == "Sign-in expired" ]] ||
  fail "Grok collector reports an expired sign-in" "$expired"
[[ $(jq -r '.retryAdvised // false' <<<"$expired") == "false" ]] ||
  fail "Grok collector does not treat expiry as a transient retry" "$expired"
[[ $(jq -r '.todayTotalTokens' <<<"$expired") == "1209" ]] ||
  fail "Grok collector keeps local stats when sign-in is expired" "$expired"
pass "Grok collector reports an expired sign-in without probing"

# --limits-only reuses a seconds-old scan; --force rereads the files.
# Drop the planted login so these runs stay offline.
scan_home="$CACHE_HOME"
rm -f "$scan_home/.grok/auth.json"
result=$(HOME="$scan_home" XDG_CACHE_HOME="$scan_home/.cache" GROK_HOME="$scan_home/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.todayPrompts' <<<"$result") == "3" ]] ||
  fail "Grok collector --force sees the fixture turns" "$result"

# Add another turn. A fresh --limits-only must keep the cached count.
session_id="$fixture_session_id" \
  turn_line "prompt-3" "grok-4.6" 20 2 0 0 >>"$scan_home/.grok/sessions/%2Ftmp%2Fproj/$fixture_session_id/updates.jsonl"

result=$(HOME="$scan_home" XDG_CACHE_HOME="$scan_home/.cache" GROK_HOME="$scan_home/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --limits-only)
[[ $(jq -r '.todayPrompts' <<<"$result") == "3" ]] ||
  fail "Grok collector --limits-only reuses a fresh scan cache" "$result"
pass "Grok collector --limits-only reuses a fresh scan cache"

result=$(HOME="$scan_home" XDG_CACHE_HOME="$scan_home/.cache" GROK_HOME="$scan_home/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.todayPrompts' <<<"$result") == "4" ]] ||
  fail "Grok collector --force rescans past the cache" "$result"
pass "Grok collector --force rescans past the cache"

# A cache older than the old 900s TTL must still be reused: opening the
# panel is --limits-only and must not walk transcripts to refresh the meter.
session_id="$fixture_session_id" \
  turn_line "prompt-4" "grok-4.6" 20 2 0 0 >>"$scan_home/.grok/sessions/%2Ftmp%2Fproj/$fixture_session_id/updates.jsonl"
find "$scan_home/.cache/omarchy/agent-usage" -name 'grok-scan-*.json' -exec touch -d '2 hours ago' {} +
result=$(HOME="$scan_home" XDG_CACHE_HOME="$scan_home/.cache" GROK_HOME="$scan_home/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --limits-only)
[[ $(jq -r '.todayPrompts' <<<"$result") == "4" ]] ||
  fail "Grok collector --limits-only reuses a stale same-day scan cache" "$result"
pass "Grok collector --limits-only reuses a stale same-day scan cache"

# An unwritable cache must not take the record down.
UNWRITABLE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OTHER_HOME" "$CACHE_HOME" "$EXPIRED_HOME" "$UNWRITABLE_HOME"' EXIT
mkdir -p "$UNWRITABLE_HOME/.grok/sessions/%2Ftmp%2Fproj"
cp -a "$session_dir" "$UNWRITABLE_HOME/.grok/sessions/%2Ftmp%2Fproj/"
touch "$UNWRITABLE_HOME/not-a-dir"
result=$(HOME="$UNWRITABLE_HOME" XDG_CACHE_HOME="$UNWRITABLE_HOME/not-a-dir" GROK_HOME="$UNWRITABLE_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "1209" ]] ||
  fail "Grok collector still prints a record when the cache is unwritable" "$result"
pass "Grok collector still prints a record when the cache is unwritable"

# Grok's cacheCreationTokens is not Claude's cacheCreationInputTokens. A
# two-model turn is still one prompt.
SHAPE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OTHER_HOME" "$CACHE_HOME" "$EXPIRED_HOME" "$UNWRITABLE_HOME" "$SHAPE_HOME"' EXIT
shape_id="019fb000-0000-7000-8000-000000000001"
shape_dir="$SHAPE_HOME/.grok/sessions/%2Ftmp%2Fshape/$shape_id"
mkdir -p "$shape_dir"
write_summary "$shape_dir"
{
  session_id="$shape_id" turn_line "prompt-write" "grok-4.6" 100 4 20 0 10
  python3 - "$timestamp" "$shape_id" <<'PY'
import json, sys
ts, sid = sys.argv[1:]
print(json.dumps({
  "timestamp": ts,
  "method": "session/update",
  "params": {
    "sessionId": sid,
    "update": {
      "sessionUpdate": "turn_completed",
      "prompt_id": "prompt-multi",
      "stop_reason": "end_turn",
      "usage": {
        "inputTokens": 18,
        "outputTokens": 3,
        "cachedReadTokens": 0,
        "cacheCreationTokens": 0,
        "reasoningTokens": 0,
        "modelUsage": {
          "grok-4.6": {"inputTokens": 10, "outputTokens": 2, "cachedReadTokens": 0, "cacheCreationTokens": 0},
          "grok-4.20": {"inputTokens": 8, "outputTokens": 1, "cachedReadTokens": 0, "cacheCreationTokens": 0}
        }
      }
    }
  }
}))
PY
} >"$shape_dir/updates.jsonl"

result=$(HOME="$SHAPE_HOME" XDG_CACHE_HOME="$SHAPE_HOME/.cache" GROK_HOME="$SHAPE_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.todayPrompts' <<<"$result") == "2" ]] ||
  fail "Grok collector counts a multi-model turn as one prompt" "$result"
[[ $(jq -c '.modelUsage["grok-4.6"]' <<<"$result") == '{"cacheCreationInputTokens":10,"cacheReadInputTokens":20,"inputTokens":80,"outputTokens":6}' ]] ||
  fail "Grok collector reads cacheCreationTokens and keeps it out of input" "$result"
[[ $(jq -c '.modelUsage["grok-4.20"]' <<<"$result") == '{"cacheCreationInputTokens":0,"cacheReadInputTokens":0,"inputTokens":8,"outputTokens":1}' ]] ||
  fail "Grok collector keeps the second model on the same prompt" "$result"
pass "Grok collector reads cacheCreationTokens and counts multi-model turns once"

# A fork summary written after the first scan must still drop that session.
FORK_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OTHER_HOME" "$CACHE_HOME" "$EXPIRED_HOME" "$UNWRITABLE_HOME" "$SHAPE_HOME" "$FORK_HOME"' EXIT
late_id="019fb000-0000-7000-8000-000000000002"
late_dir="$FORK_HOME/.grok/sessions/%2Ftmp%2Flate/$late_id"
mkdir -p "$late_dir"
write_summary "$late_dir"
session_id="$late_id" turn_line "late-1" "grok-4.6" 40 2 0 0 >"$late_dir/updates.jsonl"
result=$(HOME="$FORK_HOME" XDG_CACHE_HOME="$FORK_HOME/.cache" GROK_HOME="$FORK_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "42" ]] ||
  fail "Grok collector counts a session before its fork summary exists" "$result"
write_summary "$late_dir" "subagent_fork" "$late_id"
result=$(HOME="$FORK_HOME" XDG_CACHE_HOME="$FORK_HOME/.cache" GROK_HOME="$FORK_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "0" ]] ||
  fail "Grok collector rereads session_kind after summary.json appears" "$result"
pass "Grok collector rereads session_kind after summary.json appears"

# Prefer the SuperGrok issuer when auth.json still has a legacy entry.
AUTH_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OTHER_HOME" "$CACHE_HOME" "$EXPIRED_HOME" "$UNWRITABLE_HOME" "$SHAPE_HOME" "$FORK_HOME" "$AUTH_HOME"' EXIT
mkdir -p "$AUTH_HOME/.grok/sessions/%2Ftmp%2Fproj"
cp -a "$session_dir" "$AUTH_HOME/.grok/sessions/%2Ftmp%2Fproj/"
python3 - "$AUTH_HOME/.grok/auth.json" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone
expires = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
open(sys.argv[1], "w").write(json.dumps({
  "https://accounts.x.ai/sign-in": {"key": "legacy-token", "expires_at": expires, "auth_mode": "oidc"},
  "https://auth.x.ai::test": {"key": "supergrok-token", "expires_at": expires, "auth_mode": "oidc"},
}))
PY

auth_pick=$(COLLECTOR="$ROOT/bin/omarchy-agent-usage-grok" HOME="$AUTH_HOME" \
  XDG_CACHE_HOME="$AUTH_HOME/.cache" GROK_HOME="$AUTH_HOME/.grok" python3 - "$billing" "$user" <<'PY'
import importlib.machinery, importlib.util, io, json, os, sys

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

billing = json.loads(sys.argv[1])
user = json.loads(sys.argv[2])
seen = []

def urlopen(request, timeout=None):
  seen.append(request.get_header("Authorization"))
  url = request.full_url
  if "billing" in url:
    return io.BytesIO(json.dumps(billing).encode())
  if url.endswith("/settings"):
    return io.BytesIO(b"{}")
  return io.BytesIO(json.dumps(user).encode())

collector.urllib.request.urlopen = urlopen
record = collector.build_record(force=True, limits_only=False)
record["_auth"] = seen
print(json.dumps(record))
PY
)
[[ $(jq -r '._auth | unique | .[]' <<<"$auth_pick") == "Bearer supergrok-token" ]] ||
  fail "Grok collector prefers the SuperGrok auth.json entry" "$auth_pick"
pass "Grok collector prefers the SuperGrok auth.json entry"

# 401 is a stable expired login; a transport miss still asks for a retry.
rejected=$(COLLECTOR="$ROOT/bin/omarchy-agent-usage-grok" HOME="$AUTH_HOME" \
  XDG_CACHE_HOME="$AUTH_HOME/.cache" GROK_HOME="$AUTH_HOME/.grok" python3 - <<'PY'
import importlib.machinery, importlib.util, json, os, urllib.error

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

def urlopen(request, timeout=None):
  raise urllib.error.HTTPError(request.full_url, 401, "Unauthorized", None, None)

collector.urllib.request.urlopen = urlopen
print(json.dumps(collector.build_record(force=True, limits_only=False)))
PY
)
[[ $(jq -r '.usageStatusText' <<<"$rejected") == "Sign-in expired" ]] ||
  fail "Grok collector reports a rejected login as expired" "$rejected"
[[ $(jq -r '.retryAdvised // false' <<<"$rejected") == "false" ]] ||
  fail "Grok collector does not retry a rejected login" "$rejected"
pass "Grok collector does not retry a rejected login"

# A server that answered with an error status is not a transport miss either.
server_error=$(COLLECTOR="$ROOT/bin/omarchy-agent-usage-grok" HOME="$AUTH_HOME" \
  XDG_CACHE_HOME="$AUTH_HOME/.cache" GROK_HOME="$AUTH_HOME/.grok" python3 - <<'PY'
import importlib.machinery, importlib.util, json, os, urllib.error

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

def urlopen(request, timeout=None):
  raise urllib.error.HTTPError(request.full_url, 503, "Service Unavailable", None, None)

collector.urllib.request.urlopen = urlopen
print(json.dumps(collector.build_record(force=True, limits_only=False)))
PY
)
[[ $(jq -r '.usageStatusText' <<<"$server_error") == "Grok limits unavailable" ]] ||
  fail "Grok collector reports a server error status" "$server_error"
[[ $(jq -r '.authHelpText' <<<"$server_error") == *"status 503"* ]] ||
  fail "Grok collector names the status it got back" "$server_error"
[[ $(jq -r '.retryAdvised // false' <<<"$server_error") == "false" ]] ||
  fail "Grok collector does not retry a server error status" "$server_error"
pass "Grok collector does not retry a server error status"

unreachable=$(COLLECTOR="$ROOT/bin/omarchy-agent-usage-grok" HOME="$AUTH_HOME" \
  XDG_CACHE_HOME="$AUTH_HOME/.cache" GROK_HOME="$AUTH_HOME/.grok" python3 - <<'PY'
import importlib.machinery, importlib.util, json, os, urllib.error

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

def urlopen(request, timeout=None):
  raise urllib.error.URLError("timed out")

collector.urllib.request.urlopen = urlopen
print(json.dumps(collector.build_record(force=True, limits_only=False)))
PY
)
[[ $(jq -r '.usageStatusText' <<<"$unreachable") == "Grok limits unavailable" ]] ||
  fail "Grok collector reports a transport miss" "$unreachable"
[[ $(jq -r '.retryAdvised' <<<"$unreachable") == "true" ]] ||
  fail "Grok collector advises a retry after a transport failure" "$unreachable"
pass "Grok collector advises a retry after a transport failure"

# Flat turn_completed (ledger on the update) and event_name both count.
FLAT_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OTHER_HOME" "$CACHE_HOME" "$EXPIRED_HOME" "$UNWRITABLE_HOME" "$SHAPE_HOME" "$FORK_HOME" "$AUTH_HOME" "$FLAT_HOME"' EXIT
flat_id="019fb000-0000-7000-8000-000000000003"
flat_dir="$FLAT_HOME/.grok/sessions/%2Ftmp%2Fflat/$flat_id"
mkdir -p "$flat_dir"
write_summary "$flat_dir"
python3 - "$timestamp" "$flat_id" >"$flat_dir/updates.jsonl" <<'PY'
import json, sys
ts, sid = sys.argv[1:]
print(json.dumps({
  "timestamp": ts,
  "method": "session/update",
  "params": {
    "sessionId": sid,
    "update": {
      "sessionUpdate": "turn_completed",
      "prompt_id": "flat-1",
      "inputTokens": 40,
      "outputTokens": 6,
      "cachedReadTokens": 10,
      "cacheCreationTokens": 0,
      "reasoningTokens": 2
    }
  }
}))
print(json.dumps({
  "timestamp": ts,
  "method": "session/update",
  "params": {
    "sessionId": sid,
    "update": {
      "event_name": "turn_completed",
      "prompt_id": "named-1",
      "usage": {
        "inputTokens": 20,
        "outputTokens": 4,
        "cachedReadTokens": 0,
        "cacheCreationTokens": 0,
        "reasoningTokens": 0
      }
    }
  }
}))
print(json.dumps({
  "timestamp": ts,
  "method": "session/update",
  "params": {
    "sessionId": sid,
    "update": {
      "sessionUpdate": "turn_completed",
      "prompt_id": "empty-nested",
      "usage": {},
      "inputTokens": 8,
      "outputTokens": 1,
      "cachedReadTokens": 0,
      "cacheCreationTokens": 0,
      "reasoningTokens": 0
    }
  }
}))
PY
result=$(HOME="$FLAT_HOME" XDG_CACHE_HOME="$FLAT_HOME/.cache" GROK_HOME="$FLAT_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.todayPrompts' <<<"$result") == "3" ]] ||
  fail "Grok collector counts flat and event_name turn_completed rows" "$result"
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "79" ]] ||
  fail "Grok collector reads a flat turn_completed ledger" "$result"
pass "Grok collector reads flat and event_name turn_completed rows"

# A subscription burned entirely through opencode has no Grok Build transcripts;
# usage must come from opencode's message database, filtered to xAI.
OPENCODE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OTHER_HOME" "$CACHE_HOME" "$EXPIRED_HOME" "$UNWRITABLE_HOME" "$SHAPE_HOME" "$FORK_HOME" "$AUTH_HOME" "$FLAT_HOME" "$OPENCODE_HOME"' EXIT

python3 - "$OPENCODE_HOME/.local/share/opencode/opencode.db" <<'PY'
import json
import sqlite3
import sys
import time
from pathlib import Path

db = Path(sys.argv[1])
db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now_ms = int(time.time() * 1000)

def message(id, provider, model, role="assistant", input=0, output=0, reasoning=0, read=0, write=0):
  return (id, "ses_1", now_ms, now_ms, json.dumps({
    "role": role,
    "providerID": provider,
    "modelID": model,
    "tokens": {"input": input, "output": output, "reasoning": reasoning, "cache": {"read": read, "write": write}},
    "time": {"created": now_ms},
  }))

conn.executemany("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [
  message("msg_1", "xai", "grok-4.6", input=80, output=40, reasoning=5, read=30),
  message("msg_2", "anthropic", "claude-opus-5", input=999, output=999),
  message("msg_3", "openai", "gpt-5.2-codex", input=999, output=999),
  message("msg_4", "xai", "grok-4.6", role="user"),
  message("msg_5", "xai-proxy", "grok-4.6", input=999, output=999),
])
conn.execute("INSERT INTO message VALUES ('msg_6', 'ses_1', ?, ?, '[\"not\",\"an\",\"object\"]')", (now_ms, now_ms))
conn.commit()
conn.close()
PY

result=$(HOME="$OPENCODE_HOME" XDG_CACHE_HOME="$OPENCODE_HOME/.cache" XDG_DATA_HOME="$OPENCODE_HOME/.local/share" \
  GROK_HOME="$OPENCODE_HOME/.grok" "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "155" ]] ||
  fail "Grok collector counts xAI usage, reasoning included, from opencode sessions" "$result"
pass "Grok collector counts xAI usage, reasoning included, from opencode sessions"

[[ $(jq -c '.modelUsage' <<<"$result") == '{"grok-4.6":{"cacheCreationInputTokens":0,"cacheReadInputTokens":30,"inputTokens":80,"outputTokens":45}}' ]] ||
  fail "Grok collector ignores prefix-colliding providers, user messages, and malformed rows" "$result"
pass "Grok collector ignores prefix-colliding providers, user messages, and malformed rows"

[[ $(jq -r '(.todayPrompts|tostring) + "/" + (.todaySessions|tostring)' <<<"$result") == "1/1" ]] ||
  fail "Grok collector counts the opencode session once" "$result"
pass "Grok collector counts the opencode session once"

# A scan cut short by a database error must not be cached as the whole story.
INTERRUPTED_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OTHER_HOME" "$CACHE_HOME" "$EXPIRED_HOME" "$UNWRITABLE_HOME" "$SHAPE_HOME" "$FORK_HOME" "$AUTH_HOME" "$FLAT_HOME" "$OPENCODE_HOME" "$INTERRUPTED_HOME"' EXIT

python3 - "$INTERRUPTED_HOME/.local/share/opencode/opencode.db" <<'PY'
import sqlite3
import sys
from pathlib import Path

db = Path(sys.argv[1])
db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE unrelated (id text PRIMARY KEY)")
conn.commit()
conn.close()
PY

result=$(HOME="$INTERRUPTED_HOME" XDG_CACHE_HOME="$INTERRUPTED_HOME/.cache" XDG_DATA_HOME="$INTERRUPTED_HOME/.local/share" \
  GROK_HOME="$INTERRUPTED_HOME/.grok" "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "0" ]] ||
  fail "Grok collector reports what it could read from a broken database" "$result"
[[ -z $(ls "$INTERRUPTED_HOME/.cache/omarchy/agent-usage/"grok-scan-*.json 2>/dev/null) ]] ||
  fail "Grok collector must not cache an interrupted scan" "$result"

python3 - "$INTERRUPTED_HOME/.local/share/opencode/opencode.db" <<'PY'
import json
import sqlite3
import sys
import time
from pathlib import Path

db = Path(sys.argv[1])
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now_ms = int(time.time() * 1000)
conn.execute("INSERT INTO message VALUES (?, ?, ?, ?, ?)", (
  "i_1", "ses_1", now_ms, now_ms, json.dumps({
    "role": "assistant",
    "providerID": "xai",
    "modelID": "grok-4.6",
    "tokens": {"input": 9, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": now_ms},
  }),
))
conn.commit()
conn.close()
PY

result=$(HOME="$INTERRUPTED_HOME" XDG_CACHE_HOME="$INTERRUPTED_HOME/.cache" XDG_DATA_HOME="$INTERRUPTED_HOME/.local/share" \
  GROK_HOME="$INTERRUPTED_HOME/.grok" "$ROOT/bin/omarchy-agent-usage-grok" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "9" ]] ||
  fail "Grok collector does not reuse a snapshot from an interrupted scan" "$result"
pass "Grok collector does not cache an interrupted opencode scan"
