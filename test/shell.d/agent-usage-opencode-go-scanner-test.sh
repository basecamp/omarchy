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

# Test 4: API failure returns error record
# Replace curl with failing version
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

# Test 5: JSON output is valid and compact
result=$(HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$PATH" \
  "$ROOT/bin/omarchy-agent-usage-opencode-go")

# Should be valid JSON
jq -e . <<<"$result" >/dev/null 2>&1 ||
  fail "Output: is valid JSON" "$result"
pass "Output: is valid JSON"

# Should be compact (no newlines within the JSON content)
json_content=$(echo "$result" | tr -d '\n')
if echo "$json_content" | grep -q '\\n'; then
  fail "Output: is compact JSON"
else
  pass "Output: is compact JSON"
fi
