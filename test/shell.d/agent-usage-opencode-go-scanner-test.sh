#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# Create a mock curl that returns usage data
mkdir -p "$TEST_HOME/bin"
cat >"$TEST_HOME/bin/curl" <<'MOCK_CURL'
#!/bin/bash
# Mock curl for testing - returns usage data when called with the right URL
for arg in "$@"; do
  if [[ "$arg" == *"opencode.ai/zen/go/v1/usage"* ]]; then
    echo '{"usage":{"rolling":{"status":"ok","percent":0,"resetsAt":"2026-08-29T01:29:11Z"},"weekly":{"status":"ok","percent":22,"resetsAt":"2026-08-31T00:00:00Z"},"monthly":{"status":"ok","percent":96,"resetsAt":"2026-08-29T20:44:27Z"}}}'
    exit 0
  fi
done
exit 1
MOCK_CURL
chmod +x "$TEST_HOME/bin/curl"

# Create a mock curl that simulates API failure
cat >"$TEST_HOME/bin/curl-fail" <<'MOCK_CURL'
#!/bin/bash
exit 1
MOCK_CURL
chmod +x "$TEST_HOME/bin/curl-fail"

# Test 1: No API key returns unavailable record
result=$(HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$PATH" \
  "$ROOT/bin/omarchy-agent-usage-opencode-go")

[[ $(jq -r '.ready' <<<"$result") == "false" ]] ||
  fail "No key: returns ready=false" "$result"
pass "No key: returns ready=false"

[[ $(jq -r '.usageStatusText' <<<"$result") == "OpenCode Go unavailable" ]] ||
  fail "No key: shows unavailable message" "$result"
pass "No key: shows unavailable message"

# Test 2: With API key returns usage data
mkdir -p "$TEST_HOME/.pi/agent"
cat >"$TEST_HOME/.pi/agent/auth.json" <<'EOF'
{"opencode-go": {"type": "api", "key": "test-key-123"}}
EOF

result=$(HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$PATH" \
  "$ROOT/bin/omarchy-agent-usage-opencode-go")

[[ $(jq -r '.ready' <<<"$result") == "true" ]] ||
  fail "With key: returns ready=true" "$result"
pass "With key: returns ready=true"

[[ $(jq -r '.tierLabel' <<<"$result") == "Go" ]] ||
  fail "With key: tierLabel is Go" "$result"
pass "With key: tierLabel is Go"

# Test 3: Limits are parsed correctly
limit_count=$(jq '.limits | length' <<<"$result")
[[ "$limit_count" == "3" ]] ||
  fail "Limits: returns 3 limits" "$result"
pass "Limits: returns 3 limits"

rolling=$(jq -r '.limits[] | select(.label == "Rolling (5h)") | .percent' <<<"$result")
[[ "$rolling" == "0" || "$rolling" == "0.0" ]] ||
  fail "Rolling limit: percent is 0" "$result"
pass "Rolling limit: percent is 0"

weekly=$(jq -r '.limits[] | select(.label == "Weekly (7-day)") | .percent' <<<"$result")
[[ "$weekly" == "0.22" ]] ||
  fail "Weekly limit: percent is 0.22" "$result"
pass "Weekly limit: percent is 0.22"

monthly=$(jq -r '.limits[] | select(.label == "Monthly") | .percent' <<<"$result")
[[ "$monthly" == "0.96" ]] ||
  fail "Monthly limit: percent is 0.96" "$result"
pass "Monthly limit: percent is 0.96"

# Test 4: scope and hasPromptStats are set correctly
scope=$(jq -r '.scope' <<<"$result")
[[ "$scope" == "account" ]] ||
  fail "Record: scope is account" "$result"
pass "Record: scope is account"

has_prompt_stats=$(jq -r '.hasPromptStats' <<<"$result")
[[ "$has_prompt_stats" == "false" ]] ||
  fail "Record: hasPromptStats is false" "$result"
pass "Record: hasPromptStats is false"

# Test 5: API failure returns error record
mv "$TEST_HOME/bin/curl" "$TEST_HOME/bin/curl-real"
mv "$TEST_HOME/bin/curl-fail" "$TEST_HOME/bin/curl"

result=$(HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$PATH" \
  "$ROOT/bin/omarchy-agent-usage-opencode-go")

[[ $(jq -r '.ready' <<<"$result") == "false" ]] ||
  fail "API failure: returns ready=false" "$result"
pass "API failure: returns ready=false"

[[ $(jq -r '.usageStatusText' <<<"$result") == "OpenCode Go unavailable" ]] ||
  fail "API failure: shows unavailable message" "$result"
pass "API failure: shows unavailable message"

# Test 6: JSON output is valid and compact
result=$(HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$PATH" \
  "$ROOT/bin/omarchy-agent-usage-opencode-go")

jq -e . <<<"$result" >/dev/null 2>&1 ||
  fail "Output: is valid JSON" "$result"
pass "Output: is valid JSON"

# Test 7: OpenCode Go provider detection
result=$(python3 -c "
import sys
sys.path.insert(0, '$ROOT/bin')
exec(open('$ROOT/bin/omarchy-agent-usage-opencode-go').read().split('def main')[0])
# Test provider detection
tests = [
    ({'provider': 'opencode-go'}, True),
    ({'providerID': 'openai', 'api': 'opencode'}, True),
    ({'provider': 'anthropic'}, False),
    ({}, False),
]
for entry, expected in tests:
    result = is_opencode_go_provider(entry)
    assert result == expected, f'Expected {expected} for {entry}, got {result}'
print('Provider detection OK')
")

[[ "$result" == "Provider detection OK" ]] ||
  fail "Provider detection: works correctly" "$result"
pass "Provider detection: works correctly"

# Test 8: OpenCode Go provider detection via providerID
result=$(python3 -c "
import sys
sys.path.insert(0, '$ROOT/bin')
exec(open('$ROOT/bin/omarchy-agent-usage-opencode-go').read().split('def main')[0])
# Test provider detection with providerID
entry = {'providerID': 'opencode-go', 'role': 'assistant'}
assert is_opencode_go_provider(entry) == True, 'providerID opencode-go should match'
entry = {'providerID': 'openai', 'api': 'opencode-go', 'role': 'assistant'}
assert is_opencode_go_provider(entry) == True, 'providerID openai with opencode api should match'
print('ProviderID detection OK')
")

[[ "$result" == "ProviderID detection OK" ]] ||
  fail "ProviderID detection: works correctly" "$result"
pass "ProviderID detection: works correctly"

# Test 9: Stats merging
result=$(python3 -c "
import sys
sys.path.insert(0, '$ROOT/bin')
exec(open('$ROOT/bin/omarchy-agent-usage-opencode-go').read().split('def main')[0])

api_stats = {
    'todayPrompts': 5,
    'todayTotalTokens': 1000,
    'totalPrompts': 100,
    'totalSessions': 10,
    'activeDates': ['2026-08-28'],
    'recentDays': [{'date': '2026-08-28', 'messageCount': 500}],
    'modelUsage': {'gpt-4': {'inputTokens': 500, 'outputTokens': 500, 'cacheReadInputTokens': 0, 'cacheCreationInputTokens': 0}},
    'todayTokensByModel': {'gpt-4': 1000},
}
local_stats = {
    'todayPrompts': 3,
    'todayTotalTokens': 600,
    'totalPrompts': 50,
    'totalSessions': 5,
    'activeDates': ['2026-08-27', '2026-08-28'],
    'recentDays': [{'date': '2026-08-27', 'messageCount': 200}, {'date': '2026-08-28', 'messageCount': 300}],
    'modelUsage': {'gpt-4': {'inputTokens': 300, 'outputTokens': 300, 'cacheReadInputTokens': 0, 'cacheCreationInputTokens': 0}},
    'todayTokensByModel': {'gpt-4': 600},
}
merged = merge_stats(api_stats, local_stats)
assert merged['todayPrompts'] == 5, f'Expected 5, got {merged[\"todayPrompts\"]}'
assert merged['todayTotalTokens'] == 1000, f'Expected 1000, got {merged[\"todayTotalTokens\"]}'
assert merged['totalPrompts'] == 100, f'Expected 100, got {merged[\"totalPrompts\"]}'
assert len(merged['activeDates']) == 2, f'Expected 2 active dates, got {len(merged[\"activeDates\"])}'
assert merged['modelUsage']['gpt-4']['inputTokens'] == 800, f'Expected 800 input tokens'
print('Stats merging OK')
")

[[ "$result" == "Stats merging OK" ]] ||
  fail "Stats merging: works correctly" "$result"
pass "Stats merging: works correctly"
