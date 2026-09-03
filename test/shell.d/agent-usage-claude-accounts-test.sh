#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

# A second Claude account lives in its own config directory, and the
# collector reports every one it finds beside the default. Everything here
# is planted under a scratch HOME, and the sign-ins are lapsed so no probe
# ever leaves the machine.
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

timestamp="$(date +%Y-%m-%d)T12:00:00Z"

plant_transcript() {
  local dir="$1" model="$2" output="$3"
  mkdir -p "$dir/projects/example"
  cat >"$dir/projects/example/session.jsonl" <<JSONL
{"timestamp":"$timestamp","type":"assistant","sessionId":"session-1","uuid":"event-1","message":{"id":"message-1","role":"assistant","model":"$model","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":$output}}}
JSONL
}

plant_login() {
  local dir="$1" account="$2"
  mkdir -p "$dir"
  echo '{"claudeAiOauth":{"accessToken":"token","expiresAt":1000,"subscriptionType":"max","rateLimitTier":"default_claude_max_5x"}}' >"$dir/.credentials.json"
  echo "{\"oauthAccount\":{\"accountUuid\":\"$account\",\"emailAddress\":\"$account@example.com\"}}" >"$dir/.claude.json"
}

plant_transcript "$TEST_HOME/.claude" claude-home 100
plant_login "$TEST_HOME/.claude" personal
# The default directory's identity file lives beside it, not inside it.
mv "$TEST_HOME/.claude/.claude.json" "$TEST_HOME/.claude.json"

plant_transcript "$TEST_HOME/.claude-work" claude-work 7
plant_login "$TEST_HOME/.claude-work" work

# Signed in to the account the default directory already covers.
plant_transcript "$TEST_HOME/.claude-dupe" claude-dupe 999
plant_login "$TEST_HOME/.claude-dupe" personal

# A directory with transcripts but no sign-in is a leftover, not an account.
plant_transcript "$TEST_HOME/.claude-stale" claude-stale 999

# Pi sessions have no account of their own and count toward the default only.
mkdir -p "$TEST_HOME/.pi/agent/sessions/project"
cat >"$TEST_HOME/.pi/agent/sessions/project/pi.jsonl" <<JSONL
{"type":"message","id":"pi-1","timestamp":"$timestamp","message":{"role":"assistant","provider":"anthropic","model":"claude-pi","usage":{"input":1,"output":2,"cacheRead":0,"cacheWrite":0,"totalTokens":3}}}
JSONL

result=$(env -u CLAUDE_CONFIG_DIR HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_DATA_HOME="$TEST_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-claude" --force)

[[ $(jq -c '[.accounts[].id]' <<<"$result") == '["claude-work"]' ]] ||
  fail "Claude collector nests one record per additional signed-in account" "$result"
pass "Claude collector nests one record per additional signed-in account"

[[ $(jq -r '.accounts[0].name + "/" + .accounts[0].tierLabel + "/" + .accounts[0].usageStatusText' <<<"$result") == "Claude · work/Max 5x/Sign-in expired" ]] ||
  fail "Claude collector names and labels an additional account from its own directory" "$result"
pass "Claude collector names and labels an additional account from its own directory"

[[ $(jq -c '[.todayTotalTokens, .accounts[0].todayTotalTokens]' <<<"$result") == "[113,17]" ]] ||
  fail "Claude collector keeps each account's transcripts apart and counts pi sessions once" "$result"
pass "Claude collector keeps each account's transcripts apart and counts pi sessions once"

[[ $(jq -c '[.modelUsage | keys[]], [.accounts[0].modelUsage | keys[]]' <<<"$result" | tr -d '\n') == '["claude-home","claude-pi"]["claude-work"]' ]] ||
  fail "Claude collector attributes models to the account that ran them" "$result"
pass "Claude collector attributes models to the account that ran them"

# With nothing beside the default directory, the record is what it always was.
mkdir -p "$TEST_HOME/solo"
mv "$TEST_HOME/.claude" "$TEST_HOME/solo/.claude"
solo=$(env -u CLAUDE_CONFIG_DIR HOME="$TEST_HOME/solo" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_DATA_HOME="$TEST_HOME/.local/share" \
  "$ROOT/bin/omarchy-agent-usage-claude" --force)

[[ $(jq -r 'has("accounts")' <<<"$solo") == "false" ]] ||
  fail "Claude collector nests nothing when only the default account is signed in" "$solo"
pass "Claude collector nests nothing when only the default account is signed in"

# Naming: a directory suffix becomes a record id the updater can file, and
# one that cannot be filed is skipped rather than written somewhere odd.
mapfile -t ids < <(python3 - "$ROOT/bin/omarchy-agent-usage-claude" <<'PY'
import importlib.util, sys
from importlib.machinery import SourceFileLoader
loader = SourceFileLoader("collector", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)
for suffix in ["work", "Acme Corp", "team/2", "...", ""]:
  print(collector.account_record_id(suffix) or "(none)")
PY
)
[[ "${ids[*]}" == "claude-work claude-Acme-Corp claude-team-2 (none) (none)" ]] ||
  fail "Claude collector derives a filing-safe record id from the directory suffix" "${ids[*]}"
pass "Claude collector derives a filing-safe record id from the directory suffix"
