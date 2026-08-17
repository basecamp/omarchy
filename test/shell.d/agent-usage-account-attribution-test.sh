#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3
require_command rg

CLAUDE_HOME=$(mktemp -d)
CODEX_HOME_FIXTURE=$(mktemp -d)
trap 'rm -rf "$CLAUDE_HOME" "$CODEX_HOME_FIXTURE"' EXIT

claude_root="$CLAUDE_HOME/.local/share/omarchy/agents/anthropic"
claude_usage="$CLAUDE_HOME/.local/state/omarchy/agents/usage"
claude_switches="$CLAUDE_HOME/.local/state/omarchy/agents/switches"
mkdir -p \
  "$claude_root/default/claude/projects/default" \
  "$claude_root/work/claude/projects/work" \
  "$CLAUDE_HOME/.pi/agent/sessions/project" \
  "$CLAUDE_HOME/.omp/agent/sessions/project" \
  "$claude_switches" \
  "$claude_usage"
ln -s "$claude_root/work/claude" "$CLAUDE_HOME/.claude"

cat >"$claude_root/default/claude/projects/default/native.jsonl" <<'EOF'
{"timestamp":"2024-01-03T12:00:00Z","type":"assistant","sessionId":"claude-default","message":{"id":"claude-default-1","role":"assistant","model":"claude-native","usage":{"input_tokens":23}}}
EOF
cat >"$claude_root/work/claude/projects/work/native.jsonl" <<'EOF'
{"timestamp":"2024-01-05T12:00:00Z","type":"assistant","sessionId":"claude-work","message":{"id":"claude-work-1","role":"assistant","model":"claude-native","usage":{"input_tokens":29}}}
EOF
cat >"$CLAUDE_HOME/.pi/agent/sessions/project/pi.jsonl" <<'EOF'
{"type":"message","id":"pi-before","timestamp":"2024-01-01T12:00:00Z","message":{"role":"assistant","provider":"anthropic","model":"claude-pi","usage":{"input":5}}}
{"type":"message","id":"pi-work","timestamp":"2024-01-05T12:00:00Z","message":{"role":"assistant","provider":"anthropic","model":"claude-pi","usage":{"input":11}}}
EOF
cat >"$CLAUDE_HOME/.omp/agent/sessions/project/omp.jsonl" <<'EOF'
{"type":"message","id":"omp-default","timestamp":"2024-01-03T12:00:00Z","message":{"role":"assistant","provider":"anthropic","model":"claude-omp","usage":{"input":7}}}
EOF
cat >"$claude_switches/anthropic.json" <<'EOF'
[
  {"timestamp":"2024-01-02T00:00:00Z","providerId":"anthropic","accountId":"default"},
  {"timestamp":"2024-01-04T00:00:00Z","providerId":"anthropic","accountId":"work"}
]
EOF

python3 - "$CLAUDE_HOME/.local/share/opencode/opencode.db" <<'PY'
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

db = Path(sys.argv[1])
db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")

def millis(value):
  return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000)

def message(message_id, timestamp, tokens):
  created = millis(timestamp)
  data = json.dumps({
    "role": "assistant",
    "providerID": "anthropic",
    "modelID": "claude-opencode",
    "tokens": {"input": tokens, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": created},
  })
  return message_id, message_id, created, created, data

conn.executemany("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [
  message("oc-before", "2024-01-01T12:00:00Z", 13),
  message("oc-default", "2024-01-03T12:00:00Z", 17),
  message("oc-work", "2024-01-05T12:00:00Z", 19),
])
conn.commit()
conn.close()
PY

printf '{"id":"claude"}\n' >"$claude_usage/claude.json"
printf '{"id":"anthropic@deleted"}\n' >"$claude_usage/anthropic@deleted.json"
printf '{"id":"codex"}\n' >"$claude_usage/codex.json"

HOME="$CLAUDE_HOME" \
  XDG_CACHE_HOME="$CLAUDE_HOME/.cache" \
  XDG_DATA_HOME="$CLAUDE_HOME/.local/share" \
  XDG_STATE_HOME="$CLAUDE_HOME/.local/state" \
  OMARCHY_PATH="$ROOT" \
  "$ROOT/bin/omarchy-agent-usage-update" claude --force

jq -e '
  .id == "anthropic@default" and
  .providerId == "anthropic" and
  .accountId == "default" and
  .accountLabel == "default" and
  (.accountActive | not) and
  .includesSharedSessions and
  .totalPrompts == 5 and
  ([.modelUsage[].inputTokens] | add) == 65
' "$claude_usage/anthropic@default.json" >/dev/null ||
  fail "Anthropic ledger attributes pre-ledger and default-era shared messages to the first account"
jq -e '
  .id == "anthropic@work" and
  .providerId == "anthropic" and
  .accountId == "work" and
  .accountActive and
  .includesSharedSessions and
  .totalPrompts == 3 and
  ([.modelUsage[].inputTokens] | add) == 59
' "$claude_usage/anthropic@work.json" >/dev/null ||
  fail "Anthropic ledger attributes later shared messages to the account active at their timestamp"
[[ ! -e $claude_usage/claude.json && ! -e $claude_usage/anthropic@deleted.json && -e $claude_usage/codex.json ]] ||
  fail "Anthropic refresh prunes only its stale and legacy records"
(( $(find "$CLAUDE_HOME/.cache/omarchy/agent-usage" -maxdepth 1 -name 'claude-pi-sessions-*.json' | wc -l) == 2 )) ||
  fail "Claude pi and omp caches are keyed per config directory"
(( $(find "$CLAUDE_HOME/.cache/omarchy/agent-usage" -maxdepth 1 -name 'claude-opencode-*.json' | wc -l) == 2 )) ||
  fail "Claude opencode caches are keyed per config directory"
pass "Anthropic shared sessions are attributed once across account records"

# A missing ledger cannot justify assigning global sources to every account.
# The active account gets the conservative fallback; the inactive one keeps
# only its native transcript usage.
rm "$claude_switches/anthropic.json"
HOME="$CLAUDE_HOME" \
  XDG_CACHE_HOME="$CLAUDE_HOME/.cache" \
  XDG_DATA_HOME="$CLAUDE_HOME/.local/share" \
  XDG_STATE_HOME="$CLAUDE_HOME/.local/state" \
  OMARCHY_PATH="$ROOT" \
  "$ROOT/bin/omarchy-agent-usage-update" anthropic --force

jq -e '.totalPrompts == 1 and ([.modelUsage[].inputTokens] | add) == 23 and (.includesSharedSessions | not)' \
  "$claude_usage/anthropic@default.json" >/dev/null ||
  fail "Missing Anthropic ledger leaves shared usage off inactive accounts"
jq -e '.totalPrompts == 7 and ([.modelUsage[].inputTokens] | add) == 101 and .includesSharedSessions' \
  "$claude_usage/anthropic@work.json" >/dev/null ||
  fail "Missing Anthropic ledger assigns shared usage only to the active account"
pass "Missing ledgers fall back to the active account without duplication"

# Adoption names a sole account default. Its account record must preserve the
# exact stats that the old one-record collector produced from the canonical
# config link and all shared sources.
rm -rf "$claude_root/work"
ln -sfnT "$claude_root/default/claude" "$CLAUDE_HOME/.claude"
cat >"$claude_switches/anthropic.json" <<'EOF'
[{"timestamp":"2024-01-02T00:00:00Z","providerId":"anthropic","accountId":"default"}]
EOF
direct=$(
  HOME="$CLAUDE_HOME" \
    CLAUDE_CONFIG_DIR="$CLAUDE_HOME/.claude" \
    XDG_CACHE_HOME="$CLAUDE_HOME/.cache" \
    XDG_DATA_HOME="$CLAUDE_HOME/.local/share" \
    XDG_STATE_HOME="$CLAUDE_HOME/.local/state" \
    "$ROOT/bin/omarchy-agent-usage-claude" --force
)
HOME="$CLAUDE_HOME" \
  XDG_CACHE_HOME="$CLAUDE_HOME/.cache" \
  XDG_DATA_HOME="$CLAUDE_HOME/.local/share" \
  XDG_STATE_HOME="$CLAUDE_HOME/.local/state" \
  OMARCHY_PATH="$ROOT" \
  "$ROOT/bin/omarchy-agent-usage-update" claude --force

stats_projection='{todayPrompts,todaySessions,todayTotalTokens,todayTokensByModel,recentDays,modelUsage,totalPrompts,totalSessions,activeDays,activeDates,includesSharedSessions}'
direct_stats=$(jq -c "$stats_projection" <<<"$direct")
account_stats=$(jq -c "$stats_projection" "$claude_usage/anthropic@default.json")
jq -en --argjson direct "$direct_stats" --argjson account "$account_stats" '$direct == $account' >/dev/null ||
  fail "A sole adopted Anthropic account preserves the old collector totals"
[[ ! -e $claude_usage/anthropic@work.json ]] ||
  fail "Removing an account prunes its regenerated usage record"
pass "A sole default account preserves the pre-account Claude totals"

codex_root="$CODEX_HOME_FIXTURE/.local/share/omarchy/agents/openai"
codex_usage="$CODEX_HOME_FIXTURE/.local/state/omarchy/agents/usage"
codex_switches="$CODEX_HOME_FIXTURE/.local/state/omarchy/agents/switches"
mkdir -p \
  "$codex_root/default/codex/sessions/2024/01/03" \
  "$codex_root/work/codex/sessions/2024/01/05" \
  "$CODEX_HOME_FIXTURE/.pi/agent/sessions/project" \
  "$CODEX_HOME_FIXTURE/.omp/agent/sessions/project" \
  "$CODEX_HOME_FIXTURE/bin" \
  "$codex_switches" \
  "$codex_usage"
ln -s "$codex_root/work/codex" "$CODEX_HOME_FIXTURE/.codex"

cat >"$codex_root/default/codex/sessions/2024/01/03/native.jsonl" <<'EOF'
{"timestamp":"2024-01-03T12:00:00Z","type":"turn_context","payload":{"model":"codex-native"}}
{"timestamp":"2024-01-03T12:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":31}}}}
EOF
cat >"$codex_root/work/codex/sessions/2024/01/05/native.jsonl" <<'EOF'
{"timestamp":"2024-01-05T12:00:00Z","type":"turn_context","payload":{"model":"codex-native"}}
{"timestamp":"2024-01-05T12:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":37}}}}
EOF
cat >"$CODEX_HOME_FIXTURE/.pi/agent/sessions/project/pi.jsonl" <<'EOF'
{"type":"message","id":"pi-before","timestamp":"2024-01-01T12:00:00Z","message":{"role":"assistant","provider":"openai-codex","model":"codex-pi","usage":{"input":3}}}
{"type":"message","id":"pi-work","timestamp":"2024-01-05T12:00:00Z","message":{"role":"assistant","provider":"openai-codex","model":"codex-pi","usage":{"input":7}}}
EOF
cat >"$CODEX_HOME_FIXTURE/.omp/agent/sessions/project/omp.jsonl" <<'EOF'
{"type":"message","id":"omp-default","timestamp":"2024-01-03T12:00:00Z","message":{"role":"assistant","provider":"openai-codex","model":"codex-omp","usage":{"input":5}}}
EOF
cat >"$codex_switches/openai.json" <<'EOF'
[
  {"timestamp":"2024-01-02T00:00:00Z","providerId":"openai","accountId":"default"},
  {"timestamp":"2024-01-04T00:00:00Z","providerId":"openai","accountId":"work"}
]
EOF
cat >"$CODEX_HOME_FIXTURE/bin/codex" <<'EOF'
#!/bin/bash
while read -r request; do
  id=$(jq -r '.id // empty' <<<"$request")
  case "$(jq -r '.method // empty' <<<"$request")" in
  initialize | account/read | account/rateLimits/read)
    jq -cn --argjson id "$id" '{id: $id, result: {}}'
    ;;
  esac
done
EOF
chmod +x "$CODEX_HOME_FIXTURE/bin/codex"

python3 - "$CODEX_HOME_FIXTURE/.local/share/opencode/opencode.db" <<'PY'
import json
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

db = Path(sys.argv[1])
db.parent.mkdir(parents=True, exist_ok=True)
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")

def millis(value):
  return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000)

def message(message_id, timestamp, tokens):
  created = millis(timestamp)
  data = json.dumps({
    "role": "assistant",
    "providerID": "openai",
    "modelID": "codex-opencode",
    "tokens": {"input": tokens, "output": 0, "reasoning": 0, "cache": {"read": 0, "write": 0}},
    "time": {"created": created},
  })
  return message_id, message_id, created, created, data

conn.executemany("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [
  message("oc-before", "2024-01-01T12:00:00Z", 11),
  message("oc-default", "2024-01-03T12:00:00Z", 13),
  message("oc-work", "2024-01-05T12:00:00Z", 17),
])
conn.commit()
conn.close()
PY

printf '{"id":"codex"}\n' >"$codex_usage/codex.json"
printf '{"id":"openai@deleted"}\n' >"$codex_usage/openai@deleted.json"

HOME="$CODEX_HOME_FIXTURE" \
  PATH="$CODEX_HOME_FIXTURE/bin:$PATH" \
  XDG_CACHE_HOME="$CODEX_HOME_FIXTURE/.cache" \
  XDG_DATA_HOME="$CODEX_HOME_FIXTURE/.local/share" \
  XDG_STATE_HOME="$CODEX_HOME_FIXTURE/.local/state" \
  OMARCHY_PATH="$ROOT" \
  "$ROOT/bin/omarchy-agent-usage-update" codex --force

jq -e '
  .id == "openai@default" and
  .providerId == "openai" and
  .accountId == "default" and
  (.accountActive | not) and
  .includesSharedSessions and
  .totalPrompts == 5 and
  ([.modelUsage[].inputTokens] | add) == 63
' "$codex_usage/openai@default.json" >/dev/null ||
  fail "OpenAI ledger attributes pre-ledger and default-era shared messages to the first account"
jq -e '
  .id == "openai@work" and
  .providerId == "openai" and
  .accountId == "work" and
  .accountActive and
  .includesSharedSessions and
  .totalPrompts == 3 and
  ([.modelUsage[].inputTokens] | add) == 61
' "$codex_usage/openai@work.json" >/dev/null ||
  fail "OpenAI ledger attributes later shared messages to the account active at their timestamp"
[[ ! -e $codex_usage/codex.json && ! -e $codex_usage/openai@deleted.json ]] ||
  fail "OpenAI refresh prunes its stale and legacy records"
(( $(find "$CODEX_HOME_FIXTURE/.cache/omarchy/agent-usage" -maxdepth 1 -name 'codex-scan-*.json' | wc -l) == 2 )) ||
  fail "Codex aggregate caches are keyed per resolved config directory"
pass "OpenAI shared sessions are attributed once across account records"

before=$(sha256sum "$codex_usage/openai@work.json")
HOME="$CODEX_HOME_FIXTURE" \
  PATH="$CODEX_HOME_FIXTURE/bin:$PATH" \
  XDG_CACHE_HOME="$CODEX_HOME_FIXTURE/.cache" \
  XDG_DATA_HOME="$CODEX_HOME_FIXTURE/.local/share" \
  XDG_STATE_HOME="$CODEX_HOME_FIXTURE/.local/state" \
  OMARCHY_PATH="$ROOT" \
  "$ROOT/bin/omarchy-agent-usage-update" --except codex openai
after=$(sha256sum "$codex_usage/openai@work.json")
[[ $before == $after ]] ||
  fail "Legacy --except codex selector excludes the OpenAI provider"
pass "Provider selection accepts canonical and legacy spellings"
