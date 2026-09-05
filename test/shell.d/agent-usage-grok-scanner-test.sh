#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

GROK_HOME="$TEST_HOME/.grok"
CACHE_HOME="$TEST_HOME/.cache"
export TZ=UTC

collect() {
  HOME="$TEST_HOME" GROK_HOME="$GROK_HOME" XDG_CACHE_HOME="$CACHE_HOME" \
    "$ROOT/bin/omarchy-agent-usage-grok" --force
}

# One turn_completed update, written the way the Grok CLI writes it. Callers
# pass the day offset so fixtures land on a date the record can be asserted
# against whenever the suite runs.
turn() {
  local session=$1 prompt=$2 days_ago=$3 model=$4 input=$5 output=$6 cache_read=$7
  local stamp
  stamp=$(date -d "$days_ago days ago" +%s)

  jq -nc \
    --arg session "$session" --arg prompt "$prompt" --arg model "$model" \
    --argjson stamp "$stamp" --argjson input "$input" \
    --argjson output "$output" --argjson cache_read "$cache_read" \
    '{
      timestamp: $stamp,
      method: "_x.ai/session/update",
      params: {
        sessionId: $session,
        update: {
          sessionUpdate: "turn_completed",
          prompt_id: $prompt,
          usage: {
            inputTokens: $input,
            outputTokens: $output,
            cachedReadTokens: $cache_read,
            cacheCreationTokens: 0,
            modelUsage: {
              ($model): {
                inputTokens: $input,
                outputTokens: $output,
                cachedReadTokens: $cache_read,
                cacheCreationTokens: 0
              }
            }
          }
        }
      }
    }'
}

write_session() {
  local session=$1
  local dir="$GROK_HOME/sessions/%2Fhome%2Fdev/$session"

  mkdir -p "$dir"
  cat >"$dir/updates.jsonl"
}

# An empty ~/.grok must still print a valid record. The panel hides an agent
# with no usage on its own, so the collector never needs to suppress itself.
mkdir -p "$GROK_HOME"
empty=$(collect)
[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + (.totalPrompts | tostring)' <<<"$empty") == "grok:true:0" ]] ||
  fail "Grok collector prints a valid record with no sessions" "$empty"
pass "Grok collector prints a valid record with no sessions"

# Two turns today plus one six days back, so the weekly chart, the model
# breakdown, and the today counters can all be checked at once.
{
  turn "session-a" "prompt-1" 0 "grok-4.6-build" 1000 100 600
  turn "session-a" "prompt-2" 0 "grok-4.6-build" 500 50 200
  turn "session-a" "prompt-3" 6 "grok-4.6" 300 30 100
} | write_session "session-a"

record=$(collect)

# Cache-read and cache-creation tokens are reported inside inputTokens, so the
# plain input bucket is what is left once they are removed: (1000-600) +
# (500-200) = 700 for the build model, 300-100 = 200 for the other.
[[ $(jq -r '.modelUsage["grok-4.6-build"] | "\(.inputTokens):\(.outputTokens):\(.cacheReadInputTokens)"' <<<"$record") == "700:150:800" ]] ||
  fail "Grok collector splits overlapping token buckets" "$record"
pass "Grok collector splits overlapping token buckets"

[[ $(jq -r '.modelUsage["grok-4.6"].inputTokens' <<<"$record") == "200" ]] ||
  fail "Grok collector keeps a second model in its own bucket" "$record"
pass "Grok collector keeps a second model in its own bucket"

# Today's two turns: (400+100+600) + (300+50+200) = 1650.
[[ $(jq -r '"\(.todayPrompts):\(.todaySessions):\(.todayTotalTokens)"' <<<"$record") == "2:1:1650" ]] ||
  fail "Grok collector counts today's prompts, sessions, and tokens" "$record"
pass "Grok collector counts today's prompts, sessions, and tokens"

[[ $(jq -r '.recentDays | length' <<<"$record") == "7" ]] &&
  [[ $(jq -r '.recentDays[-1].messageCount' <<<"$record") == "1650" ]] &&
  [[ $(jq -r '.recentDays[0].messageCount' <<<"$record") == "330" ]] ||
  fail "Grok collector fills the seven-day chart" "$record"
pass "Grok collector fills the seven-day chart"

[[ $(jq -r '"\(.totalPrompts):\(.totalSessions):\(.activeDays)"' <<<"$record") == "3:1:2" ]] ||
  fail "Grok collector totals prompts, sessions, and active days" "$record"
pass "Grok collector totals prompts, sessions, and active days"

# `grok --fork-session` replays a transcript under a new session id. The
# shared turns carry their original prompt ids, so they must not be counted a
# second time.
{
  turn "session-b" "prompt-1" 0 "grok-4.6-build" 1000 100 600
  turn "session-b" "prompt-4" 0 "grok-4.6-build" 10 5 0
} | write_session "session-b"

forked=$(collect)
[[ $(jq -r '"\(.totalPrompts):\(.todayTotalTokens)"' <<<"$forked") == "4:1665" ]] ||
  fail "Grok collector counts a forked session's replayed turns once" "$forked"
pass "Grok collector counts a forked session's replayed turns once"

# A turn that switched models mid-flight is still one prompt.
{
  turn "session-c" "prompt-5" 0 "grok-4.6" 100 10 0 |
    jq -c '.params.update.usage.modelUsage["grok-4.6-fast"] = {inputTokens: 20, outputTokens: 2, cachedReadTokens: 0, cacheCreationTokens: 0}'
} | write_session "session-c"

multi=$(collect)
[[ $(jq -r '.totalPrompts' <<<"$multi") == "5" ]] &&
  [[ $(jq -r '.modelUsage["grok-4.6-fast"].inputTokens' <<<"$multi") == "20" ]] ||
  fail "Grok collector counts a multi-model turn as one prompt" "$multi"
pass "Grok collector counts a multi-model turn as one prompt"

# Sessions untouched for longer than the scan window are skipped, which is
# what keeps a long-lived ~/.grok from being reread in full on every refresh.
turn "session-old" "prompt-old" 45 "grok-4.6" 900 90 0 | write_session "session-old"
touch -d "45 days ago" "$GROK_HOME/sessions/%2Fhome%2Fdev/session-old/updates.jsonl"

windowed=$(collect)
[[ $(jq -r '.totalPrompts' <<<"$windowed") == "5" ]] ||
  fail "Grok collector skips sessions outside the scan window" "$windowed"
pass "Grok collector skips sessions outside the scan window"

# A malformed line must not take the scan down with it.
printf 'not json at all\n{"params":{"update":{"sessionUpdate":"turn_completed"}}}\n' \
  >>"$GROK_HOME/sessions/%2Fhome%2Fdev/session-c/updates.jsonl"

survived=$(collect)
[[ $(jq -r '.totalPrompts' <<<"$survived") == "5" ]] ||
  fail "Grok collector survives malformed and usage-less lines" "$survived"
pass "Grok collector survives malformed and usage-less lines"
