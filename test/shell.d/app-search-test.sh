#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const search = requireFromRoot('shell/services/AppSearch.js')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
const appLibraryQml = fs.readFileSync(path.join(root, 'shell/services/AppLibrary.qml'), 'utf8')

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

// The menu's Apps submenu is the launcher now: app rows launch and uninstall
// through the shared app library instead of running commands themselves.
const activateMatch = menuQml.match(/function activateIndex\(index, fromPointer\) \{([\s\S]*?)\n  \}/)
assert(activateMatch, 'menu activateIndex function exists')
assert(
  activateMatch[1].includes('root.appLibrary.launch('),
  'menu routes app launch through the shared app library'
)
assert(
  !activateMatch[1].includes('entry.execute()'),
  'menu does not execute desktop entries directly'
)

const confirmDeleteMatch = menuQml.match(/function confirmDelete\(\) \{([\s\S]*?)\n  \}/)
assert(confirmDeleteMatch, 'menu confirmDelete function exists')
assert(
  confirmDeleteMatch[1].includes('root.appLibrary.remove('),
  'menu delete routes through the shared app library'
)
assert(
  confirmDeleteMatch[1].includes('root.cancel()'),
  'menu delete closes the menu after confirmation'
)

assert(
  /function remove\(desktopId, name\) \{[\s\S]*?omarchy-remove-launcher-entry[\s\S]*?\n  \}/.test(appLibraryQml),
  'app library remove runs the remover through the shell'
)

assert(
  /function launch\(desktopId, name\) \{[\s\S]*?gtk-launch[\s\S]*?\n  \}/.test(appLibraryQml) &&
    appLibraryQml.includes('Util.execDetached("gtk-launch "'),
  'app library runs desktop entry launch through the shell'
)

assert(
  /function iconIndexScanCommand\(\)[\s\S]*-path "\*\/apps\/\*" -o -path "\*\/devices\/\*"/.test(appLibraryQml),
  'app library fallback icon index includes device icons'
)

assert(
  /if \(active === "apps"\) \{[\s\S]*?rows\.sort\(function\(a, b\)/.test(menuQml),
  'apps menu enforces alphabetical display order after provider refreshes'
)

const iconSourceMatch = appLibraryQml.match(/function iconSource\(icon\) \{([\s\S]*?)\n  \}/)
assert(iconSourceMatch, 'app library iconSource function exists')
assert(
  iconSourceMatch[1].indexOf('root.iconIndex[value]') < iconSourceMatch[1].indexOf('Quickshell.iconPath(value, true)'),
  'app library prefers indexed app icons over ambiguous themed icons'
)

const openMatch = menuQml.match(/function openExistingMenu\(initialMenu\) \{([\s\S]*?)\n  \}/)
assert(openMatch, 'menu openExistingMenu function exists')
assert(
  openMatch[1].includes('root.appLibrary.refreshIcons()'),
  'menu refreshes the shared icon index when opened'
)
JS
