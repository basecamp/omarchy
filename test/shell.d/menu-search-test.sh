#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const search = requireFromRoot('shell/services/MenuSearch.js')

const menuEntry = (id, label) => ({ id, parent: 'system', kind: 'action', label, description: '', aliases: [] })
const suspend = menuEntry('system.suspend', 'Suspend')
const screensaver = menuEntry('system.screensaver', 'Screensaver')
const shutdown = menuEntry('system.shutdown', 'Shutdown')

assert(search.matchesQuery(suspend, 'ss', true), 'menu fzf chunks match separated letters')
assert(!search.matchesQuery(shutdown, 'ss', true), 'menu fuzzy matching never crosses from a label into its id')
assertEqual(search.rank(suspend, 'ss').tier, 70, 'menu fuzzy matches stay in their own tier')
assert(
  search.compareRanks(search.rank(suspend, 'ss'), search.rank(screensaver, 'ss')) < 0,
  'menu fzf rank prefers the shorter equivalent chunk match'
)

const defaultMenu = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const systemSsMatches = defaultMenu
  .filter(entry => entry.parent === 'system' && search.matchesQuery(entry, 'ss', true))
  .sort((a, b) => search.compareRanks(search.rank(a, 'ss'), search.rank(b, 'ss')))
  .map(entry => entry.id)
assertDeepEqual(
  systemSsMatches,
  ['system.suspend', 'system.screensaver'],
  'system ss search lists Suspend first and excludes Shutdown'
)

assert(
  search.compareRanks(
    search.rank(menuEntry('tools.one', 'Suspend'), 'sud'),
    search.rank({ ...menuEntry('tools.two', 'Sound'), kind: 'menu' }, 'sud')
  ) < 0,
  'menu ranks consecutive chunks before applying the menu-kind tie-breaker'
)

const boundary = menuEntry('tools.one', 'System Xray')
const embedded = menuEntry('tools.two', 'Asystem Xray')
assert(
  search.compareRanks(search.rank(boundary, 'sx'), search.rank(embedded, 'sx')) < 0,
  'menu fzf rank prefers matches beginning at a word boundary'
)

const app = { id: 'apps.google-contacts', parent: 'apps', kind: 'app', label: 'Google Contacts', description: '', aliases: [], acronym: 'gc' }
assert(search.matchesQuery(app, 'gc', true), 'app rows retain short acronym matching')
assert(!search.matchesQuery({ ...app, label: 'Calculator', id: 'apps.calculator', acronym: 'c' }, 'cltr', true), 'app rows reject loose subsequences')
JS
