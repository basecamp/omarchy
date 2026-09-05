#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

DATA_DIR="$TEST_HOME/antigravity-cli"
mkdir -p "$DATA_DIR" "$TEST_HOME/bin"

# Local-day math must be deterministic regardless of where the suite runs.
export TZ=UTC
today=$(date -u +%F)
yesterday=$(date -u -d 'yesterday' +%F)
today_ms=$(date -u -d "$today 12:00:00" +%s000)
yesterday_ms=$(date -u -d "$yesterday 12:00:00" +%s000)

cat >"$DATA_DIR/history.jsonl" <<EOF
{"display":"today one","timestamp":$today_ms,"workspace":"/w"}
{"display":"today two","timestamp":$today_ms,"workspace":"/w"}
{"display":"yesterday","timestamp":$yesterday_ms,"workspace":"/w"}
not even json
EOF

python3 - "$DATA_DIR/conversation_summaries.db" "$today_ms" "$yesterday_ms" <<'PY'
import sqlite3
import sys

db_path, today_ms, yesterday_ms = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
conn = sqlite3.connect(db_path)
conn.execute("CREATE TABLE conversation_summaries (conversation_id TEXT, last_modified_time INTEGER, not_fully_idle INTEGER)")
conn.execute("INSERT INTO conversation_summaries VALUES ('a', ?, 0)", (today_ms,))
conn.execute("INSERT INTO conversation_summaries VALUES ('b', ?, 0)", (yesterday_ms,))
conn.commit()
conn.close()
PY

cat >"$TEST_HOME/bin/agy" <<'EOF'
#!/bin/bash
cat <<'JSON'
{"command":{"data":{"groups":[
  {"name":"Gemini Models","buckets":[
    {"id":"gemini-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.925,"reset_time":"2026-09-03T20:12:05Z"},
    {"id":"gemini-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":0.995,"reset_time":"2026-08-30T22:15:32Z"}
  ]},
  {"name":"Claude and GPT models","buckets":[
    {"id":"3p-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":1,"reset_time":"2026-09-06T17:25:01Z"}
  ]}
]}}}
JSON
EOF
chmod +x "$TEST_HOME/bin/agy"

result=$(HOME="$TEST_HOME" ANTIGRAVITY_DATA_DIR="$DATA_DIR" PATH="$TEST_HOME/bin:$PATH" TZ=UTC \
  "$ROOT/bin/omarchy-agent-usage-antigravity")

[[ $(jq -c '{id, ready, hasLocalStats, todayPrompts, totalPrompts, todaySessions, totalSessions, activeDays}' <<<"$result") \
  == '{"id":"antigravity","ready":true,"hasLocalStats":true,"todayPrompts":2,"totalPrompts":3,"todaySessions":1,"totalSessions":2,"activeDays":2}' ]] ||
  fail "Antigravity collector counts prompts and sessions from local files" "$result"
pass "Antigravity collector counts prompts and sessions from local files"

[[ $(jq -r ".recentDays[-1] | .date == \"$today\" and .messageCount == 2" <<<"$result") == "true" ]] ||
  fail "Antigravity collector places today's prompts on the last day of the week" "$result"
pass "Antigravity collector places today's prompts on the last day of the week"

[[ $(jq -c '.limits' <<<"$result") == '[{"label":"Gemini Models — Weekly","title":"Gemini Models — Weekly","percent":0.075,"resetsAt":"2026-09-03T20:12:05Z"},{"label":"Gemini Models — Session (5-hour)","title":"Gemini Models — Session (5-hour)","percent":0.005,"resetsAt":"2026-08-30T22:15:32Z"},{"label":"Claude and GPT models — Weekly","title":"Claude and GPT models — Weekly","percent":0.0,"resetsAt":"2026-09-06T17:25:01Z"}]' ]] ||
  fail "Antigravity collector inverts remaining_fraction into percent used and drops 'Remaining' from the label" "$result"
pass "Antigravity collector inverts remaining_fraction into percent used and drops 'Remaining' from the label"

# Without agy on PATH, stats still ship -- the collector shouldn't go dark
# just because the CLI that provides limits is missing.
no_agy=$(HOME="$TEST_HOME" ANTIGRAVITY_DATA_DIR="$DATA_DIR" PATH="/usr/bin:/bin" TZ=UTC \
  "$ROOT/bin/omarchy-agent-usage-antigravity")

[[ $(jq -c '{ready, limits, totalPrompts} + {authHelpTextSet: (.authHelpText | length > 0)}' <<<"$no_agy") \
  == '{"ready":true,"limits":[],"totalPrompts":3,"authHelpTextSet":true}' ]] ||
  fail "Antigravity collector keeps local stats when agy is not installed" "$no_agy"
pass "Antigravity collector keeps local stats when agy is not installed"

# A non-zero exit (e.g. not signed in) must not crash the collector.
cat >"$TEST_HOME/bin/agy" <<'EOF'
#!/bin/bash
echo "not signed in" >&2
exit 1
EOF
chmod +x "$TEST_HOME/bin/agy"

signed_out=$(HOME="$TEST_HOME" ANTIGRAVITY_DATA_DIR="$DATA_DIR" PATH="$TEST_HOME/bin:$PATH" TZ=UTC \
  "$ROOT/bin/omarchy-agent-usage-antigravity")

[[ $(jq -c '{limits, usageStatusText}' <<<"$signed_out") == '{"limits":[],"usageStatusText":"Antigravity limits unavailable"}' ]] ||
  fail "Antigravity collector handles a failed agy invocation without crashing" "$signed_out"
pass "Antigravity collector handles a failed agy invocation without crashing"

# No data directory at all (agy never run on this machine).
empty=$(HOME="$TEST_HOME" ANTIGRAVITY_DATA_DIR="$TEST_HOME/no-such-dir" PATH="/usr/bin:/bin" TZ=UTC \
  "$ROOT/bin/omarchy-agent-usage-antigravity")

[[ $(jq -c '{ready, totalPrompts, totalSessions, "recentDaysCount": (.recentDays | length)}' <<<"$empty") \
  == '{"ready":false,"totalPrompts":0,"totalSessions":0,"recentDaysCount":7}' ]] ||
  fail "Antigravity collector prints a full record with no data directory" "$empty"
pass "Antigravity collector prints a full record with no data directory"
