#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
export ROOT

node <<'JS'
const search = require(`${process.env.ROOT}/shell/plugins/launcher/LauncherSearch.js`)

function fail(description, detail) {
  if (detail) console.error(detail)
  console.error(`not ok - ${description}`)
  process.exit(1)
}

function pass(description) {
  console.log(`ok - ${description}`)
}

function assert(condition, description, detail) {
  if (!condition) fail(description, detail)
  pass(description)
}

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
assert(
  contactMatches.length === 1 && contactMatches[0] === 'Google Contacts',
  'contact search only returns direct contact matches',
  `matches: ${contactMatches.join(', ')}`
)

assert(
  search.fuzzyScore(entries[1], 'contact') < 0,
  'calculator does not match contact as a loose subsequence'
)

const acronymMatches = search.sortedEntries(entries, 'gc').map(row => search.entryName(row.entry))
assert(
  acronymMatches[0] === 'Google Contacts',
  'short acronym matching still works'
)

const directMatches = search.sortedEntries(entries, 'obs').map(row => search.entryName(row.entry))
assert(
  directMatches[0] === 'OBS Studio',
  'direct app-name matching still works'
)
JS
