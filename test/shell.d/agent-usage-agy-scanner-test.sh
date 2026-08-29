#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

brain_dir="$TEST_HOME/.gemini/antigravity-cli/brain/session-123/.system_generated/logs"
mkdir -p "$brain_dir"

timestamp="$(date +%Y-%m-%d)T12:00:00Z"
cat >"$brain_dir/transcript.jsonl" <<EOF
{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"$timestamp","content":"Hello from prompt 1"}
{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"$timestamp","content":"Here is a response","thinking":"Internal reasoning"}
