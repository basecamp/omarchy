#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command flock
require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
mock_bin="$test_tmp/bin"
launcher_log="$test_tmp/launcher-log"
shell_log="$test_tmp/shell-log"
mkdir -p "$test_home" "$mock_bin"

cat >"$mock_bin/omarchy-default-agent" <<'SH'
#!/bin/bash
printf '%s\n' "${OMARCHY_TEST_DEFAULT_AGENT-claude}"
SH

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
for command in "$@"; do
  case " ${OMARCHY_TEST_INSTALLED_HARNESSES:-claude codex pi opencode} " in
  *" $command "*) ;;
  *) exit 0 ;;
  esac
done
exit 1
SH

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_LAUNCHER_LOG"
SH

cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_SHELL_LOG"
SH

cat >"$mock_bin/gum" <<'SH'
#!/bin/bash
first=""
while IFS= read -r row; do
  [[ -n $first ]] || first="$row"
done
printf '%s\n' "${OMARCHY_TEST_GUM_CHOICE:-$first}"
SH

cat >"$mock_bin/claude" <<'SH'
#!/bin/bash
mkdir -p "$CLAUDE_CONFIG_DIR"
jq -n --arg token "${OMARCHY_TEST_CLAUDE_TOKEN:-claude-login}" '{oauth: $token}' >"$CLAUDE_CONFIG_DIR/.credentials.json"
SH

cat >"$mock_bin/codex" <<'SH'
#!/bin/bash
mkdir -p "$CODEX_HOME"
jq -n --arg token "${OMARCHY_TEST_CODEX_TOKEN:-codex-login}" '{tokens: $token}' >"$CODEX_HOME/auth.json"
SH

cat >"$mock_bin/pi" <<'SH'
#!/bin/bash
auth_file="$HOME/.pi/agent/auth.json"
auth_key=${OMARCHY_TEST_PI_AUTH_KEY:?}
mkdir -p "$(dirname "$auth_file")"
if [[ -f $auth_file ]]; then
  jq --arg key "$auth_key" --arg token "${OMARCHY_TEST_PI_TOKEN:-pi-login}" '.[$key] = {type: "oauth", access: $token}' "$auth_file" >"$auth_file.tmp"
else
  jq -n --arg key "$auth_key" --arg token "${OMARCHY_TEST_PI_TOKEN:-pi-login}" '{($key): {type: "oauth", access: $token}}' >"$auth_file.tmp"
fi
mv -T "$auth_file.tmp" "$auth_file"
SH

cat >"$mock_bin/opencode" <<'SH'
#!/bin/bash
provider=""
while (( $# > 0 )); do
  if [[ $1 == "--provider" ]]; then
    provider="$2"
    shift
  fi
  shift
done
auth_file="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
mkdir -p "$(dirname "$auth_file")"
if [[ -f $auth_file ]]; then
  jq --arg key "$provider" --arg token "${OMARCHY_TEST_OPENCODE_TOKEN:-opencode-login}" '.[$key] = {type: "oauth", refresh: $token, access: $token, expires: 9999999999999}' "$auth_file" >"$auth_file.tmp"
else
  jq -n --arg key "$provider" --arg token "${OMARCHY_TEST_OPENCODE_TOKEN:-opencode-login}" '{($key): {type: "oauth", refresh: $token, access: $token, expires: 9999999999999}}' >"$auth_file.tmp"
fi
mv -T "$auth_file.tmp" "$auth_file"
SH

cat >"$mock_bin/omarchy-done" <<'SH'
#!/bin/bash
[[ $1 != "check" ]]
SH

cat >"$mock_bin/omarchy-test-noop" <<'SH'
#!/bin/bash
exit 0
SH

for command in omarchy-refresh-applications xdg-mime xdg-settings xdg-user-dirs-update; do
  ln -s omarchy-test-noop "$mock_bin/$command"
done
chmod +x "$mock_bin"/*

export HOME="$test_home"
export OMARCHY_PATH="$ROOT"
export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_TEST_LAUNCHER_LOG="$launcher_log"
export OMARCHY_TEST_SHELL_LOG="$shell_log"

bare_home="$test_tmp/bare-home"
mkdir -p "$bare_home"
bare_output=$(HOME="$bare_home" OMARCHY_TEST_DEFAULT_AGENT="" omarchy-agent-account)
[[ $bare_output == "No agent accounts are set up yet." ]] || fail "bare account command explains that no accounts are configured"
pass "bare account command succeeds when no default agent is set"

claude_only_home="$test_tmp/claude-only-home"
mkdir -p "$claude_only_home/.claude"
printf '{"oauth":"claude-only-default"}\n' >"$claude_only_home/.claude/.credentials.json"
(
  export HOME="$claude_only_home"
  export OMARCHY_TEST_INSTALLED_HARNESSES="claude"
  [[ $(omarchy-agent-account anthropic) == "default" ]]
  OMARCHY_TEST_CLAUDE_TOKEN=claude-only-work \
    omarchy-agent-account-login --run-slot-login anthropic work claude >"$test_tmp/claude-only-login" 2>&1
  omarchy-agent-account-switch anthropic default >/dev/null
  omarchy-agent-account-switch anthropic work >"$test_tmp/claude-only-switch" 2>&1
  [[ $(OMARCHY_TEST_DEFAULT_AGENT="" omarchy-agent-account) == "Anthropic: work" ]]
  claude_only_list=$(omarchy-agent-account-list anthropic)
  [[ $claude_only_list != *"missing pi:"* ]]
  [[ $claude_only_list != *"missing opencode:"* ]]
  omarchy-agent-account-list anthropic --json |
    jq -e 'all(.[]; (.slots | keys) == ["claude"] and .missingSlots == [])' >/dev/null
)
[[ $(<"$test_tmp/claude-only-switch") == "Switched Anthropic to account 'work'." ]] ||
  fail "Claude-only switch mentions no uninstalled harnesses"
[[ ! -e $claude_only_home/.pi ]] || fail "Claude-only account handling does not create a Pi auth directory"
[[ ! -e $claude_only_home/.local/share/opencode ]] || fail "Claude-only account handling does not create an OpenCode auth directory"
pass "Claude-only machines switch and list accounts without uninstalled harness slots"
pass "uninstalled harnesses get no auth files or directories"

(
  export XDG_DATA_HOME="$test_tmp/xdg-data"
  source "$ROOT/bin/omarchy-agent-account-backends"
  agent_account_provider_load anthropic
  agent_account_slot_load opencode
  [[ $AGENT_ACCOUNT_SLOT_AUTH_FILE == "$XDG_DATA_HOME/opencode/auth.json" ]]
) || fail "OpenCode auth-key slots honor XDG_DATA_HOME"
pass "OpenCode auth-key slots honor XDG_DATA_HOME"

pi_auth="$HOME/.pi/agent/auth.json"
opencode_auth="$HOME/.local/share/opencode/auth.json"
anthropic_root="$HOME/.local/share/omarchy/agents/anthropic"

mkdir -p "$HOME/.claude" "$(dirname "$pi_auth")" "$(dirname "$opencode_auth")"
printf '{"oauth":"legacy-claude"}\n' >"$HOME/.claude/.credentials.json"
printf '{"anthropic":{"type":"oauth","access":"default-pi"},"openai-codex":{"type":"oauth","access":"openai-sibling"},"google":{"type":"api_key","key":"pi-sibling"}}\n' >"$pi_auth"
printf '{"anthropic":{"type":"oauth","refresh":"default-opencode","access":"default-opencode","expires":9999999999999},"openai":{"type":"oauth","refresh":"openai-sibling","access":"openai-sibling","expires":9999999999999},"google":{"type":"api","key":"opencode-sibling"}}\n' >"$opencode_auth"

[[ $(omarchy-agent-account claude) == "default" ]] || fail "Claude alias selects the Anthropic provider"
[[ -L $HOME/.claude ]] || fail "Claude canonical config becomes a symlink"
[[ $(readlink "$HOME/.claude") == "$anthropic_root/default/claude" ]] ||
  fail "Claude config points at the adopted provider account slot"
jq -e '.oauth == "legacy-claude"' "$anthropic_root/default/claude/.credentials.json" >/dev/null ||
  fail "adoption preserves the existing Claude credential"
jq -e '.access == "default-pi"' "$anthropic_root/default/slots/pi.json" >/dev/null ||
  fail "adoption captures the live Pi Anthropic key"
jq -e '.access == "default-opencode"' "$anthropic_root/default/slots/opencode.json" >/dev/null ||
  fail "adoption captures the live OpenCode Anthropic key"
jq -e '.google.key == "pi-sibling" and .["openai-codex"].access == "openai-sibling"' "$pi_auth" >/dev/null ||
  fail "adoption leaves Pi sibling providers untouched"
jq -e '.google.key == "opencode-sibling" and .openai.access == "openai-sibling"' "$opencode_auth" >/dev/null ||
  fail "adoption leaves OpenCode sibling providers untouched"
[[ $(stat -c '%a' "$anthropic_root") == "700" ]] || fail "managed provider root is private"
[[ $(stat -c '%a' "$anthropic_root/default") == "700" ]] || fail "account bundle is private"
[[ $(stat -c '%a' "$anthropic_root/default/claude") == "700" ]] || fail "config-dir slot is private"
[[ $(stat -c '%a' "$anthropic_root/default/slots/pi.json") == "600" ]] || fail "stored auth-key slot is private"
pass "existing provider credentials are adopted into private per-harness slots"

list_output=$(omarchy-agent-account-list anthropic)
[[ $list_output == "* anthropic default" ]] || fail "complete text account list marks the active provider account"
omarchy-agent-account-list anthropic --json |
  jq -e 'length == 1 and .[0].providerId == "anthropic" and .[0].accountId == "default" and .[0].accountActive and (.[0].slots | all(.[]; .filled)) and .[0].missingSlots == []' >/dev/null ||
  fail "JSON account list exposes canonical provider identity and slot readiness"
pass "account lists report canonical providers and per-slot readiness"

if omarchy-agent-account-login anthropic ../escape claude >"$test_tmp/invalid-output" 2>&1; then
  fail "account names cannot escape the managed root"
fi
grep -Fq "Invalid account name '../escape'" "$test_tmp/invalid-output" ||
  fail "invalid account errors name the rejected value"
[[ ! -e $HOME/.local/share/omarchy/agents/escape ]] || fail "invalid account names create no profile"

if omarchy-agent-account-login anthropic openai claude >"$test_tmp/reserved-output" 2>&1; then
  fail "account IDs cannot collide with provider arguments"
fi
grep -Fq "provider names and aliases are reserved" "$test_tmp/reserved-output" ||
  fail "reserved account errors explain the provider ambiguity"
pass "account IDs preserve containment and provider argument boundaries"

: >"$launcher_log"
omarchy-agent-account-login anthropic work claude
mapfile -d '' -t launcher_args <"$launcher_log"
expected_login="$ROOT/bin/omarchy-agent-account-login --run-slot-login anthropic work claude"
[[ ${#launcher_args[@]} == 1 && ${launcher_args[0]} == "$expected_login" ]] ||
  fail "public login launches the selected harness slot flow"
[[ $(omarchy-agent-account anthropic) == "default" ]] || fail "launching a login terminal does not mutate the default-agent setting or account state"

OMARCHY_TEST_CLAUDE_TOKEN=work-claude \
  omarchy-agent-account-login --run-slot-login anthropic work claude 2>"$test_tmp/claude-missing"
[[ $(omarchy-agent-account anthropic) == "work" ]] || fail "slot login activates its provider account"
jq -e '.oauth == "work-claude"' "$anthropic_root/work/claude/.credentials.json" >/dev/null ||
  fail "Claude login writes into the account's config-dir slot"
grep -Fq "pi: omarchy agent account login anthropic work pi" "$test_tmp/claude-missing" ||
  fail "login reports the missing Pi slot and its fill command"
grep -Fq "opencode: omarchy agent account login anthropic work opencode" "$test_tmp/claude-missing" ||
  fail "login reports the missing OpenCode slot and its fill command"
jq -e 'has("anthropic") | not' "$pi_auth" >/dev/null || fail "partial login does not leave the outgoing Pi credential live"
jq -e '.google.key == "pi-sibling" and .["openai-codex"].access == "openai-sibling"' "$pi_auth" >/dev/null ||
  fail "partial activation preserves unrelated Pi providers"
pass "login fills one slot and reports every still-empty slot"

omarchy-agent-account-switch anthropic default >/dev/null
omarchy-agent-account-switch anthropic work >"$test_tmp/missing-switch" 2>&1
grep -Fq "pi: omarchy agent account login anthropic work pi" "$test_tmp/missing-switch" ||
  fail "partial switch names the empty Pi slot and fill command"
grep -Fq "opencode: omarchy agent account login anthropic work opencode" "$test_tmp/missing-switch" ||
  fail "partial switch names the empty OpenCode slot and fill command"
[[ $(omarchy-agent-account anthropic) == "work" ]] || fail "empty installed slots do not block a partially filled account"
jq -e '(has("anthropic") | not) and .google.key == "pi-sibling" and .["openai-codex"].access == "openai-sibling"' "$pi_auth" >/dev/null ||
  fail "partial switch clears Pi's provider credential and preserves sibling providers"
jq -e '(has("anthropic") | not) and .google.key == "opencode-sibling" and .openai.access == "openai-sibling"' "$opencode_auth" >/dev/null ||
  fail "partial switch clears OpenCode's provider credential and preserves sibling providers"
pass "installed empty slots warn, stay signed out, and do not block switching"

mkdir -p "$anthropic_root/empty/claude"
if omarchy-agent-account-switch anthropic empty >"$test_tmp/empty-switch" 2>&1; then
  fail "switching accepts an account with no filled slots"
fi
grep -Fq "Anthropic account 'empty' has no filled credential slots." "$test_tmp/empty-switch" ||
  fail "an entirely empty account explains why switching is refused"
[[ $(omarchy-agent-account anthropic) == "work" ]] || fail "an entirely empty account leaves the active account unchanged"
pass "accounts with no filled installed slot are refused"

OMARCHY_TEST_PI_AUTH_KEY=anthropic OMARCHY_TEST_PI_TOKEN=work-pi \
  omarchy-agent-account-login --run-slot-login anthropic work pi 2>"$test_tmp/pi-missing"
grep -Fq "opencode: omarchy agent account login anthropic work opencode" "$test_tmp/pi-missing" ||
  fail "Pi login still reports the empty OpenCode slot"
OMARCHY_TEST_OPENCODE_TOKEN=work-opencode \
  omarchy-agent-account-login --run-slot-login anthropic work opencode
jq -e '.access == "work-pi"' "$anthropic_root/work/slots/pi.json" >/dev/null || fail "Pi provider key is captured into its account slot"
jq -e '.access == "work-opencode"' "$anthropic_root/work/slots/opencode.json" >/dev/null || fail "OpenCode provider key is captured into its account slot"
pass "auth-key logins capture only the provider key written by each harness"

jq '.anthropic.access = "work-pi-refreshed"' "$pi_auth" >"$pi_auth.tmp"
mv -T "$pi_auth.tmp" "$pi_auth"
jq '.anthropic.access = "work-opencode-refreshed" | .anthropic.refresh = "work-opencode-refreshed"' "$opencode_auth" >"$opencode_auth.tmp"
mv -T "$opencode_auth.tmp" "$opencode_auth"

omarchy-agent-account-switch anthropic default >/dev/null
jq -e '.access == "work-pi-refreshed"' "$anthropic_root/work/slots/pi.json" >/dev/null ||
  fail "switch stashes Pi's refreshed OAuth blob before restoring the incoming account"
jq -e '.access == "work-opencode-refreshed"' "$anthropic_root/work/slots/opencode.json" >/dev/null ||
  fail "switch stashes OpenCode's refreshed OAuth blob before restoring the incoming account"
jq -e '.anthropic.access == "default-pi" and .google.key == "pi-sibling" and .["openai-codex"].access == "openai-sibling"' "$pi_auth" >/dev/null ||
  fail "Pi restore replaces only Anthropic and preserves sibling providers"
jq -e '.anthropic.access == "default-opencode" and .google.key == "opencode-sibling" and .openai.access == "openai-sibling"' "$opencode_auth" >/dev/null ||
  fail "OpenCode restore replaces only Anthropic and preserves sibling providers"

omarchy-agent-account-switch anthropic work >/dev/null
jq -e '.anthropic.access == "work-pi-refreshed" and .google.key == "pi-sibling" and .["openai-codex"].access == "openai-sibling"' "$pi_auth" >/dev/null ||
  fail "Pi round trip restores the refreshed account credential and siblings"
jq -e '.anthropic.access == "work-opencode-refreshed" and .google.key == "opencode-sibling" and .openai.access == "openai-sibling"' "$opencode_auth" >/dev/null ||
  fail "OpenCode round trip restores the refreshed account credential and siblings"
[[ $(stat -c '%a' "$pi_auth") == "600" && $(stat -c '%a' "$opencode_auth") == "600" ]] ||
  fail "auth-key restores keep shared auth files at 0600"
pass "auth-key slots round-trip refreshed OAuth blobs without touching sibling providers"

ledger="$HOME/.local/state/omarchy/agents/switches/anthropic.json"
jq -e 'length >= 2 and all(.[]; .providerId == "anthropic" and (.accountId | type == "string") and (.timestamp | fromdateiso8601)) and .[-1].accountId == "work"' "$ledger" >/dev/null ||
  fail "switch ledger records timestamped canonical provider/account changes"
[[ $(stat -c '%a' "$ledger") == "600" ]] || fail "switch ledger is private"
pass "provider switches append an atomic timestamped ledger for later attribution"

omarchy-agent-account-switch anthropic --next >/dev/null
[[ $(omarchy-agent-account anthropic) == "default" ]] || fail "--next cycles complete provider accounts"
OMARCHY_TEST_GUM_CHOICE=work omarchy-agent-account-switch anthropic >/dev/null
[[ $(omarchy-agent-account anthropic) == "work" ]] || fail "account picker switches every provider slot"
pass "provider account switching supports cycling and interactive selection"

mkdir -p "$anthropic_root/interrupted/claude" "$anthropic_root/interrupted/slots"
printf '{"oauth":"interrupted-claude"}\n' >"$anthropic_root/interrupted/claude/.credentials.json"
printf '{"type":"oauth","access":"interrupted-pi"}\n' >"$anthropic_root/interrupted/slots/pi.json"
printf '{"type":"oauth","refresh":"interrupted-opencode","access":"interrupted-opencode","expires":9999999999999}\n' >"$anthropic_root/interrupted/slots/opencode.json"
chmod 700 "$anthropic_root/interrupted" "$anthropic_root/interrupted/claude" "$anthropic_root/interrupted/slots"
chmod 600 "$anthropic_root/interrupted/slots"/*.json

omarchy-agent-account-switch anthropic default >/dev/null
jq '.anthropic.access = "interrupted-pi"' "$pi_auth" >"$pi_auth.tmp"
mv -T "$pi_auth.tmp" "$pi_auth"
ln -s "$anthropic_root/interrupted/claude" "$HOME/.claude.interrupted"
mv -Tf "$HOME/.claude.interrupted" "$HOME/.claude"
printf '{"from":"default","to":"interrupted"}\n' >"$anthropic_root/.switching.json"
chmod 600 "$anthropic_root/.switching.json"

[[ $(omarchy-agent-account anthropic) == "default" ]] || fail "next account command rolls an interrupted switch back to its outgoing account"
jq -e '.anthropic.access == "default-pi" and .google.key == "pi-sibling"' "$pi_auth" >/dev/null ||
  fail "interrupted-switch recovery restores the outgoing Pi key and siblings"
jq -e '.anthropic.access == "default-opencode" and .google.key == "opencode-sibling"' "$opencode_auth" >/dev/null ||
  fail "interrupted-switch recovery restores the outgoing OpenCode key and siblings"
[[ ! -e $anthropic_root/.switching.json ]] || fail "interrupted-switch recovery clears its journal"
pass "an interrupted multi-slot switch recovers as one provider account"

theme_source="$HOME/.local/state/omarchy/current/theme/claude.json"
mkdir -p "$(dirname "$theme_source")"
printf '{"name":"Omarchy"}\n' >"$theme_source"
omarchy-theme-set-claude --activate
for account in default interrupted work; do
  [[ -f $anthropic_root/$account/claude/themes/omarchy.json ]] ||
    fail "Claude theme reaches managed $account config slot"
  jq -e '.theme == "custom:omarchy"' "$anthropic_root/$account/claude/settings.json" >/dev/null ||
    fail "Claude theme activation reaches managed $account config slot"
done
pass "Claude theming iterates config-dir slots across Anthropic accounts"

omarchy-agent-account-switch anthropic work >/dev/null
if omarchy-agent-account-logout anthropic work >"$test_tmp/active-logout-output" 2>&1; then
  fail "logout refuses the active provider account"
fi
grep -Fq "switch to another account first" "$test_tmp/active-logout-output" ||
  fail "active logout explains how to proceed"

omarchy-agent-account-switch anthropic default >/dev/null
mkdir -p "$HOME/.local/state/omarchy/agents/usage"
printf '{}\n' >"$HOME/.local/state/omarchy/agents/usage/anthropic@work.json"
logout_output=$(omarchy-agent-account-logout anthropic work)
trash_profile=$(find "$anthropic_root/.trash" -mindepth 1 -maxdepth 1 -type d -name 'work.*' -print -quit)
[[ -n $trash_profile && -f $trash_profile/slots/pi.json ]] || fail "logout keeps the whole credential bundle in recoverable trash"
[[ $logout_output == *"$trash_profile"* ]] || fail "logout reports where recovery data was moved"
[[ ! -e $HOME/.local/state/omarchy/agents/usage/anthropic@work.json ]] || fail "logout removes the canonical provider account usage record"
pass "logout refuses active state and recoverably forgets an inactive provider bundle"

openai_root="$HOME/.local/share/omarchy/agents/openai"
mkdir -p "$openai_root/default/codex"
printf '{"tokens":"moved-codex"}\n' >"$openai_root/default/codex/auth.json"
jq '.["openai-codex"] = {type: "oauth", access: "default-openai-pi"}' "$pi_auth" >"$pi_auth.tmp"
mv -T "$pi_auth.tmp" "$pi_auth"
jq '.openai = {type: "oauth", refresh: "default-openai-opencode", access: "default-openai-opencode", expires: 9999999999999}' "$opencode_auth" >"$opencode_auth.tmp"
mv -T "$opencode_auth.tmp" "$opencode_auth"

[[ $(omarchy-agent-account codex) == "default" ]] || fail "Codex alias selects OpenAI and resumes an already-moved config slot"
[[ -L $HOME/.codex && $(readlink "$HOME/.codex") == "$openai_root/default/codex" ]] ||
  fail "resumed OpenAI adoption points Codex at its account config slot"
jq -e '.access == "default-openai-pi"' "$openai_root/default/slots/pi.json" >/dev/null ||
  fail "OpenAI adoption maps Pi subscription auth from the openai-codex key"
jq -e '.access == "default-openai-opencode"' "$openai_root/default/slots/opencode.json" >/dev/null ||
  fail "OpenAI adoption maps OpenCode subscription auth from the openai key"
[[ $(omarchy-agent-account openai) == "default" ]] || fail "canonical OpenAI provider ID is accepted"

rm "$HOME/.codex"
ln -s "$openai_root/recovered/codex" "$HOME/.codex"
[[ $(omarchy-agent-account openai) == "recovered" ]] || fail "managed dangling config slots are repaired"
[[ -d $openai_root/recovered/codex ]] || fail "dangling config-slot repair creates a private account profile"
pass "OpenAI uses the verified harness-specific keys and resumable config adoption"

if (( EUID == 0 )); then
  pass "running as root; skipping user finalization provisioning check"
else
  install_root="$test_tmp/install"
  mkdir -p "$install_root/user"
  printf ':\n' >"$install_root/user/all.sh"
  rm "$anthropic_root/default/claude/skills/omarchy"
  rm "$anthropic_root/interrupted/claude/skills/omarchy"
  OMARCHY_INSTALL="$install_root" omarchy-provision-user --force >/dev/null
  [[ -L $anthropic_root/default/claude/skills/omarchy ]] ||
    fail "user finalization reprovisions the default Anthropic config slot"
  [[ -L $anthropic_root/interrupted/claude/skills/omarchy ]] ||
    fail "user finalization reprovisions the inactive Anthropic config slot"
  pass "user finalization provisions skills into every managed config-dir slot"
fi
