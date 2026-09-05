#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq
require_command python3

test_home=$(mktemp -d)
test_bin=$(mktemp -d)
trap 'rm -rf "$test_home" "$test_bin"' EXIT

usage_dir="$test_home/.local/state/omarchy/agents/usage"
update_log="$test_home/update.log"
mkdir -p "$usage_dir"

cat >"$test_bin/omarchy-agent-usage-update" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >"$UPDATE_LOG"
if [[ ${FAIL_UPDATE:-0} == "1" ]]; then
  exit 1
else
  exit 0
fi
EOF
chmod +x "$test_bin/omarchy-agent-usage-update"

cat >"$usage_dir/claude.json" <<'EOF'
{
  "id": "claude",
  "name": "Claude Code",
  "ready": true,
  "todayPrompts": 3,
  "todaySessions": 2,
  "todayTotalTokens": 42,
  "todayTokensByModel": { "claude-test": 42 },
  "recentDays": [{ "date": "2026-08-31", "messageCount": 3 }],
  "totalPrompts": 9,
  "totalSessions": 4,
  "activeDays": 2,
  "activeDates": ["2026-08-30", "2026-08-31"],
  "modelUsage": { "claude-test": { "inputTokens": 30, "outputTokens": 12 } },
  "limits": { "secret": "not-for-sync" },
  "authError": "not-for-sync"
}
EOF

cat >"$usage_dir/codex.json" <<'EOF'
{
  "id": "codex",
  "name": "Codex",
  "scope": "device",
  "hasLocalStats": false,
  "hasPromptStats": false,
  "totalPrompts": "7"
}
EOF

printf '%s\n' '{not-json' >"$usage_dir/broken.json"

snapshot=$(HOME="$test_home" XDG_STATE_HOME="" HOSTNAME="Headless Build Server" UPDATE_LOG="$update_log" PATH="$test_bin:$PATH" \
  "$ROOT/bin/omarchy-agent-usage-snapshot" 2>"$test_home/stderr")

jq -e '
  .schemaVersion == 1 and
  .deviceId == "Headless-Build-Server" and
  (.updatedAt | test("Z$")) and
  .providers.claude.providerName == "Claude Code" and
  .providers.claude.todayTotalTokens == 42 and
  .providers.codex.totalPrompts == 7 and
  .providers.codex.hasLocalStats == false and
  (.providers.claude | has("limits") | not) and
  (.providers.claude | has("authError") | not)
' >/dev/null <<<"$snapshot" || fail "snapshot publishes compatible usage metrics without private collector state"
pass "snapshot publishes compatible usage metrics without private collector state"

grep -q 'ignoring broken.json' "$test_home/stderr" || fail "snapshot reports malformed usage records"
pass "snapshot reports malformed usage records"

output_path="$test_home/sync/nested-server.json"
HOME="$test_home" XDG_STATE_HOME="" UPDATE_LOG="$update_log" PATH="$test_bin:$PATH" \
  "$ROOT/bin/omarchy-agent-usage-snapshot" --output "$output_path" --device-id nested-server --force --except codex claude 2>/dev/null

[[ $(jq -r '.deviceId' "$output_path") == "nested-server" ]] || fail "snapshot writes the requested device ID"
[[ $(jq -r '.providers | keys | join(",")' "$output_path") == "claude" ]] || fail "snapshot filters providers requested by the caller"
[[ $(<"$update_log") == "--force --except codex claude" ]] || fail "snapshot forwards collector selection and refresh flags"
pass "snapshot atomically publishes selected agents to a file"

printf '%s\n' 'keep-existing' >"$output_path"
if HOME="$test_home" XDG_STATE_HOME="" FAIL_UPDATE=1 UPDATE_LOG="$update_log" PATH="$test_bin:$PATH" \
  "$ROOT/bin/omarchy-agent-usage-snapshot" --output "$output_path" 2>/dev/null; then
  fail "snapshot reports a collector refresh failure"
fi
[[ $(<"$output_path") == "keep-existing" ]] || fail "failed refresh leaves the previous snapshot intact"
pass "failed refresh leaves the previous snapshot intact"
