#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command jq

TEST_HOME=$(mktemp -d)
mock_bin="$TEST_HOME/mock-bin"
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$mock_bin" "$TEST_HOME/.claude"

cat >"$mock_bin/omarchy-agent-usage-update" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$mock_bin/omarchy-notification-send" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$mock_bin/claude" <<'EOF'
#!/bin/bash
if [[ $1 == auth && $2 == login ]]; then
  mkdir -p "$CLAUDE_CONFIG_DIR"
  cat >"$CLAUDE_CONFIG_DIR/.claude.json" <<'JSON'
{"oauthAccount":{"emailAddress":"work@example.com","accountUuid":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","displayName":"Work","organizationName":"Work Org","organizationType":"max","organizationRateLimitTier":"default_claude_max_5x"}}
JSON
  cat >"$CLAUDE_CONFIG_DIR/.credentials.json" <<'JSON'
{"claudeAiOauth":{"accessToken":"work-token","refreshToken":"work-refresh","subscriptionType":"max","rateLimitTier":"default_claude_max_5x"}}
JSON
  exit 0
fi
exit 1
EOF

chmod +x "$mock_bin"/*

export HOME="$TEST_HOME"
export XDG_STATE_HOME="$TEST_HOME/.local/state"
export OMARCHY_PATH="$ROOT"
export PATH="$mock_bin:$ROOT/bin:$PATH"

cat >"$HOME/.claude/.claude.json" <<'JSON'
{"oauthAccount":{"emailAddress":"personal@example.com","accountUuid":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","displayName":"Personal","organizationName":"Personal Org","organizationType":"max","organizationRateLimitTier":"default_claude_max_20x"}}
JSON
cat >"$HOME/.claude/.credentials.json" <<'JSON'
{"claudeAiOauth":{"accessToken":"personal-token","refreshToken":"personal-refresh","subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}
JSON
chmod 600 "$HOME/.claude/.credentials.json"

listed=$(omarchy-agent-account list claude --json)
[[ $(jq -r '.provider' <<<"$listed") == "claude" ]] || fail "list names the claude provider" "$listed"
[[ $(jq -r '.accounts | length' <<<"$listed") == "1" ]] || fail "list registers the live ~/.claude login" "$listed"
[[ $(jq -r '.accounts[0].email' <<<"$listed") == "personal@example.com" ]] || fail "list reports the live email" "$listed"
[[ $(jq -r '.accounts[0].active' <<<"$listed") == "true" ]] || fail "the live login is the active account" "$listed"
pass "list registers the live Claude login"

personal_id=$(jq -r '.accounts[0].id' <<<"$listed")
[[ $(omarchy-agent-account dir claude) == "$(python3 -c "from pathlib import Path; print(Path('$HOME/.claude').resolve())")" ]] ||
  fail "dir points at ~/.claude for the first account"
pass "dir points at ~/.claude for the first account"

omarchy-agent-account add claude >/dev/null

listed=$(omarchy-agent-account list --json)
[[ $(jq -r '.accounts | length' <<<"$listed") == "2" ]] || fail "add registers a second isolated account" "$listed"
[[ $(jq -r '.current.email' <<<"$listed") == "work@example.com" ]] || fail "add switches the pointer to the new account" "$listed"
work_path=$(jq -r '.current.path' <<<"$listed")
[[ $work_path == "$XDG_STATE_HOME/omarchy/agent-accounts/claude/accounts/"* ]] ||
  fail "the new account lives under the state directory" "$work_path"
[[ $(omarchy-agent-account dir claude) == "$work_path" ]] || fail "dir follows the pointer after add"
pass "add creates an isolated Claude config dir and points at it"

[[ -f $HOME/.claude/.credentials.json ]] || fail "add does not remove the original ~/.claude credentials"
original_token=$(jq -r '.claudeAiOauth.accessToken' "$HOME/.claude/.credentials.json")
[[ $original_token == "personal-token" ]] || fail "add does not copy over the original OAuth" "$original_token"
pass "add leaves the original ~/.claude session in place"

work_id=$(jq -r '.current.id' <<<"$listed")
omarchy-agent-account use claude "$personal_id" >/dev/null
[[ $(jq -r '.current.email' <<<"$(omarchy-agent-account list --json)") == "personal@example.com" ]] ||
  fail "use switches the pointer back to the original account"
[[ $(omarchy-agent-account dir claude) == "$(python3 -c "from pathlib import Path; print(Path('$HOME/.claude').resolve())")" ]] ||
  fail "dir follows the pointer after use"
[[ $(jq -r '.claudeAiOauth.accessToken' "$work_path/.credentials.json") == "work-token" ]] ||
  fail "use does not rewrite the unused account's credentials"
pass "use switches the pointer without copying OAuth"

if omarchy-agent-account list codex >/dev/null 2>&1; then
  fail "list refuses providers with no backend"
fi
pass "list refuses providers with no backend"

omarchy-agent-account use "$work_id" >/dev/null
[[ $(jq -r '.current.email' <<<"$(omarchy-agent-account list --json)") == "work@example.com" ]] ||
  fail "use claude is implied when the provider is omitted"
pass "use claude is implied when the provider is omitted"

collector_dir=$(HOME="$TEST_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" python3 - <<'PY'
import importlib.machinery, importlib.util, os
loader = importlib.machinery.SourceFileLoader("collector", os.environ["OMARCHY_PATH"] + "/bin/omarchy-agent-usage-claude")
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)
print(collector.config_dir())
PY
)
[[ $collector_dir == "$work_path" ]] || fail "usage collector follows the account pointer" "$collector_dir"
pass "usage collector follows the account pointer"
