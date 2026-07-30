#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.codex/sessions/$(date +%Y/%m/%d)" "$TEST_HOME/bin"

cat >"$TEST_HOME/bin/codex" <<'EOF'
#!/bin/bash

while read -r request; do
  id=$(jq -r '.id // empty' <<<"$request")
  method=$(jq -r '.method // empty' <<<"$request")

  case "$method" in
    initialize)
      jq -cn --argjson id "$id" '{id: $id, result: {}}'
      ;;
    account/read)
      jq -cn --argjson id "$id" '{id: $id, result: {account: {}}}'
      ;;
    account/rateLimits/read)
      jq -cn --argjson id "$id" '{id: $id, result: {rateLimits: {}}}'
      ;;
  esac
done
EOF
chmod +x "$TEST_HOME/bin/codex"

timestamp="$(date +%Y-%m-%d)T12:00:00Z"
session="$TEST_HOME/.codex/sessions/$(date +%Y/%m/%d)/rollout.jsonl"
cat >"$session" <<EOF
{"timestamp":"$timestamp","type":"turn_context","payload":{"model":"gpt-test"}}
{"timestamp":"$timestamp","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120},"last_token_usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120}}}}
{"timestamp":"$timestamp","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":180,"cached_input_tokens":110,"output_tokens":30,"reasoning_output_tokens":8,"total_tokens":210},"last_token_usage":{"input_tokens":80,"cached_input_tokens":50,"output_tokens":10,"reasoning_output_tokens":3,"total_tokens":90}}}}
EOF

result=$(HOME="$TEST_HOME" CODEX_HOME="$TEST_HOME/.codex" PATH="$TEST_HOME/bin:$PATH" \
  python3 "$ROOT/shell/plugins/model-usage/scripts/codex_usage_scanner.py")

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "210" ]] ||
  fail "Codex scanner counts each turn once" "$result"
pass "Codex scanner counts each turn once"

[[ $(jq -c '.modelUsage["gpt-test"]' <<<"$result") == '{"inputTokens":70,"outputTokens":30,"cacheReadInputTokens":110,"cacheCreationInputTokens":0}' ]] ||
  fail "Codex scanner does not double-count cache or reasoning tokens" "$result"
pass "Codex scanner does not double-count cache or reasoning tokens"
