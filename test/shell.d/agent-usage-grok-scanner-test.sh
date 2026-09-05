#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq

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
pass "Grok collector maps nested turn_completed usage into panel buckets"

[[ $(jq -c '.limits' <<<"$result") == '[]' ]] ||
  fail "Grok collector leaves limits empty when grok is not on PATH" "$result"
[[ $(jq -r '.usageStatusText' <<<"$result") == "Grok unavailable" ]] ||
  fail "Grok collector reports missing grok binary" "$result"
pass "Grok collector leaves limits empty when grok is not on PATH"

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
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "196" ]] ||
  fail "Grok collector adds flat-ledger tokens" "$result"
pass "Grok collector counts flat event_name turn_completed rows"

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

EMPTY_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME"' EXIT
result=$(HOME="$EMPTY_HOME" XDG_CACHE_HOME="$EMPTY_HOME/.cache" GROK_HOME="$EMPTY_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '(.id) + "/" + (.totalSessions|tostring) + "/" + .authHelpText' <<<"$result") == "grok/0/Run \`grok login\` to sign in." ]] ||
  fail "Grok collector reports an empty install" "$result"
pass "Grok collector reports an empty install"

install_grok_stub '{"config":{"creditUsagePercent":31,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-08-22T23:23:37.992320+00:00"},"prepaidBalance":{"val":0},"onDemandCap":{"val":0},"onDemandUsed":{"val":0}},"subscription_tier":"SuperGrok Heavy"}'
result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.tierLabel' <<<"$result") == "SuperGrok Heavy" ]] ||
  fail "Grok collector uses the ACP plan display string" "$result"
[[ $(jq -r '.limits[0].label' <<<"$result") == "Weekly" ]] ||
  fail "Grok collector labels a weekly pool Weekly" "$result"
[[ $(jq -r '.limits[0].percent * 100 | round' <<<"$result") == "31" ]] ||
  fail "Grok collector maps creditUsagePercent 0-100 onto the panel meter" "$result"
[[ $(jq 'has("balance")' <<<"$result") == "false" ]] ||
  fail "Grok collector omits a zero prepaid ledger" "$result"
pass "Grok collector maps a SuperGrok weekly pool onto the panel meter"

install_grok_stub '{"config":{"creditUsagePercent":8,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY","end":"2026-09-01T00:00:00+00:00"}},"subscriptionTier":"SuperGrokPro"}'
result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.tierLabel + "/" + .limits[0].label' <<<"$result") == "SuperGrok Pro/Monthly" ]] ||
  fail "Grok collector rewrites SuperGrokPro and labels monthly pools" "$result"
pass "Grok collector rewrites SuperGrokPro and labels monthly pools"

install_grok_stub '{"config":{"creditUsagePercent":10,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-08-29T00:00:00Z"},"prepaidBalance":{"val":12.5},"onDemandCap":{"val":20},"onDemandUsed":{"val":5}},"subscription_tier":"SuperGrok Heavy"}'
result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq '.balance.remaining == 27.5 and .balance.funded == 32.5 and .balance.spent == 5' <<<"$result") == "true" ]] ||
  fail "Grok collector adds prepaid leftover to unused on-demand cap" "$result"
pass "Grok collector reports leftover prepaid credits as a balance"

install_grok_stub '{"config":{},"subscription_tier":"SuperGrok Heavy"}'
result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.tierLabel' <<<"$result") == "SuperGrok Heavy" ]] ||
  fail "Grok collector keeps the plan label without a usage percent" "$result"
[[ $(jq -c '.limits' <<<"$result") == '[]' ]] ||
  fail "Grok collector does not invent a meter without creditUsagePercent" "$result"
pass "Grok collector does not invent a meter without creditUsagePercent"
