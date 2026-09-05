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

require_command python3

# The plan table describes what a plan ships with, so an account carrying bonus
# space needs the override to win. Everything unusable has to defer to the
# table instead, since a broken setting must not blank out the quota.
read_override() {
  HELPER="$ROOT/shell/plugins/panels/dropbox/status.py" RAW="$1" python3 - <<'PY'
import importlib.machinery, importlib.util, os

loader = importlib.machinery.SourceFileLoader("status", os.environ["HELPER"])
spec = importlib.util.spec_from_loader(loader.name, loader)
status = importlib.util.module_from_spec(spec)
loader.exec_module(status)

print(status.quota_override_bytes(os.environ["RAW"]))
PY
}

assert_override() {
  local raw=$1 expected=$2 description=$3
  local actual

  actual=$(read_override "$raw")
  [[ $actual == "$expected" ]] || fail "$description" "expected $expected, got $actual"
  pass "$description"
}

assert_override 21380 21380000000 "dropbox override reads megabytes as bytes"
assert_override 0 0 "dropbox override of zero defers to the plan table"
assert_override -5 0 "dropbox override refuses negative megabytes"
assert_override "" 0 "dropbox override ignores a blank setting"
assert_override "lots" 0 "dropbox override ignores a non-numeric setting"
