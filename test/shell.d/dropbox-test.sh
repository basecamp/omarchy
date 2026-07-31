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

const folders = dropbox.parseFolders(JSON.stringify({
  ok: true,
  accountPath: '/home/user/Dropbox',
  path: '/home/user/Dropbox/Photos',
  parentPath: '/home/user/Dropbox',
  atRoot: false,
  folders: [{ name: 'Trips', path: '/home/user/Dropbox/Photos/Trips', excluded: false, browsable: true, childCount: 2 }]
}))
assert(folders.ok === true && folders.atRoot === false, 'dropbox parses folder listing flags')
assertEqual(folders.folders.length, 1, 'dropbox preserves folder rows')
assertEqual(folders.parentPath, '/home/user/Dropbox', 'dropbox parses the parent path')

assertEqual(dropbox.parseFolders('not json').ok, false, 'dropbox rejects malformed folder payloads')
assertEqual(dropbox.parseFolders('').folders.length, 0, 'dropbox defaults an empty folder payload')
assert(dropbox.parseFolders(JSON.stringify({ ok: true })).folders.length === 0, 'dropbox defaults a missing folder array')

assertEqual(dropbox.folderMeta({ excluded: true }), 'Not synced', 'dropbox labels excluded folders')
assertEqual(dropbox.folderMeta({ excluded: false, childCount: 0 }), 'Synced', 'dropbox labels a synced leaf folder')
assertEqual(dropbox.folderMeta({ excluded: false, childCount: 1 }), 'Synced · 1 folder', 'dropbox labels a single child folder')
assertEqual(dropbox.folderMeta({ excluded: false, childCount: 3 }), 'Synced · 3 folders', 'dropbox labels multiple child folders')
JS
