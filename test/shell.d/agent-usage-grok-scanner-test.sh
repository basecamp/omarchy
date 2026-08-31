#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/bin"

# Hide the real grok binary so local-scan tests do not hit live billing.
jq_dir=$(dirname "$(command -v jq)")
export PATH="$TEST_HOME/bin:$jq_dir:/usr/bin:/bin"

install_grok_stub() {
  printf '%s\n' "$1" >"$TEST_HOME/bin/grok-billing.json"
  cat >"$TEST_HOME/bin/grok" <<'EOF'
#!/bin/bash
billing="$(dirname "$0")/grok-billing.json"
while read -r request; do
  id=$(jq -r '.id // empty' <<<"$request")
  method=$(jq -r '.method // empty' <<<"$request")
  [[ -z $id ]] && continue
  case "$method" in
  initialize)
    jq -cn --argjson id "$id" '{jsonrpc:"2.0",id:$id,result:{}}'
    ;;
  _x.ai/billing)
    jq -cn --argjson id "$id" --slurpfile result "$billing" '{jsonrpc:"2.0",id:$id,result:$result[0]}'
    ;;
  esac
done
EOF
  chmod +x "$TEST_HOME/bin/grok"
}

today="$(date +%Y-%m-%d)"
session_dir="$TEST_HOME/.grok/sessions/%2Ftmp/01a00c12-f7c9-7413-81bb-a18404c10c70"
mkdir -p "$session_dir"

cat >"$session_dir/summary.json" <<EOF
{
  "info": {"id": "01a00c12-f7c9-7413-81bb-a18404c10c70", "cwd": "/tmp"},
  "current_model_id": "grok-4.6"
}
EOF

cat >"$session_dir/updates.jsonl" <<EOF
{"timestamp":"${today}T12:00:00Z","method":"_x.ai/session/update","params":{"sessionId":"01a00c12-f7c9-7413-81bb-a18404c10c70","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"hi"}}}}
{"timestamp":"${today}T12:01:00Z","method":"_x.ai/session/update","params":{"sessionId":"01a00c12-f7c9-7413-81bb-a18404c10c70","update":{"sessionUpdate":"turn_completed","prompt_id":"turn-1","usage":{"inputTokens":100,"outputTokens":20,"cachedReadTokens":60,"cacheCreationTokens":10,"reasoningTokens":5,"modelUsage":{"grok-4.6-build":{"inputTokens":100,"outputTokens":20,"cachedReadTokens":60,"cacheCreationTokens":10,"reasoningTokens":5}}}}}}
{"timestamp":"${today}T13:00:00Z","method":"_x.ai/session/update","params":{"sessionId":"01a00c12-f7c9-7413-81bb-a18404c10c70","update":{"sessionUpdate":"turn_completed","prompt_id":"turn-2","usage":{"inputTokens":50,"outputTokens":8,"cachedReadTokens":0,"cacheCreationTokens":0,"reasoningTokens":12,"modelUsage":{"grok-4.6-build":{"inputTokens":50,"outputTokens":8,"cachedReadTokens":0,"cacheCreationTokens":0,"reasoningTokens":12}}}}}}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.id + "/" + (.todayPrompts|tostring) + "/" + (.todaySessions|tostring)' <<<"$result") == "grok/2/1" ]] ||
  fail "Grok collector counts turn_completed events as prompts" "$result"
pass "Grok collector counts turn_completed events as prompts"

# input 100-60-10=30 + 50=80; output max(20,5)=20 + max(8,12)=12 → 32;
# cache read 60; cache write 10; total 80+32+60+10=182
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "182" ]] ||
  fail "Grok collector sums billed tokens from turn_completed" "$result"
[[ $(jq -c '.modelUsage["grok-4.6-build"]' <<<"$result") == '{"cacheCreationInputTokens":10,"cacheReadInputTokens":60,"inputTokens":80,"outputTokens":32}' ]] ||
  fail "Grok collector splits cache out of input and folds extra reasoning into output" "$result"
[[ $(jq -r '.recentDays[] | select(.date=="'"$today"'") | .messageCount' <<<"$result") == "182" ]] ||
  fail "Grok collector files token totals on recentDays.messageCount" "$result"
pass "Grok collector maps nested turn_completed usage into panel buckets"

[[ $(jq -c '.limits' <<<"$result") == '[]' ]] ||
  fail "Grok collector leaves limits empty when grok is not on PATH" "$result"
[[ $(jq -r '.usageStatusText' <<<"$result") == "Grok unavailable" ]] ||
  fail "Grok collector reports missing grok binary" "$result"
pass "Grok collector leaves limits empty when grok is not on PATH"

# Flat ledger + event_name still counts (Grok Build variant without nested usage).
flat="$TEST_HOME/.grok/sessions/%2Ftmp/flat-session"
mkdir -p "$flat"
cat >"$flat/summary.json" <<EOF
{"info":{"id":"flat-session"},"current_model_id":"grok-4.6"}
EOF
cat >"$flat/updates.jsonl" <<EOF
{"timestamp":"${today}T14:00:00Z","method":"session/update","params":{"update":{"event_name":"turn_completed","prompt_id":"flat-1","inputTokens":10,"outputTokens":4,"cachedReadTokens":3}}}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '(.totalSessions|tostring) + "/" + (.totalPrompts|tostring)' <<<"$result") == "2/3" ]] ||
  fail "Grok collector counts flat event_name turn_completed rows" "$result"
# previous 182 + (10-3)+4+3 = 196
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "196" ]] ||
  fail "Grok collector adds flat-ledger tokens" "$result"
pass "Grok collector counts flat event_name turn_completed rows"

# Duplicate prompt_id in the same file is counted once.
dup="$TEST_HOME/.grok/sessions/%2Ftmp/dup-session"
mkdir -p "$dup"
cat >"$dup/summary.json" <<EOF
{"info":{"id":"dup-session"}}
EOF
cat >"$dup/updates.jsonl" <<EOF
{"timestamp":"${today}T15:00:00Z","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"same","usage":{"inputTokens":6,"outputTokens":1}}}}
{"timestamp":"${today}T15:00:01Z","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"same","usage":{"inputTokens":6,"outputTokens":1}}}}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.totalPrompts' <<<"$result") == "4" ]] ||
  fail "Grok collector dedupes turn_completed by prompt_id" "$result"
pass "Grok collector dedupes turn_completed by prompt_id"

# Subagent sessions are skipped so parent totals are not counted twice.
child="$TEST_HOME/.grok/sessions/%2Ftmp/child-session"
mkdir -p "$child"
cat >"$child/summary.json" <<EOF
{"info":{"id":"child-session"},"session_kind":"subagent"}
EOF
cat >"$child/updates.jsonl" <<EOF
{"timestamp":"${today}T16:00:00Z","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"child-1","usage":{"inputTokens":999,"outputTokens":999}}}}
EOF
fork="$TEST_HOME/.grok/sessions/%2Ftmp/fork-session"
mkdir -p "$fork"
cat >"$fork/summary.json" <<EOF
{"info":{"id":"fork-session"},"session_kind":"subagent_fork"}
EOF
cat >"$fork/updates.jsonl" <<EOF
{"timestamp":"${today}T16:00:00Z","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"fork-1","usage":{"inputTokens":888,"outputTokens":888}}}}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.totalPrompts' <<<"$result") == "4" ]] ||
  fail "Grok collector skips subagent session_kind" "$result"
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "203" ]] ||
  fail "Grok collector does not add subagent tokens" "$result"
pass "Grok collector skips subagent session_kind"

# events.jsonl turn_started alone must not invent tokens (the previous scanner's bug).
events_only="$TEST_HOME/.grok/sessions/%2Ftmp/events-only"
mkdir -p "$events_only"
cat >"$events_only/summary.json" <<EOF
{"info":{"id":"events-only"},"current_model_id":"grok-4.6"}
EOF
cat >"$events_only/events.jsonl" <<EOF
{"ts":"${today}T12:00:00Z","type":"turn_started","turn_number":0,"model_id":"grok-4.6"}
{"ts":"${today}T12:01:00Z","type":"turn_ended","outcome":"completed"}
EOF
cat >"$events_only/chat_history.jsonl" <<'EOF'
{"type":"user","prompt_index":0,"content":[{"type":"text","text":"hello"}]}
{"type":"assistant","content":"hi","usage":{"input_tokens":10,"output_tokens":4}}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.totalPrompts' <<<"$result") == "4" ]] ||
  fail "Grok collector ignores events.jsonl and chat_history.jsonl" "$result"
pass "Grok collector ignores events.jsonl and chat_history.jsonl"

# GROK_HOME points at an empty tree: valid empty record, not a crash.
EMPTY_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME"' EXIT
result=$(HOME="$EMPTY_HOME" XDG_CACHE_HOME="$EMPTY_HOME/.cache" GROK_HOME="$EMPTY_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '(.id) + "/" + (.totalSessions|tostring) + "/" + .authHelpText' <<<"$result") == "grok/0/Run \`grok login\` to sign in." ]] ||
  fail "Grok collector reports an empty install" "$result"
pass "Grok collector reports an empty install"

# Weekly SuperGrok pool + plan label from ACP _x.ai/billing.
install_grok_stub '{"config":{"creditUsagePercent":31,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-08-22T23:23:37.992320+00:00"},"prepaidBalance":{"val":0},"onDemandCap":{"val":0},"onDemandUsed":{"val":0}},"subscription_tier":"SuperGrok Heavy"}'
result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.tierLabel' <<<"$result") == "SuperGrok Heavy" ]] ||
  fail "Grok collector uses the ACP plan display string" "$result"
[[ $(jq -r '.limits[0].label' <<<"$result") == "Weekly" ]] ||
  fail "Grok collector labels a weekly pool Weekly" "$result"
[[ $(jq -r '.limits[0].percent * 100 | round' <<<"$result") == "31" ]] ||
  fail "Grok collector maps creditUsagePercent 0-100 onto the panel meter" "$result"
[[ $(jq -r '.limits[0].resetsAt' <<<"$result") == "2026-08-22T23:23:37.992320+00:00" ]] ||
  fail "Grok collector copies the weekly reset timestamp" "$result"
[[ $(jq 'has("balance")' <<<"$result") == "false" ]] ||
  fail "Grok collector omits a zero prepaid ledger" "$result"
pass "Grok collector maps a SuperGrok weekly pool onto the panel meter"

# Internal SuperGrokPro enum is rewritten; monthly periods keep their label.
install_grok_stub '{"config":{"creditUsagePercent":8,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY","end":"2026-09-01T00:00:00+00:00"}},"subscriptionTier":"SuperGrokPro"}'
result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.tierLabel + "/" + .limits[0].label' <<<"$result") == "SuperGrok Pro/Monthly" ]] ||
  fail "Grok collector rewrites SuperGrokPro and labels monthly pools" "$result"
pass "Grok collector rewrites SuperGrokPro and labels monthly pools"

# Live ACP Money.val is integer cents: prepaidBalance.val 488 is $4.88,
# matching Grok Build /usage — not $488.00.
install_grok_stub '{"config":{"creditUsagePercent":22,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-08-29T00:00:00Z"},"prepaidBalance":{"val":488},"onDemandCap":{"val":0},"onDemandUsed":{"val":0}},"subscription_tier":"SuperGrok Plus"}'
result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq '.balance.remaining == 4.88 and .balance.funded == 4.88 and .balance.spent == 0' <<<"$result") == "true" ]] ||
  fail "Grok collector treats ACP Money.val as integer cents" "$result"
pass "Grok collector treats ACP Money.val as integer cents"

# Leftover prepaid plus unused on-demand cap, still in cents.
install_grok_stub '{"config":{"creditUsagePercent":10,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-08-29T00:00:00Z"},"prepaidBalance":{"val":1250},"onDemandCap":{"val":2000},"onDemandUsed":{"val":500}},"subscription_tier":"SuperGrok Heavy"}'
result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq '.balance.remaining == 27.5 and .balance.funded == 32.5 and .balance.spent == 5' <<<"$result") == "true" ]] ||
  fail "Grok collector adds prepaid leftover to unused on-demand cap" "$result"
[[ $(jq -r '.limits | length' <<<"$result") == "1" ]] ||
  fail "Grok collector still draws the weekly meter next to a prepaid balance" "$result"
pass "Grok collector reports leftover prepaid credits as a balance"

# Missing creditUsagePercent: plan still shows, no invented meter.
install_grok_stub '{"config":{},"subscription_tier":"SuperGrok Heavy"}'
result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.tierLabel' <<<"$result") == "SuperGrok Heavy" ]] ||
  fail "Grok collector keeps the plan label without a usage percent" "$result"
[[ $(jq -c '.limits' <<<"$result") == '[]' ]] ||
  fail "Grok collector does not invent a meter without creditUsagePercent" "$result"
pass "Grok collector does not invent a meter without creditUsagePercent"

# Auth failure on the billing RPC is a sign-in problem, not a retry loop.
cat >"$TEST_HOME/bin/grok" <<'EOF'
#!/bin/bash
while read -r request; do
  id=$(jq -r '.id // empty' <<<"$request")
  method=$(jq -r '.method // empty' <<<"$request")
  [[ -z $id ]] && continue
  case "$method" in
  initialize)
    jq -cn --argjson id "$id" '{jsonrpc:"2.0",id:$id,result:{}}'
    ;;
  _x.ai/billing)
    jq -cn --argjson id "$id" '{jsonrpc:"2.0",id:$id,error:{code:401,message:"unauthorized"}}'
    ;;
  esac
done
EOF
chmod +x "$TEST_HOME/bin/grok"
result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.usageStatusText' <<<"$result") == "Sign-in expired" ]] ||
  fail "Grok collector treats billing 401 as expired sign-in" "$result"
[[ $(jq '.retryAdvised // false' <<<"$result") == "false" ]] ||
  fail "Grok collector does not retry an expired login every 30s" "$result"
pass "Grok collector treats billing 401 as expired sign-in"

# "author" contains "auth"; that must not look like expired sign-in.
cat >"$TEST_HOME/bin/grok" <<'EOF'
#!/bin/bash
while read -r request; do
  id=$(jq -r '.id // empty' <<<"$request")
  method=$(jq -r '.method // empty' <<<"$request")
  [[ -z $id ]] && continue
  case "$method" in
  initialize)
    jq -cn --argjson id "$id" '{jsonrpc:"2.0",id:$id,result:{}}'
    ;;
  _x.ai/billing)
    jq -cn --argjson id "$id" '{jsonrpc:"2.0",id:$id,error:{code:-32603,message:"Request author mismatch"}}'
    ;;
  esac
done
EOF
chmod +x "$TEST_HOME/bin/grok"
result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.usageStatusText' <<<"$result") == "Grok limits unavailable" ]] ||
  fail "Grok collector does not treat author in an error as expired sign-in" "$result"
[[ $(jq '.retryAdvised // false' <<<"$result") == "true" ]] ||
  fail "Grok collector retries a non-auth billing error" "$result"
pass "Grok collector does not treat author in an error as expired sign-in"

# Mise wrappers may print a non-JSON line before ACP traffic; skip it.
cat >"$TEST_HOME/bin/grok" <<'EOF'
#!/bin/bash
echo "mise: ignored wrapper line"
billing="$(dirname "$0")/grok-billing.json"
cat >"$billing" <<'JSON'
{"config":{"creditUsagePercent":4,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-08-29T00:00:00Z"}},"subscription_tier":"SuperGrok"}
JSON
while read -r request; do
  id=$(jq -r '.id // empty' <<<"$request")
  method=$(jq -r '.method // empty' <<<"$request")
  [[ -z $id ]] && continue
  case "$method" in
  initialize)
    jq -cn --argjson id "$id" '{jsonrpc:"2.0",id:$id,result:{}}'
    ;;
  _x.ai/billing)
    echo '{"jsonrpc":"2.0","method":"_x.ai/mcp/servers_updated","params":{}}'
    jq -cn --argjson id "$id" --slurpfile result "$billing" '{jsonrpc:"2.0",id:$id,result:$result[0]}'
    ;;
  esac
done
EOF
chmod +x "$TEST_HOME/bin/grok"
result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.limits[0].percent * 100 | round' <<<"$result") == "4" ]] ||
  fail "Grok collector skips non-JSON wrapper lines and ACP notifications" "$result"
pass "Grok collector skips non-JSON wrapper lines and ACP notifications"

# Pi and omp can spend a SuperGrok subscription without writing Grok Build
# transcripts. Match Claude/Codex: merge those trees, filtered to xAI.
PI_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$PI_HOME"' EXIT
mkdir -p "$PI_HOME/.pi/agent/sessions/project" "$PI_HOME/.omp/agent/sessions/project"
now_ms=$(python3 -c 'import time; print(int(time.time() * 1000))')
cat >"$PI_HOME/.pi/agent/sessions/project/pi.jsonl" <<EOF
{"type":"message","id":"pi-1","timestamp":$now_ms,"message":{"role":"assistant","provider":"xai","model":"grok-4.6","usage":{"input":100,"output":20,"cacheRead":10,"cacheWrite":0,"reasoning":5}}}
{"type":"message","id":"pi-auth","timestamp":$now_ms,"message":{"role":"assistant","provider":"xai-auth","model":"grok-4.6","usage":{"input":8,"output":2}}}
{"type":"message","id":"pi-user","timestamp":$now_ms,"message":{"role":"user","provider":"xai","model":"grok-4.6","usage":{"input":50,"output":1}}}
["usage","assistant"]
EOF
cat >"$PI_HOME/.omp/agent/sessions/project/omp.jsonl" <<EOF
{"type":"message","id":"omp-1","timestamp":$now_ms,"message":{"role":"assistant","provider":"xai","model":"grok-omp","usage":{"input":20,"output":5,"cacheRead":4,"cacheWrite":1}}}
{"type":"message","id":"other-1","timestamp":$now_ms,"message":{"role":"assistant","provider":"anthropic","model":"claude-test","usage":{"input":999,"output":999}}}
{"type":"message","id":"proxy-1","timestamp":$now_ms,"message":{"role":"assistant","provider":"xai-proxy","model":"grok-4.6","usage":{"input":999,"output":999}}}
EOF

jq_bin=$(command -v jq)
result=$(HOME="$PI_HOME" XDG_CACHE_HOME="$PI_HOME/.cache" XDG_DATA_HOME="$PI_HOME/.local/share" \
  GROK_HOME="$PI_HOME/.grok" PATH="$(dirname "$jq_bin"):/usr/bin:/bin" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

# pi: 100-10 cache = 90 input + 20 output + 10 cache (reasoning already in output)
# xai-auth: 8 + 2
# omp: 20-5 cache = 15 input + 5 output + 4 read + 1 write
# total 155; anthropic, xai-proxy, user rows ignored
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "155" ]] ||
  fail "Grok collector counts usage from pi and omp xAI sessions" "$result"
[[ $(jq -r '.todayPrompts' <<<"$result") == "3" ]] ||
  fail "Grok collector counts one prompt per xAI assistant message" "$result"
[[ $(jq -r '.todaySessions' <<<"$result") == "2" ]] ||
  fail "Grok collector counts pi and omp sessions separately" "$result"
[[ $(jq -c '.modelUsage' <<<"$result") == '{"grok-4.6":{"cacheCreationInputTokens":0,"cacheReadInputTokens":10,"inputTokens":98,"outputTokens":22},"grok-omp":{"cacheCreationInputTokens":1,"cacheReadInputTokens":4,"inputTokens":15,"outputTokens":5}}' ]] ||
  fail "Grok collector filters pi and omp sessions to xAI providers" "$result"
pass "Grok collector counts pi and omp xAI subscription usage"

# A subscription burned entirely through opencode has no Grok Build files.
OPENCODE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$PI_HOME" "$OPENCODE_HOME"' EXIT

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
  GROK_HOME="$OPENCODE_HOME/.grok" PATH="$(dirname "$jq_bin"):/usr/bin:/bin" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "155" ]] ||
  fail "Grok collector counts xAI usage, reasoning included, from opencode sessions" "$result"
[[ $(jq -c '.modelUsage' <<<"$result") == '{"grok-4.6":{"cacheCreationInputTokens":0,"cacheReadInputTokens":30,"inputTokens":80,"outputTokens":45}}' ]] ||
  fail "Grok collector ignores prefix-colliding providers, user messages, and malformed rows" "$result"
[[ $(jq -r '(.todayPrompts|tostring) + "/" + (.todaySessions|tostring)' <<<"$result") == "1/1" ]] ||
  fail "Grok collector counts the opencode session once" "$result"
pass "Grok collector counts xAI usage from opencode sessions"

# A scan cut short by a database error must not be cached as the whole story.
INTERRUPTED_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$PI_HOME" "$OPENCODE_HOME" "$INTERRUPTED_HOME"' EXIT

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
  GROK_HOME="$INTERRUPTED_HOME/.grok" PATH="$(dirname "$jq_bin"):/usr/bin:/bin" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

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
  GROK_HOME="$INTERRUPTED_HOME/.grok" PATH="$(dirname "$jq_bin"):/usr/bin:/bin" \
  "$ROOT/bin/omarchy-agent-usage-grok" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "9" ]] ||
  fail "Grok collector does not reuse a snapshot from an interrupted scan" "$result"
pass "Grok collector does not cache an interrupted opencode scan"

# Cache is an optimization: the record is the contract. Stamp scanDate, reject
# a corrupt envelope, and never let an unwritable cache take the collector down.
CACHE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$PI_HOME" "$OPENCODE_HOME" "$INTERRUPTED_HOME" "$CACHE_HOME"' EXIT
cache_session="$CACHE_HOME/.grok/sessions/%2Ftmp/cache-session"
mkdir -p "$cache_session"
cat >"$cache_session/summary.json" <<'EOF'
{"info":{"id":"cache-session"}}
EOF
cat >"$cache_session/updates.jsonl" <<EOF
{"timestamp":"${today}T12:00:00Z","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"c1","usage":{"inputTokens":5,"outputTokens":0}}}}
EOF

result=$(HOME="$CACHE_HOME" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  GROK_HOME="$CACHE_HOME/.grok" PATH="$(dirname "$jq_bin"):/usr/bin:/bin" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "5" ]] ||
  fail "Grok collector writes a fresh local-stats cache on first scan" "$result"
cache_file=$(ls "$CACHE_HOME/.cache/omarchy/agent-usage/"grok-scan-*.json 2>/dev/null | head -n 1)
[[ -n $cache_file && -s $cache_file ]] ||
  fail "Grok collector leaves a cache file behind" "$result"
[[ $(stat -c %a "$cache_file") == "644" ]] ||
  fail "Grok collector keeps cache files readable" "$result"
[[ $(jq -r '.schemaVersion' "$cache_file") == "3" && $(jq -r '.scanDate' "$cache_file") == "$today" && $(jq -r '.stats.todayTotalTokens' "$cache_file") == "5" ]] ||
  fail "Grok collector writes a versioned cache envelope with scanDate" "$result"
pass "Grok collector writes a local-stats cache on first scan"

# A parseable envelope with the wrong shape is a miss: rescan and rewrite.
printf '{"schemaVersion":3,"scanDate":"%s","stats":{"foo":1}}\n' "$today" >"$cache_file"
result=$(HOME="$CACHE_HOME" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  GROK_HOME="$CACHE_HOME/.grok" PATH="$(dirname "$jq_bin"):/usr/bin:/bin" \
  "$ROOT/bin/omarchy-agent-usage-grok")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "5" ]] ||
  fail "Grok collector recovers from a corrupt cache file" "$result"
[[ $(jq -r '.schemaVersion' "$cache_file") == "3" && $(jq -r '.stats.todayTotalTokens' "$cache_file") == "5" ]] ||
  fail "Grok collector rewrites the cache after a corrupt read" "$result"
pass "Grok collector recovers from a corrupt cache file"

# A new turn changes what a scan would find; --limits-only must reuse cache.
cat >>"$cache_session/updates.jsonl" <<EOF
{"timestamp":"${today}T12:01:00Z","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"c2","usage":{"inputTokens":10,"outputTokens":0}}}}
EOF
result=$(HOME="$CACHE_HOME" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  GROK_HOME="$CACHE_HOME/.grok" PATH="$(dirname "$jq_bin"):/usr/bin:/bin" \
  "$ROOT/bin/omarchy-agent-usage-grok" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "5" ]] ||
  fail "Grok collector --limits-only reuses cached local stats" "$result"
pass "Grok collector --limits-only reuses cached local stats"

result=$(HOME="$CACHE_HOME" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  GROK_HOME="$CACHE_HOME/.grok" PATH="$(dirname "$jq_bin"):/usr/bin:/bin" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "15" ]] ||
  fail "Grok collector --force rescans past the cache" "$result"
pass "Grok collector --force rescans past the cache"

# A cache from another local date holds another day's today* stats even with
# a fresh mtime: scanDate must turn it into a miss.
cat >>"$cache_session/updates.jsonl" <<EOF
{"timestamp":"${today}T12:02:00Z","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"c3","usage":{"inputTokens":10,"outputTokens":0}}}}
EOF
jq -c --arg day "1999-01-01" '.scanDate = $day' "$cache_file" >"$cache_file.tmp" && mv "$cache_file.tmp" "$cache_file"
result=$(HOME="$CACHE_HOME" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  GROK_HOME="$CACHE_HOME/.grok" PATH="$(dirname "$jq_bin"):/usr/bin:/bin" \
  "$ROOT/bin/omarchy-agent-usage-grok" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "25" ]] ||
  fail "Grok collector treats a cache from another day as a miss" "$result"
[[ $(jq -r '.scanDate' "$cache_file") == "$today" ]] ||
  fail "Grok collector stamps the rewritten cache with the scan date" "$result"
pass "Grok collector treats a cache from another day as a miss"

# A cache stamped in the future has no trustworthy age: miss, not fresh.
cat >>"$cache_session/updates.jsonl" <<EOF
{"timestamp":"${today}T12:03:00Z","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"c4","usage":{"inputTokens":10,"outputTokens":0}}}}
EOF
touch -d "@$(( $(date +%s) + 3600 ))" "$cache_file"
result=$(HOME="$CACHE_HOME" XDG_CACHE_HOME="$CACHE_HOME/.cache" XDG_DATA_HOME="$CACHE_HOME/.local/share" \
  GROK_HOME="$CACHE_HOME/.grok" PATH="$(dirname "$jq_bin"):/usr/bin:/bin" \
  "$ROOT/bin/omarchy-agent-usage-grok" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "35" ]] ||
  fail "Grok collector treats a future-dated cache as a miss" "$result"
pass "Grok collector treats a future-dated cache as a miss"

# XDG_CACHE_HOME as a regular file makes mkdir fail; still print the record.
UNWRITABLE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$PI_HOME" "$OPENCODE_HOME" "$INTERRUPTED_HOME" "$CACHE_HOME" "$UNWRITABLE_HOME"' EXIT
unwritable_session="$UNWRITABLE_HOME/.grok/sessions/%2Ftmp/unwritable-session"
mkdir -p "$unwritable_session"
cat >"$unwritable_session/summary.json" <<'EOF'
{"info":{"id":"unwritable-session"}}
EOF
cat >"$unwritable_session/updates.jsonl" <<EOF
{"timestamp":"${today}T12:00:00Z","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"u1","usage":{"inputTokens":3,"outputTokens":0}}}}
EOF
touch "$UNWRITABLE_HOME/not-a-dir"
result=$(HOME="$UNWRITABLE_HOME" XDG_CACHE_HOME="$UNWRITABLE_HOME/not-a-dir" XDG_DATA_HOME="$UNWRITABLE_HOME/.local/share" \
  GROK_HOME="$UNWRITABLE_HOME/.grok" PATH="$(dirname "$jq_bin"):/usr/bin:/bin" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "3" ]] ||
  fail "Grok collector still prints a complete record when the cache is unwritable" "$result"
pass "Grok collector still prints a complete record when the cache is unwritable"

# Inconsistent ledger: cache larger than input. Clamp input to 0 so the four
# buckets stay exclusive, the same way Codex uses max(0, input - cache).
CLAMP_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$PI_HOME" "$OPENCODE_HOME" "$INTERRUPTED_HOME" "$CACHE_HOME" "$UNWRITABLE_HOME" "$CLAMP_HOME"' EXIT
clamp_session="$CLAMP_HOME/.grok/sessions/%2Ftmp/clamp-session"
mkdir -p "$clamp_session"
cat >"$clamp_session/summary.json" <<'EOF'
{"info":{"id":"clamp-session"},"current_model_id":"grok-4.6"}
EOF
cat >"$clamp_session/updates.jsonl" <<EOF
{"timestamp":"${today}T12:00:00Z","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"clamp-1","usage":{"inputTokens":10,"outputTokens":5,"cachedReadTokens":60,"cacheCreationTokens":10}}}}
EOF
result=$(HOME="$CLAMP_HOME" XDG_CACHE_HOME="$CLAMP_HOME/.cache" XDG_DATA_HOME="$CLAMP_HOME/.local/share" \
  GROK_HOME="$CLAMP_HOME/.grok" PATH="$(dirname "$jq_bin"):/usr/bin:/bin" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -c '.modelUsage["grok"]' <<<"$result") == '{"cacheCreationInputTokens":10,"cacheReadInputTokens":60,"inputTokens":0,"outputTokens":5}' ]] ||
  fail "Grok collector clamps overlapping cache out of input" "$result"
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "75" ]] ||
  fail "Grok collector does not double-count cache when the ledger is inconsistent" "$result"
pass "Grok collector clamps overlapping cache out of input"

# pi rows that only have totalTokens still count, matching Claude/Codex.
PI_TOTAL_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME" "$PI_HOME" "$OPENCODE_HOME" "$INTERRUPTED_HOME" "$CACHE_HOME" "$UNWRITABLE_HOME" "$CLAMP_HOME" "$PI_TOTAL_HOME"' EXIT
mkdir -p "$PI_TOTAL_HOME/.pi/agent/sessions/project"
now_ms=$(python3 -c 'import time; print(int(time.time() * 1000))')
cat >"$PI_TOTAL_HOME/.pi/agent/sessions/project/pi.jsonl" <<EOF
{"type":"message","id":"pi-total","timestamp":$now_ms,"message":{"role":"assistant","provider":"xai","model":"grok-4.6","usage":{"totalTokens":40}}}
EOF
result=$(HOME="$PI_TOTAL_HOME" XDG_CACHE_HOME="$PI_TOTAL_HOME/.cache" XDG_DATA_HOME="$PI_TOTAL_HOME/.local/share" \
  GROK_HOME="$PI_TOTAL_HOME/.grok" PATH="$(dirname "$jq_bin"):/usr/bin:/bin" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "40" ]] ||
  fail "Grok collector counts pi totalTokens-only rows" "$result"
[[ $(jq -c '.modelUsage["grok-4.6"]' <<<"$result") == '{"cacheCreationInputTokens":0,"cacheReadInputTokens":0,"inputTokens":40,"outputTokens":0}' ]] ||
  fail "Grok collector files totalTokens-only pi rows as input" "$result"
pass "Grok collector counts pi totalTokens-only rows"
