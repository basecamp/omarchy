#!/bin/bash

set -e

source "$(dirname "$0")/base-test.sh"

run_node_test "dropbox model helpers" <<'JS'
const dropbox = requireFromRoot('shell/plugins/panels/dropbox/Model.js')

assertEqual(dropbox.fileKind('photo.JPG'), 'image', 'dropbox detects image files')
assertEqual(dropbox.fileKind('clip.webm'), 'video', 'dropbox detects video files')
assertEqual(dropbox.fileKind('report.pdf'), 'document', 'dropbox detects document files')
assertEqual(dropbox.fileKind('archive.zip'), 'misc', 'dropbox falls back to misc files')
assertEqual(dropbox.formatBytes(1530), '1.53 KB', 'dropbox formats small byte counts')
assertEqual(dropbox.formatBytes(2_000_000_000), '2 GB', 'dropbox formats gigabytes')
assertEqual(dropbox.formatPercent(7.25), '7.3%', 'dropbox formats small percentages')
assertEqual(dropbox.usageText(1000, 2000, true), '1 KB of 2 KB', 'dropbox formats known quota usage')
assertEqual(dropbox.usageText(1000, 0, false), '1 KB', 'dropbox formats unknown quota usage')

const parsed = dropbox.parseStatus(JSON.stringify({
  installed: true,
  running: true,
  authenticated: true,
  files: [{ name: 'x.txt' }]
}))
assert(parsed.installed && parsed.running && parsed.authenticated, 'dropbox parses status booleans')
assertEqual(parsed.files.length, 1, 'dropbox preserves file rows')

assertEqual(
  dropbox.fileMeta({ modifiedTs: 1000, folder: 'Docs' }, 1000 * 1000 + 3600 * 1000),
  '1h ago · Docs',
  'dropbox file metadata includes relative time and folder'
)
JS

require_command jq
require_command python3

# The status helper prefers the Dropbox API (DROPBOX_API_TOKEN) over the
# hardcoded plan quotas, since plans ignore bonus/referral space.
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.dropbox" "$TEST_HOME/Dropbox"
printf 'x' >"$TEST_HOME/Dropbox/file.txt"
cat >"$TEST_HOME/.dropbox/info.json" <<EOF
{"personal": {"path": "$TEST_HOME/Dropbox", "host": 1, "is_team": false, "subscription_type": "Basic"}}
EOF

run_status() {
  env -i HOME="$TEST_HOME" PATH="$PATH" DROPBOX_API_TOKEN="${1:-}" \
    python3 "$ROOT/shell/plugins/panels/dropbox/status.py"
}

# Without a token, quota falls back to the hardcoded plan quota.
result=$(run_status "")
[[ $(jq -r '.quotaBytes' <<<"$result") == "2000000000" ]] ||
  fail "dropbox status falls back to plan quota without a token" "$result"
pass "dropbox status falls back to plan quota without a token"

# With a token but no reachable API, it still falls back instead of failing.
result=$(run_status "invalid-token")
[[ $(jq -r '.quotaBytes' <<<"$result") == "2000000000" ]] ||
  fail "dropbox status falls back to plan quota when the API is unreachable" "$result"
pass "dropbox status falls back to plan quota when the API is unreachable"

# With a working API, server-reported usage and quota win over the plan table.
MOCK_BIN=$(mktemp -d)
cat >"$MOCK_BIN/python3" <<'EOF'
#!/bin/bash
exec /usr/bin/python3 - "$@" <<'PYEOF'
import json, sys, urllib.request

class FakeResponse:
  def __enter__(self): return self
  def __exit__(self, *args): return False
  def read(self): return json.dumps({"used": 3_500_000_000, "allocation": {"allocated": 8_000_000_000}}).encode()

urllib.request.urlopen = lambda request, timeout=5: FakeResponse()

script = sys.argv[1]
sys.argv = [script] + sys.argv[2:]
with open(script) as handle:
  exec(compile(handle.read(), script, "exec"), {"__name__": "__main__"})
PYEOF
EOF
chmod +x "$MOCK_BIN/python3"

result=$(env -i HOME="$TEST_HOME" PATH="$MOCK_BIN:$PATH" DROPBOX_API_TOKEN="valid-token" \
  "$MOCK_BIN/python3" "$ROOT/shell/plugins/panels/dropbox/status.py")
[[ $(jq -r '.usedBytes' <<<"$result") == "3500000000" && $(jq -r '.quotaBytes' <<<"$result") == "8000000000" ]] ||
  fail "dropbox status uses API usage and quota when a token is configured" "$result"
pass "dropbox status uses API usage and quota when a token is configured"
