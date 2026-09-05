#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

timestamp="$(date +%Y-%m-%d)T12:00:00Z"

# 1. Pi and omp session transcripts for Gemini/Antigravity providers
mkdir -p "$TEST_HOME/.pi/agent/sessions/project" "$TEST_HOME/.omp/agent/sessions/project"

cat >"$TEST_HOME/.pi/agent/sessions/project/pi.jsonl" <<EOF
{"type":"message","id":"pi-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"google","model":"google-antigravity/gemini-2.5-pro","usage":{"input":100,"output":50,"cacheRead":25,"cacheWrite":10,"totalTokens":185}}}
EOF

cat >"$TEST_HOME/.omp/agent/sessions/project/omp.jsonl" <<EOF
{"type":"message","id":"omp-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"google-antigravity","model":"gemini-2.5-flash","usage":{"input":200,"output":80,"cacheRead":40,"cacheWrite":20,"totalTokens":340}}}
{"type":"message","id":"other-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"anthropic","model":"claude-3-5-sonnet","usage":{"input":999,"output":999}}}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_STATE_HOME="$TEST_HOME/.local/state" \
  "$ROOT/bin/omarchy-agent-usage-gemini")

[[ $(jq -r '.id' <<<"$result") == "gemini" ]] ||
  fail "Gemini collector identifies itself with id gemini" "$result"
pass "Gemini collector identifies itself with id gemini"

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "525" ]] ||
[[ $(jq -r '.modelUsage["gemini-2.5-pro"].inputTokens' <<<"$result") == "100" && \
   $(jq -r '.modelUsage["gemini-2.5-pro"].outputTokens' <<<"$result") == "50" && \
   $(jq -r '.modelUsage["gemini-2.5-pro"].cacheReadInputTokens' <<<"$result") == "25" && \
   $(jq -r '.modelUsage["gemini-2.5-pro"].cacheCreationInputTokens' <<<"$result") == "10" ]] ||
  fail "Gemini collector strips provider prefixes and records per-model token buckets" "$result"
pass "Gemini collector strips provider prefixes and records per-model token buckets"

# 2. Antigravity CLI history scanning
mkdir -p "$TEST_HOME/.gemini/antigravity-cli"
cat >"$TEST_HOME/.gemini/antigravity-cli/history.jsonl" <<EOF
{"timestamp":"$timestamp","query":"explain quickshell"}
EOF

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_STATE_HOME="$TEST_HOME/.local/state" \
  "$ROOT/bin/omarchy-agent-usage-gemini" --force)

[[ $(jq -r '.totalPrompts' <<<"$result") == "3" ]] ||
  fail "Gemini collector counts prompts from antigravity CLI history" "$result"
pass "Gemini collector counts prompts from antigravity CLI history"

# 3. Opencode SQLite database scanning
OPENCODE_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OPENCODE_HOME"' EXIT
mkdir -p "$OPENCODE_HOME/.local/share/opencode"

python3 - "$OPENCODE_HOME/.local/share/opencode/opencode.db" <<'PY'
import json
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE message (session_id TEXT, data TEXT)")

conn.execute(
  "INSERT INTO message VALUES (?, ?)",
  (
    "sess-1",
    json.dumps({
      "role": "assistant",
      "providerID": "google",
      "modelID": "gemini-2.5-flash",
      "tokens": {
        "input": 300,
        "output": 120,
        "reasoning": 30,
        "cache": {"read": 50, "write": 20},
      },
    }),
  ),
)

conn.execute(
  "INSERT INTO message VALUES (?, ?)",
  (
    "sess-2",
    json.dumps({
      "role": "assistant",
      "providerID": "anthropic",
      "modelID": "claude-3-7-sonnet",
      "tokens": {"input": 500, "output": 200},
    }),
  ),
)

conn.commit()
conn.close()
PY

result=$(HOME="$OPENCODE_HOME" XDG_CACHE_HOME="$OPENCODE_HOME/.cache" XDG_DATA_HOME="$OPENCODE_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-gemini" --force)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "520" ]] ||
  fail "Gemini collector counts tokens from opencode database including reasoning" "$result"
pass "Gemini collector counts tokens from opencode database including reasoning"

# 4. Cache behavior with --limits-only and --force
result=$(HOME="$OPENCODE_HOME" XDG_CACHE_HOME="$OPENCODE_HOME/.cache" XDG_DATA_HOME="$OPENCODE_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-gemini" --limits-only)

[[ $(jq -r '.todayTotalTokens' <<<"$result") == "520" ]] ||
  fail "Gemini collector reuses cached scan data on --limits-only" "$result"
pass "Gemini collector reuses cached scan data on --limits-only"

# 5. Plan tier detection
python3 - "$ROOT/bin/omarchy-agent-usage-gemini" <<'PY' || fail "Gemini plan tier parser maps subscription tiers accurately"
import sys
from importlib.machinery import SourceFileLoader

mod = SourceFileLoader("gemini_usage", sys.argv[1]).load_module()
assert mod.plan_label({"paidTier": {"id": "g1-pro-tier", "name": "Google AI Pro"}}) == "Pro"
assert mod.plan_label({"paidTier": {"id": "g1-ultra-tier", "name": "Google AI Ultra"}}) == "Ultra"
assert mod.plan_label({"currentTier": {"id": "standard-tier", "name": "Antigravity"}}) == "Standard"
assert mod.plan_label({"currentTier": {"id": "free-tier", "name": "Antigravity"}}) == "Free"
assert mod.plan_label({}) == "Free"
PY
pass "Gemini plan tier parser maps subscription tiers accurately"
