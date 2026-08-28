#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
mock_bin="$test_tmp/bin"
mkdir -p "$test_home/.codex" "$test_home/.claude" "$test_home/.config/opencode" "$mock_bin" "$test_tmp/work"

for agent in codex claude opencode pi; do
  printf '#!/bin/bash\nexit 0\n' >"$mock_bin/$agent"
  chmod +x "$mock_bin/$agent"
done

cat >"$test_home/.codex/config.toml" <<'EOF'
[mcp_servers.railway]
command = "secret-command"
args = ["--token", "super-secret-token"]
EOF

cat >"$test_home/.claude.json" <<'EOF'
{"mcpServers":{"sentry":{"url":"https://secret.example/token"}}}
EOF

cat >"$test_home/.config/opencode/opencode.jsonc" <<'EOF'
{
  // OpenCode accepts JSONC comments and trailing commas.
  "mcp": {"docs": {"headers": {"Authorization": "Bearer hidden"}},},
}
EOF

output=$(cd "$test_tmp/work" && HOME="$test_home" PATH="$mock_bin:/usr/bin" "$ROOT/bin/omarchy-agent-mcp" list --json)
python3 - "$output" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["ok"] is True
assert {(row["agent"], row["name"]) for row in result["servers"]} == {
  ("claude", "sentry"),
  ("codex", "railway"),
  ("opencode", "docs"),
}
assert next(row for row in result["agents"] if row["name"] == "pi")["adapter"] == "unsupported"
PY
[[ $output != *"super-secret-token"* && $output != *"secret.example"* && $output != *"Bearer hidden"* ]] ||
  fail "agent MCP JSON does not expose configuration secrets"
pass "agent MCP list discovers server names without exposing secrets"

doctor_output=$(cd "$test_tmp/work" && HOME="$test_home" PATH="$mock_bin:/usr/bin" "$ROOT/bin/omarchy-agent-mcp" doctor)
[[ $doctor_output == *"Configured MCP servers: 3"* && $doctor_output == *"Unsupported adapters: pi"* ]] ||
  fail "agent MCP doctor summarizes supported and unsupported adapters"
pass "agent MCP doctor reports an honest adapter summary"

printf '{broken' >"$test_home/.claude.json"
if cd "$test_tmp/work" && HOME="$test_home" PATH="$mock_bin:/usr/bin" "$ROOT/bin/omarchy-agent-mcp" doctor --json >"$test_tmp/doctor.json"; then
  fail "agent MCP doctor fails on an unreadable configuration"
fi
jq -e '.ok == false and (.issues | length == 1) and .issues[0].agent == "claude"' "$test_tmp/doctor.json" >/dev/null ||
  fail "agent MCP doctor returns structured parse failures"
if grep -q 'super-secret-token\|secret.example\|Bearer hidden' "$test_tmp/doctor.json"; then
  fail "agent MCP doctor failure output does not expose configuration secrets"
fi
pass "agent MCP doctor diagnoses malformed configuration safely"

if "$ROOT/bin/omarchy-agent-mcp" add example >/dev/null 2>&1; then
  fail "agent MCP command rejects mutating operations"
fi
pass "agent MCP command is read-only"
