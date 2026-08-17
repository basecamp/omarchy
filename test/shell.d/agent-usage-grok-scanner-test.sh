#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

today="$(date +%Y-%m-%d)"
session_dir="$TEST_HOME/.grok/sessions/%2Fhome%2Fnick%2FWork/01a00c12-f7c9-7413-81bb-a18404c10c70"
mkdir -p "$session_dir"

cat >"$session_dir/summary.json" <<EOF
{
  "info": {"id": "01a00c12-f7c9-7413-81bb-a18404c10c70", "cwd": "/home/nick/Work"},
  "current_model_id": "grok-4.6",
  "created_at": "${today}T12:00:00Z",
  "updated_at": "${today}T15:00:00Z",
  "last_active_at": "${today}T15:00:00Z"
}
EOF

cat >"$session_dir/events.jsonl" <<EOF
{"ts":"${today}T12:00:00Z","type":"turn_started","turn_number":0,"model_id":"grok-4.6"}
{"ts":"${today}T12:01:00Z","type":"turn_ended","outcome":"completed"}
{"ts":"${today}T13:00:00Z","type":"turn_started","turn_number":1,"model_id":"grok-4.6"}
{"ts":"${today}T13:01:00Z","type":"turn_ended","outcome":"completed"}
{"ts":"${today}T13:01:01Z","type":"phase_changed","phase":"streaming_text"}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.id + "/" + (.todayPrompts|tostring) + "/" + (.todaySessions|tostring)' <<<"$result") == "grok/2/1" ]] ||
  fail "Grok collector counts turn_started events as prompts" "$result"
pass "Grok collector counts turn_started events as prompts"

[[ $(jq -r '.totalSessions' <<<"$result") == "1" ]] ||
  fail "Grok collector counts each session directory once" "$result"
pass "Grok collector counts each session directory once"

[[ $(jq -c '.limits' <<<"$result") == '[]' ]] ||
  fail "Grok collector has no rate-limit endpoint" "$result"
pass "Grok collector has no rate-limit endpoint"

# A second session with only chat_history (no events) still counts.
other="$TEST_HOME/.grok/sessions/%2Fhome%2Fnick/01a00c19-41c2-79d3-b0be-58670756fcb2"
mkdir -p "$other"
cat >"$other/summary.json" <<EOF
{
  "info": {"id": "01a00c19-41c2-79d3-b0be-58670756fcb2", "cwd": "/home/nick"},
  "current_model_id": "grok-4.6",
  "last_active_at": "${today}T16:00:00Z"
}
EOF
cat >"$other/chat_history.jsonl" <<'EOF'
{"type":"user","prompt_index":0,"content":[{"type":"text","text":"hello"}]}
{"type":"assistant","content":"hi"}
{"type":"user","prompt_index":1,"content":[{"type":"text","text":"again"}]}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '(.totalSessions|tostring) + "/" + (.totalPrompts|tostring)' <<<"$result") == "2/4" ]] ||
  fail "Grok collector falls back to chat_history user lines" "$result"
pass "Grok collector falls back to chat_history user lines"

# GROK_HOME points at an empty tree: valid empty record, not a crash.
EMPTY_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$EMPTY_HOME"' EXIT
result=$(HOME="$EMPTY_HOME" XDG_CACHE_HOME="$EMPTY_HOME/.cache" GROK_HOME="$EMPTY_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '(.id) + "/" + (.totalSessions|tostring) + "/" + .authHelpText' <<<"$result") == "grok/0/Run \`grok login\` to sign in." ]] ||
  fail "Grok collector reports an empty install" "$result"
pass "Grok collector reports an empty install"

# Embedded usage objects, if a future CLI writes them, must be counted once.
usage_session="$TEST_HOME/.grok/sessions/%2Ftmp/usage-session"
mkdir -p "$usage_session"
cat >"$usage_session/summary.json" <<EOF
{"info":{"id":"usage-session"},"current_model_id":"grok-4.6","last_active_at":"${today}T17:00:00Z"}
EOF
cat >"$usage_session/chat_history.jsonl" <<EOF
{"type":"assistant","model_id":"grok-4.6","timestamp":"${today}T17:00:00Z","usage":{"input_tokens":10,"output_tokens":4,"reasoning_tokens":2,"cache_read_input_tokens":3}}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" GROK_HOME="$TEST_HOME/.grok" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "19" ]] ||
  fail "Grok collector counts embedded usage when present" "$result"
[[ $(jq -c '.modelUsage["grok-4.6"]' <<<"$result") == '{"cacheCreationInputTokens":0,"cacheReadInputTokens":3,"inputTokens":10,"outputTokens":6}' ]] ||
  fail "Grok collector folds reasoning tokens into output" "$result"
pass "Grok collector counts embedded usage when present"
