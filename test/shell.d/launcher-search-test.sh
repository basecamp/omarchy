#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const search = requireFromRoot('shell/plugins/launcher/LauncherSearch.js')
const launcherQml = fs.readFileSync(path.join(root, 'shell/plugins/launcher/Launcher.qml'), 'utf8')

const entries = [
  {
    name: 'Google Contacts',
    genericName: 'Address Book',
    comment: 'Manage contacts',
    keywords: ['contacts', 'address book', 'people'],
    id: 'google-contacts.desktop'
  },
  {
    name: 'Calculator',
    genericName: 'Calculator',
    comment: 'Perform arithmetic, scientific or financial calculations',
    keywords: ['calculation', 'arithmetic', 'scientific', 'financial'],
    id: 'org.gnome.Calculator.desktop'
  },
  {
    name: 'OBS Studio',
    genericName: 'Streaming/Recording Software',
    comment: 'Free and Open Source Streaming/Recording Software',
    keywords: ['streaming', 'recording', 'capture'],
    id: 'com.obsproject.Studio.desktop'
  },
  {
    name: 'Aether',
    genericName: '',
    comment: 'Minimal internet radio player',
    keywords: ['audio', 'music', 'radio'],
    id: 'io.github.taqi.aether.desktop'
  },
  {
    name: 'Xournal++',
    genericName: 'Notetaking',
    comment: 'Take handwritten notes',
    keywords: ['notes', 'pdf', 'annotation'],
    id: 'com.github.xournalpp.xournalpp.desktop'
  },
  {
    name: 'RustDesk',
    genericName: 'Remote Desktop',
    comment: 'Remote desktop control',
    keywords: ['remote', 'desktop', 'control'],
    id: 'com.rustdesk.RustDesk.desktop'
  }
]

const contactMatches = search.sortedEntries(entries, 'contact').map(row => search.entryName(row.entry))
assertDeepEqual(contactMatches, ['Google Contacts'], 'contact search only returns direct contact matches')

assert(
  search.fuzzyScore(entries[1], 'contact') < 0,
  'calculator does not match contact as a loose subsequence'
)

const acronymMatches = search.sortedEntries(entries, 'gc').map(row => search.entryName(row.entry))
assertEqual(acronymMatches[0], 'Google Contacts', 'short acronym matching still works')

const directMatches = search.sortedEntries(entries, 'obs').map(row => search.entryName(row.entry))
assertEqual(directMatches[0], 'OBS Studio', 'direct app-name matching still works')

assert(
  /function select\(delta\)[\s\S]*root\.hoverArmed = false[\s\S]*root\.selectedIndex =/.test(launcherQml),
  'launcher keyboard navigation disarms stale hover before moving selection'
)

const confirmDeleteMatch = launcherQml.match(/function confirmDelete\(\) \{([\s\S]*?)\n  \}/)
assert(confirmDeleteMatch, 'launcher confirmDelete function exists')
assert(
  confirmDeleteMatch[1].includes('root.dismiss()'),
  'launcher delete closes launcher after confirmation'
)
assert(
  confirmDeleteMatch[1].includes('Util.hyprExecCommand(command)'),
  'launcher delete routes remover through Hyprland'
)

const activateMatch = launcherQml.match(/function activateIndex\(index\) \{([\s\S]*?)\n  \}/)
assert(activateMatch, 'launcher activateIndex function exists')
assert(
  !activateMatch[1].includes('entry.execute()'),
  'launcher does not execute desktop entries directly'
)
assert(
  activateMatch[1].includes('gtk-launch') && activateMatch[1].includes('Util.hyprExecCommand'),
  'launcher routes desktop entry launch through Hyprland'
)
JS
