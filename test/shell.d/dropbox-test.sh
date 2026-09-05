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

run_node_test "dropbox login retry wiring" <<'JS'
const fs = require('fs')
const service = fs.readFileSync(root + '/shell/plugins/panels/dropbox/Service.qml', 'utf8')

assert(/function login\(\)[^}]*loginRetry\.restart\(\)/s.test(service), 'login starts the status-poll retry for the link URL')
assert(/if \(loginRetry\.running\) openAuthUrlFrom\(statusText\)/.test(service), 'status poll feeds the pending login the link URL')
assert(/Dropbox offered no login link[\s\S]{0,200}root\.actionStatus = root\.lastError/.test(service), 'an exhausted login retry surfaces an error that survives the next status poll')
JS

# The account block in info.json marks a linked account; the sync folder only
# appears once the first sync starts. A freshly linked account must not read as
# unauthenticated in that window.
require_command python3
require_command jq

DROPBOX_HOME=$(mktemp -d)
trap 'rm -rf "$DROPBOX_HOME"' EXIT

STUB_BIN="$DROPBOX_HOME/bin"
mkdir -p "$STUB_BIN" "$DROPBOX_HOME/.dropbox"
cat >"$STUB_BIN/dropbox-cli" <<'EOF'
#!/bin/bash
echo "Starting..."
EOF
chmod +x "$STUB_BIN/dropbox-cli"

cat >"$DROPBOX_HOME/.dropbox/info.json" <<EOF
{"personal": {"path": "$DROPBOX_HOME/Dropbox", "subscription_type": "basic"}}
EOF

result=$(HOME="$DROPBOX_HOME" PATH="$STUB_BIN:$PATH" python3 "$ROOT/shell/plugins/panels/dropbox/status.py" 5)

[[ $(jq -r '.authenticated' <<<"$result") == "true" ]] ||
  fail "dropbox status reports a linked account before its folder exists" "$result"
pass "dropbox status reports a linked account before its folder exists"

[[ $(jq -r '.usedBytes' <<<"$result") == "0" ]] ||
  fail "dropbox status survives scanning a folder that is not there yet" "$result"
pass "dropbox status survives scanning a folder that is not there yet"

rm "$DROPBOX_HOME/.dropbox/info.json"
result=$(HOME="$DROPBOX_HOME" PATH="$STUB_BIN:$PATH" python3 "$ROOT/shell/plugins/panels/dropbox/status.py" 5)

[[ $(jq -r '.authenticated' <<<"$result") == "false" ]] ||
  fail "dropbox status keeps an unlinked install on the login screen" "$result"
pass "dropbox status keeps an unlinked install on the login screen"
