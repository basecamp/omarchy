#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
test_repo="$test_tmp/repo"
test_omarchy="$test_tmp/omarchy"
test_bin="$test_tmp/bin"
mkdir -p "$test_home/.config/omarchy/defaults" "$test_home/.codex/skills" \
  "$test_home/.claude/skills" "$test_repo" "$test_omarchy/default/agents/skills/omarchy" "$test_bin"

printf 'codex\n' >"$test_home/.config/omarchy/defaults/agent"
touch "$test_repo/AGENTS.md" "$test_repo/CLAUDE.md"
ln -s "$test_omarchy/default/agents/skills/omarchy" "$test_home/.codex/skills/omarchy"
ln -s "$test_omarchy/default/agents/skills/missing" "$test_home/.claude/skills/missing"

cat >"$test_bin/codex" <<'SH'
#!/bin/bash
printf 'codex-cli 1.2.3\n'
SH
chmod +x "$test_bin/codex"

output=$(cd "$test_repo" && HOME="$test_home" OMARCHY_PATH="$test_omarchy" PATH="$test_bin:$PATH" \
  "$ROOT/bin/omarchy-agent-doctor" --json)

jq -e '.default_agent == "codex" and .binary_available == true and .version == "codex-cli 1.2.3"' \
  <<<"$output" >/dev/null || fail "agent doctor reports the selected agent and version"
pass "agent doctor reports the selected agent and version"

jq -e '.instruction_files == ["AGENTS.md", "CLAUDE.md"]' <<<"$output" >/dev/null ||
  fail "agent doctor reports repository instruction files"
pass "agent doctor reports repository instruction files"

jq -e '.skills.installed | any(.name == "omarchy" and .package_owned == true and .broken == false)' \
  <<<"$output" >/dev/null || fail "agent doctor identifies packaged Omarchy skill links"
pass "agent doctor identifies packaged Omarchy skill links"

jq -e '.skills.broken | any(.name == "missing" and .broken == true and .package_owned == true)' <<<"$output" >/dev/null ||
  fail "agent doctor identifies broken skill links"
jq -e '.warnings | any(contains("Broken skill link:"))' <<<"$output" >/dev/null ||
  fail "agent doctor warns about broken skill links"
pass "agent doctor reports broken skill links without following them"

rm -f "$test_home/.config/omarchy/defaults/agent"
output=$(cd "$test_repo" && HOME="$test_home" OMARCHY_PATH="$test_omarchy" PATH="$test_bin:$PATH" \
  "$ROOT/bin/omarchy-agent-doctor" --json)
jq -e '.default_agent == "" and .binary_available == false and (.warnings | any(contains("No default")))' \
  <<<"$output" >/dev/null || fail "agent doctor handles an unconfigured default"
pass "agent doctor handles an unconfigured default"

if "$ROOT/bin/omarchy-agent-doctor" --bogus >/dev/null 2>&1; then
  fail "agent doctor rejects unsupported arguments"
fi
pass "agent doctor rejects unsupported arguments"
