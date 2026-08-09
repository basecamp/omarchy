#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# The scanner only buckets the trailing 7 days, so the fixture day must be
# today for the day-row assertions to hold.
DAY=$(date +%Y-%m-%d)
YDAY=$(date -d "1 day ago" +%Y-%m-%d)

# Fake opencode CLI: answers the `db` query the collector makes with CLI-only
# session usage. Rows carry a route (from providerID), a model, and session
# ids, exactly like the real query returns.
#
#   - ses-cli-1 today: Zen row (route "zen")
#   - ses-cli-2 today: Go row (route "go")
#   - ses-cli-3 today: BYOK/unattributed (route ""), merged-only
#   - ses-cli-1 yesterday: legacy/unattributed (route ""), merged-only
#     ses-cli-1 appears on two days but must still count as one session
mkdir -p "$TEST_HOME/bin"
cat >"$TEST_HOME/bin/opencode" <<SCRIPT
#!/bin/bash
if [[ \$1 == "db" ]]; then
  cat <<'JSON'
[
  {
    "day": "$DAY",
    "route": "zen",
    "model": "claude-sonnet-4.2-lite",
    "session_ids": "ses-cli-1",
    "input": 2000,
    "output": 500,
    "reasoning": 250,
    "cache_read": 1000,
    "cache_write": 0
  },
  {
    "day": "$DAY",
    "route": "go",
    "model": "kimi-k2.6",
    "session_ids": "ses-cli-2",
    "input": 100,
    "output": 50,
    "reasoning": 0,
    "cache_read": 0,
    "cache_write": 0
  },
  {
    "day": "$DAY",
    "route": "",
    "model": "gpt-direct",
    "session_ids": "ses-cli-3",
    "input": 400,
    "output": 0,
    "reasoning": 0,
    "cache_read": 0,
    "cache_write": 0
  },
  {
    "day": "$YDAY",
    "route": "",
    "model": "",
    "session_ids": "ses-cli-1",
    "input": 100,
    "output": 0,
    "reasoning": 0,
    "cache_read": 0,
    "cache_write": 0
  }
]
JSON
  exit 0
fi
exit 1
SCRIPT
chmod +x "$TEST_HOME/bin/opencode"

# Pi transcripts: a Zen session and a Go session, each with one assistant
# message carrying per-route usage. Timestamps must be local so they stay on
# DAY in any timezone.
ZEN_T0=$(date +%Y-%m-%dT10:00:00%:z)
ZEN_T1=$(date +%Y-%m-%dT10:00:01%:z)
GO_T0=$(date +%Y-%m-%dT11:00:00%:z)
GO_T1=$(date +%Y-%m-%dT11:00:01%:z)
mkdir -p "$TEST_HOME/.pi/agent/sessions/Projects-demo"
cat >"$TEST_HOME/.pi/agent/sessions/Projects-demo/zen.jsonl" <<EOF
{"type":"session","version":3,"id":"zen-ses","timestamp":"$ZEN_T0","cwd":"/demo"}
{"type":"message","id":"m1","timestamp":"$ZEN_T1","message":{"role":"assistant","provider":"opencode","model":"gpt-5.6-luna","usage":{"input":100,"output":50,"cacheRead":0,"cacheWrite":400,"totalTokens":550,"cost":{"total":0.001}}}}
EOF
cat >"$TEST_HOME/.pi/agent/sessions/Projects-demo/go.jsonl" <<EOF
{"type":"session","version":3,"id":"go-ses","timestamp":"$GO_T0","cwd":"/demo"}
{"type":"message","id":"m2","timestamp":"$GO_T1","message":{"role":"assistant","provider":"opencode-go","model":"kimi-k2.7-code","usage":{"input":300,"output":100,"cacheRead":0,"cacheWrite":0,"totalTokens":400,"cost":{"total":0.002}}}}
EOF

BASE="$ROOT/bin/opencode-usage-base.py"

# ---------------------------------------------------------------------------
# Standard contract fields

run_zen() {
  HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$PATH" python3 "$BASE" --route zen
}

run_go() {
  HOME="$TEST_HOME" PATH="$TEST_HOME/bin:$PATH" python3 "$BASE" --route go
}

result_zen=$(run_zen)
result_go=$(run_go)

# Both records must be valid JSON with the standard contract fields.
jq -e . >/dev/null 2>&1 <<<"$result_zen" ||
  fail "Zen record is valid JSON" "$result_zen"
pass "Zen record is valid JSON"

jq -e . >/dev/null 2>&1 <<<"$result_go" ||
  fail "Go record is valid JSON" "$result_go"
pass "Go record is valid JSON"

[[ $(jq -r '.schemaVersion' <<<"$result_zen") == "1" ]] ||
  fail "Zen record has schemaVersion" "$result_zen"
pass "Zen record has schemaVersion"

[[ $(jq -r '.id' <<<"$result_zen") == "opencode-zen" ]] ||
  fail "Zen record has correct id" "$result_zen"
pass "Zen record has correct id"

[[ $(jq -r '.id' <<<"$result_go") == "opencode-go" ]] ||
  fail "Go record has correct id" "$result_go"
pass "Go record has correct id"

[[ $(jq -r '.name' <<<"$result_zen") == "OpenCode Zen" ]] ||
  fail "Zen record has correct name" "$result_zen"
pass "Zen record has correct name"

[[ $(jq -r '.name' <<<"$result_go") == "OpenCode Go" ]] ||
  fail "Go record has correct name" "$result_go"
pass "Go record has correct name"

[[ $(jq -r '.tierLabel' <<<"$result_zen") == "API" ]] ||
  fail "Zen record has API tier label" "$result_zen"
pass "Zen record has API tier label"

[[ $(jq -r '.tierLabel' <<<"$result_go") == "Subscription" ]] ||
  fail "Go record has Subscription tier label" "$result_go"
pass "Go record has Subscription tier label"

[[ $(jq -r '.ready' <<<"$result_zen") == "true" ]] ||
  fail "Zen record reports ready" "$result_zen"
pass "Zen record reports ready"

[[ $(jq -r '.hasLocalStats' <<<"$result_zen") == "true" ]] ||
  fail "Zen record has local stats" "$result_zen"
pass "Zen record has local stats"

[[ $(jq -r '.hasPromptStats' <<<"$result_zen") == "true" ]] ||
  fail "Zen record has prompt stats" "$result_zen"
pass "Zen record has prompt stats"

# No routeData field — the old scanner's extension is not present.
[[ $(jq 'has("routeData")' <<<"$result_zen") == "false" ]] ||
  fail "Zen record has no routeData field" "$result_zen"
pass "Zen record has no routeData field"

# Limits are empty (no OpenCode API for rate limits).
[[ $(jq '.limits | length' <<<"$result_zen") == "0" ]] ||
  fail "Zen record has empty limits" "$result_zen"
pass "Zen record has empty limits"

# retryAdvised is false (no limits endpoint to retry).
[[ $(jq -r '.retryAdvised' <<<"$result_zen") == "false" ]] ||
  fail "Zen record has retryAdvised false" "$result_zen"
pass "Zen record has retryAdvised false"

# ---------------------------------------------------------------------------
# Zen route totals

# Zen today: Pi zen (550) + CLI zen (2000+500+250+1000 = 3750) = 4300
zen_today=$(jq -r --arg d "$DAY" '.recentDays[] | select(.date == $d) | .messageCount' <<<"$result_zen")
[[ $zen_today == "4300" ]] ||
  fail "Zen record totals Pi + CLI tokens by day" "$result_zen"
pass "Zen record totals Pi + CLI tokens by day"

# Sessions: 1 Pi session (zen-ses) + 1 CLI session (ses-cli-1) = 2
[[ $(jq -r '.totalSessions' <<<"$result_zen") == "2" ]] ||
  fail "Zen record counts Pi + CLI sessions" "$result_zen"
pass "Zen record counts Pi + CLI sessions"

# Prompts: Pi assistant messages only (CLI sessions are not prompts)
[[ $(jq -r '.totalPrompts' <<<"$result_zen") == "1" ]] ||
  fail "Zen record counts Pi messages as prompts" "$result_zen"
pass "Zen record counts Pi messages as prompts"

# activeDates: only today (BYOK-only yesterday is excluded)
[[ $(jq -r '.activeDays' <<<"$result_zen") == "1" ]] ||
  fail "Zen record has 1 active day" "$result_zen"
pass "Zen record has 1 active day"

# Zen model: Pi gpt-5.6-luna (100 input + 50 output + 400 cache = 550 total)
[[ $(jq -r '.modelUsage["gpt-5.6-luna"].inputTokens' <<<"$result_zen") == "100" ]] ||
  fail "Zen model tracks Pi input tokens" "$result_zen"
pass "Zen model tracks Pi input tokens"

# Reasoning folds into model output: CLI 500 + 250 reasoning = 750 output
[[ $(jq -r '.modelUsage["claude-sonnet-4.2-lite"].outputTokens' <<<"$result_zen") == "750" ]] ||
  fail "Zen model folds CLI reasoning into output" "$result_zen"
pass "Zen model folds CLI reasoning into output"

# BYOK (gpt-direct) must never appear in Zen route.
[[ $(jq -r '.modelUsage["gpt-direct"]' <<<"$result_zen") == "null" ]] ||
  fail "Zen record excludes BYOK tokens" "$result_zen"
pass "Zen record excludes BYOK tokens"

# Go route (kimi-k2.6 CLI, kimi-k2.7-code Pi) must never appear in Zen.
[[ $(jq -r '.modelUsage["kimi-k2.6"]' <<<"$result_zen") == "null" ]] ||
  fail "Zen record excludes Go CLI tokens" "$result_zen"
pass "Zen record excludes Go CLI tokens"

[[ $(jq -r '.modelUsage["kimi-k2.7-code"]' <<<"$result_zen") == "null" ]] ||
  fail "Zen record excludes Go Pi tokens" "$result_zen"
pass "Zen record excludes Go Pi tokens"

# ---------------------------------------------------------------------------
# Go route totals

# Go today: Pi go (400) + CLI go (100+50 = 150) = 550
go_today=$(jq -r --arg d "$DAY" '.recentDays[] | select(.date == $d) | .messageCount' <<<"$result_go")
[[ $go_today == "550" ]] ||
  fail "Go record totals Pi + CLI tokens by day" "$result_go"
pass "Go record totals Pi + CLI tokens by day"

# Sessions: 1 Pi session (go-ses) + 1 CLI session (ses-cli-2) = 2
[[ $(jq -r '.totalSessions' <<<"$result_go") == "2" ]] ||
  fail "Go record counts Pi + CLI sessions" "$result_go"
pass "Go record counts Pi + CLI sessions"

# Prompts: Pi assistant messages only
[[ $(jq -r '.totalPrompts' <<<"$result_go") == "1" ]] ||
  fail "Go record counts Pi messages as prompts" "$result_go"
pass "Go record counts Pi messages as prompts"

# Go model: Pi kimi-k2.7-code (300 input + 100 output = 400 total)
[[ $(jq -r '.modelUsage["kimi-k2.7-code"].outputTokens' <<<"$result_go") == "100" ]] ||
  fail "Go model tracks Pi output tokens" "$result_go"
pass "Go model tracks Pi output tokens"

# BYOK (gpt-direct) must never appear in Go route.
[[ $(jq -r '.modelUsage["gpt-direct"]' <<<"$result_go") == "null" ]] ||
  fail "Go record excludes BYOK tokens" "$result_go"
pass "Go record excludes BYOK tokens"

# Zen models must never appear in Go route.
[[ $(jq -r '.modelUsage["gpt-5.6-luna"]' <<<"$result_go") == "null" ]] ||
  fail "Go record excludes Zen Pi tokens" "$result_go"
pass "Go record excludes Zen Pi tokens"

[[ $(jq -r '.modelUsage["claude-sonnet-4.2-lite"]' <<<"$result_go") == "null" ]] ||
  fail "Go record excludes Zen CLI tokens" "$result_go"
pass "Go record excludes Zen CLI tokens"

# ---------------------------------------------------------------------------
# Graceful degrade without the opencode CLI

result_no_cli=$(HOME="$TEST_HOME" PATH="/usr/bin:/bin:/usr/local/bin" \
  python3 "$BASE" --route zen)

[[ $(jq -r '.ready' <<<"$result_no_cli") == "true" ]] ||
  fail "Zen record works without opencode CLI" "$result_no_cli"
pass "Zen record works without opencode CLI"

# Without CLI, only Pi Zen tokens remain: 550 today.
no_cli_today=$(jq -r --arg d "$DAY" '.recentDays[] | select(.date == $d) | .messageCount' <<<"$result_no_cli")
[[ $no_cli_today == "550" ]] ||
  fail "Zen record falls back to Pi-only tokens without CLI" "$result_no_cli"
pass "Zen record falls back to Pi-only tokens without CLI"

# ---------------------------------------------------------------------------
# Panel marks resolve by provider id (assets/<id>.svg, plus a -light twin for
# light surfaces), so each route must ship the mark under its own id even
# though zen and go share one OpenCode brand mark.

require_command test

mark() {
  [[ -f "$ROOT/shell/plugins/agents/assets/$1" ]]
}

mark opencode-zen.svg ||
  fail "Zen panel mark exists at assets/opencode-zen.svg"
pass "Zen panel mark exists at assets/opencode-zen.svg"

mark opencode-zen-light.svg ||
  fail "Zen panel mark light twin exists at assets/opencode-zen-light.svg"
pass "Zen panel mark light twin exists at assets/opencode-zen-light.svg"

mark opencode-go.svg ||
  fail "Go panel mark exists at assets/opencode-go.svg"
pass "Go panel mark exists at assets/opencode-go.svg"

mark opencode-go-light.svg ||
  fail "Go panel mark light twin exists at assets/opencode-go-light.svg"
pass "Go panel mark light twin exists at assets/opencode-go-light.svg"
