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

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
launch_log="$test_tmp/launch-log"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
:
SH

cat >"$mock_bin/omarchy-plugin-enable" <<'SH'
#!/bin/bash
:
SH

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_TEST_LAUNCH_LOG"
SH

cat >"$mock_bin/uwsm-app" <<'SH'
#!/bin/bash
printf 'direct:%s\n' "$*" >"$OMARCHY_TEST_LAUNCH_LOG"
SH

chmod +x "$mock_bin"/*

PATH="$mock_bin:$PATH" OMARCHY_TEST_LAUNCH_LOG="$launch_log" \
  bash "$ROOT/bin/omarchy-install-service-dropbox"
for _ in {1..50}; do
  [[ -s $launch_log ]] && break
  sleep 0.01
done
grep -Fxq 'uwsm-app -- dropbox-cli start' "$launch_log" ||
  fail "Dropbox installer detaches the service from its terminal" "$(cat "$launch_log")"
pass "Dropbox installer detaches the service from its terminal"
