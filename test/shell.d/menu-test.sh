#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
const defaultMenuJsonc = fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8')

const parsed = menu.parseMenuJsonc(`
{
  // comment
  "items": {
    "root": { "label": "Go" },
    "style": { "label": "Style" },
    "style.theme": {
      "label": "Themes",
      "aliases": "theme",
      "description": "appearance colors",
      "action": "omarchy-theme-set"
    },
  },
}
`)

assertEqual(parsed.length, 3, 'menu parses JSONC with comments and trailing commas')
assertDeepEqual(
  parsed.find(item => item.id === 'style.theme'),
  {
    id: 'style.theme',
    parent: 'style',
    kind: 'action',
    icon: '',
    iconFont: '',
    label: 'Themes',
    title: '',
    target: '',
    description: 'appearance colors',
    action: 'omarchy-theme-set',
    provider: '',
    aliases: ['theme'],
    when: '',
    checked: ''
  },
  'menu normalizes parsed items'
)

const user = [
  menu.normalizeItem('style.theme', { label: 'Theme picker', aliases: ['theme', 'colors'], action: 'custom-theme' }),
  menu.normalizeItem('tools', { label: 'Tools' })
]
const merged = menu.mergeMenuSources(parsed, user)
assertEqual(merged.items['style.theme'].label, 'Theme picker', 'menu user entries override default entries')
assertEqual(merged.items['style.theme'].order, 2, 'menu preserves original order on override')
assert(merged.items.root, 'menu injects root when merging sources')

assertEqual(menu.slugify('Power Saver!'), 'power-saver', 'menu slugifies provider rows')
assertEqual(menu.pathFor(merged.items, 'style.theme'), 'Style › Theme picker', 'menu builds item paths')
assertEqual(menu.parentPathFor(merged.items, 'style.theme'), 'Style', 'menu builds parent paths')
assert(menu.isDescendantOf(merged.items, 'style.theme', 'style'), 'menu detects descendants')
assertEqual(menu.childCount(merged.items, merged.itemOrder, 'style'), 1, 'menu counts children')
assertEqual(menu.labelFor({ id: 'style.theme', label: 'Theme', checked: 'cmd' }, { 'style.theme': true }), 'Theme ✓', 'menu appends checked marker')

const visibilityItems = {
  hardware: menu.normalizeItem('hardware', { label: 'Hardware' }),
  laptop: menu.normalizeItem('hardware.laptop', { label: 'Laptop', when: 'is-laptop', action: 'toggle-laptop' }),
  nested: menu.normalizeItem('nested', { label: 'Nested' }),
  branch: menu.normalizeItem('nested.branch', { label: 'Branch' }),
  leaf: menu.normalizeItem('nested.branch.leaf', { label: 'Leaf', when: 'has-leaf', action: 'run-leaf' }),
  dynamic: menu.normalizeItem('dynamic', { label: 'Dynamic', provider: 'items' })
}
const visibilityOrder = Object.keys(visibilityItems)
assert(!menu.isVisible(visibilityItems, visibilityOrder, { 'hardware.laptop': false }, visibilityItems.hardware), 'menu hides a submenu with no visible children')
assert(menu.isVisible(visibilityItems, visibilityOrder, { 'hardware.laptop': true }, visibilityItems.hardware), 'menu shows a submenu with a visible child')
assert(!menu.isVisible(visibilityItems, visibilityOrder, { 'nested.branch.leaf': false }, visibilityItems.nested), 'menu hides recursively empty submenus')
assert(menu.isVisible(visibilityItems, visibilityOrder, {}, visibilityItems.dynamic), 'menu keeps provider-backed submenus visible')

const entry = merged.items['style.theme']
assert(menu.matchesQuery(entry, 'theme', true), 'menu matches labels and aliases')
assert(menu.matchesQuery(entry, 'colors', true), 'menu matches aliases')
assert(!menu.matchesQuery(entry, 'missing', true), 'menu rejects missing terms')
assert(!menu.matchesQuery(entry, 'theme', false), 'menu hides invisible matches')
assert(menu.searchScore(merged.items, entry, 'theme') < menu.searchScore(merged.items, entry, 'appearance'), 'menu scores name matches above description matches')

assertDeepEqual(
  menu.displayRow(merged.items, merged.itemOrder, {}, entry, 'Style', 12, 'search'),
  {
    itemId: 'style.theme',
    kind: 'action',
    icon: '',
    iconFont: '',
    appIcon: '',
    appId: '',
    label: 'Theme picker',
    target: 'style.theme',
    detail: 'Style',
    path: 'Style › Theme picker',
    childCount: 0,
    action: 'custom-theme',
    provider: '',
    score: 12,
    section: 'search'
  },
  'menu builds display rows'
)

const defaultItems = menu.parseMenuJsonc(defaultMenuJsonc)
const defaultById = Object.fromEntries(defaultItems.map(item => [item.id, item]))

// Needs the real menu: app rows sort after all menu items, and only at that
// item count does the order tiebreak alone bury an installed app.
const rankBase = menu.mergeMenuSources(defaultItems, [])
const ranked = menu.mergeAppRows(rankBase.items, rankBase.itemOrder, [
  { id: 'apps.brave', parent: 'apps', kind: 'app', label: 'Brave', description: '', aliases: [] },
  { id: 'apps.fontforge', parent: 'apps', kind: 'app', label: 'FontForge', description: '', aliases: [] }
])
const rankScore = (id, query) => menu.searchScore(ranked.items, ranked.items[id], query)
assert(
  ['install.browser.brave', 'remove.browser.brave', 'setup.default.browser.brave'].every(
    id => rankScore('apps.brave', 'brave') < rankScore(id, 'brave')
  ),
  'menu ranks an installed app above menu entries matching the query equally well'
)
assert(
  rankScore('style.font', 'font') < rankScore('apps.fontforge', 'font'),
  'menu keeps a better-matching menu entry above a weaker app match'
)
const triggerItems = defaultItems.filter(item => item.parent === 'trigger')
assertEqual(
  triggerItems[0].id,
  'trigger.emoji',
  'menu lists Emoji first under Trigger'
)
assertEqual(
  defaultById['trigger.emoji'].action,
  'omarchy-menu-emoji',
  'menu opens the emoji picker from Trigger'
)
assert(
  defaultById['update.omarchy'].icon === '\ue900',
  'menu update Omarchy entry uses the Omarchy glyph'
)
assert(
  defaultById['update.omarchy'].iconFont === 'omarchy',
  'menu update Omarchy entry renders the private glyph with the Omarchy font'
)
assert(
  defaultById['setup.input'].action.includes('input.lua'),
  'menu keeps Input as a direct config action'
)
assert(
  defaultById['setup.direct-boot'].action.includes('omarchy-setup-direct-boot'),
  'menu places Direct Boot directly under Setup'
)
assertEqual(
  defaultItems.findIndex(item => item.id === 'setup.direct-boot'),
  defaultItems.findIndex(item => item.id === 'setup.input') + 1,
  'menu lists Direct Boot immediately below Input'
)
assert(
  defaultById['setup.security.passwordless-sudo'].action.includes('omarchy-sudo-passwordless'),
  'menu places Passwordless Sudo under Setup > Security'
)
assert(
  !defaultById['trigger.toggle.direct-boot'] && !defaultById['trigger.toggle.passwordless-sudo'],
  'menu removes the relocated toggles from Trigger > Toggle'
)
assert(
  defaultById['style.bar.position'].kind === 'menu',
  'menu groups Menu Bar positions in a submenu'
)
assert(
  ['top', 'bottom', 'left', 'right'].every(position => defaultById[`style.bar.position.${position}`].action === `omarchy-bar position ${position}`),
  'menu lists all Menu Bar positions under Position'
)
assertEqual(
  defaultById['style.bar.transparency'].action,
  'omarchy-bar transparent toggle',
  'menu exposes Menu Bar transparency as a toggle'
)
assertEqual(
  defaultById['trigger.hardware.laptop-display'].when,
  'omarchy-hw-laptop',
  'menu only shows Laptop Display on laptops'
)
assertEqual(
  defaultById['trigger.hardware.mirror-display'].when,
  'omarchy-hw-laptop',
  'menu only shows Mirror Display on laptops'
)
assertEqual(
  defaultById['trigger.capture.screenrecord.webcam'].when,
  'omarchy-hw-webcam',
  'menu only shows webcam screen recording when a webcam is available'
)
assert(
  /font\.family: row\.iconFont\.length > 0 \? row\.iconFont : root\.fontFamily/.test(menuQml),
  'menu rows support per-icon font families'
)

assert(
  /function select\(delta\)[\s\S]*root\.disarmPointer\(\)[\s\S]*selectedIndex =/.test(menuQml),
  'menu keyboard navigation disarms pointer selection'
)
assert(
  /function setFilter\(nextFilter\)[\s\S]*root\.disarmPointer\(\)/.test(menuQml),
  'menu filter changes disarm pointer selection'
)
assert(
  /function setActiveMenu\(id, pushHistory, fromPointer\)[\s\S]*if \(fromPointer\) pointerGate\.allowInitialSample\(\)\s*else root\.disarmPointer\(\)/.test(menuQml),
  'menu route changes only accept an initial pointer sample for mouse activation'
)
assert(
  /\(event\.key === Qt\.Key_Backspace \|\| event\.key === Qt\.Key_Left\) && !root\.filterText[\s\S]*root\.goBack\(\)/.test(menuQml),
  'menu Left key follows empty-filter Backspace navigation'
)
assert(
  /PointerMoveGate\s*\{[\s\S]*id: pointerGate[\s\S]*referenceItem: card[\s\S]*\}/.test(menuQml),
  'menu uses shared pointer movement gate in card coordinates'
)
assert(
  /function disarmPointer\(\)[\s\S]*pointerGate\.reset\(\)/.test(menuQml),
  'menu resets pointer movement gate when pointer selection is disarmed'
)
// App rows are rebuilt from scratch on every desktop-entry rescan. The merge
// must be idempotent and must never carry an orphan id forward, or a single
// lost write turns into an app listed twice (and thrice, and so on).
const nonAppItems = {
  root: { id: 'root', kind: 'menu', label: 'Go' },
  apps: { id: 'apps', kind: 'menu', label: 'Apps', provider: 'apps' }
}
const nonAppOrder = ['root', 'apps']
const appRowsFor = ids => ids.map(id => ({ id: `apps.${id}`, kind: 'app', parent: 'apps', label: id, appId: id }))

const firstMerge = menu.mergeAppRows(nonAppItems, nonAppOrder, appRowsFor(['alacritty', 'youtube']))
assert(
  firstMerge.itemOrder.join(',') === 'root,apps,apps.alacritty,apps.youtube',
  'app merge appends app rows after the static menu items'
)

const secondMerge = menu.mergeAppRows(firstMerge.items, firstMerge.itemOrder, appRowsFor(['alacritty', 'youtube']))
assert(
  secondMerge.itemOrder.join(',') === 'root,apps,apps.alacritty,apps.youtube',
  'repeating the app merge with the same entries does not duplicate rows'
)

assert(
  menu.mergeAppRows(secondMerge.items, secondMerge.itemOrder, appRowsFor(['alacritty'])).itemOrder.join(',')
    === 'root,apps,apps.alacritty',
  'app merge drops rows for entries that went away'
)

assert(
  menu.mergeAppRows(nonAppItems, nonAppOrder, appRowsFor(['youtube', 'youtube'])).itemOrder.join(',')
    === 'root,apps,apps.youtube',
  'app merge lists an app once even when two desktop entries share an id'
)

const orphanedItems = {}
for (const key in firstMerge.items) orphanedItems[key] = firstMerge.items[key]
delete orphanedItems['apps.youtube']
const healed = menu.mergeAppRows(orphanedItems, firstMerge.itemOrder, appRowsFor(['alacritty', 'youtube']))
assert(
  healed.itemOrder.join(',') === 'root,apps,apps.alacritty,apps.youtube'
    && !!healed.items['apps.youtube'],
  'app merge heals an order entry whose item went missing instead of duplicating it'
)

assert(
  !firstMerge.items['apps.youtube'].hasOwnProperty('__probe')
    && (() => {
      const before = Object.keys(nonAppItems).length
      menu.mergeAppRows(nonAppItems, nonAppOrder, appRowsFor(['gimp']))
      return Object.keys(nonAppItems).length === before
    })(),
  'app merge leaves the map it was handed untouched'
)

const providerRowsFor = values => values.map(value => ({ id: `style.font.${value}`, kind: 'action', parent: 'style.font', label: value }))
const firstProviderMerge = menu.mergeRowsById(nonAppItems, nonAppOrder, providerRowsFor(['mono', 'serif']))
assert(
  firstProviderMerge.itemOrder.join(',') === 'root,apps,style.font.mono,style.font.serif',
  'provider merge appends its rows'
)
assert(
  menu.mergeRowsById(firstProviderMerge.items, firstProviderMerge.itemOrder, providerRowsFor(['mono', 'serif']))
    .itemOrder.join(',') === 'root,apps,style.font.mono,style.font.serif',
  'repeating a provider merge does not duplicate rows'
)

// The maps live in QML `var` properties, where an in-place write is
// occasionally dropped by the engine, so both merges must hand back fresh
// objects for the caller to assign in one shot.
assert(
  /var merged = MenuModel\.mergeAppRows\(root\.items, root\.itemOrder, appRows\)\s*\n\s*root\.items = merged\.items\s*\n\s*root\.itemOrder = merged\.itemOrder/.test(menuQml),
  'menu assigns the rebuilt app item map instead of mutating it in place'
)
assert(
  /var merged = MenuModel\.mergeRowsById\(root\.items, root\.itemOrder, providerRows\)\s*\n\s*root\.items = merged\.items\s*\n\s*root\.itemOrder = merged\.itemOrder/.test(menuQml),
  'menu assigns the rebuilt provider item map instead of mutating it in place'
)
assert(
  !/root\.items\[[^\]]+\] =/.test(menuQml) && !/delete root\.items\[/.test(menuQml),
  'menu never writes into the item map held by the var property'
)

for (const functionName of ['openExistingMenu', 'openDmenu']) {
  const openMatch = menuQml.match(new RegExp(`function ${functionName}\\([^)]*\\) \\{([\\s\\S]*?)\\n  \\}`))
  assert(openMatch, `menu ${functionName} function exists`)
  assert(
    openMatch[1].indexOf('root.disarmPointer()') < openMatch[1].indexOf('opened = true')
      && !openMatch[1].includes('pointerGate.allowInitialSample()'),
    `menu ${functionName} ignores a stale hidden-pointer position when becoming visible`
  )
}
assert(
  /function selectFromPointer\(index, item, mouse\)[\s\S]*pointerGate\.moved\(item, mouse\)[\s\S]*root\.selectedIndex = index/.test(menuQml),
  'menu only selects from pointer after real movement'
)
assert(
  /onPositionChanged: function\(mouse\) \{\s*root\.selectFromPointer\(row\.index, row, mouse\)\s*\}/.test(menuQml),
  'menu row hover routes through pointer movement gate'
)
assert(
  /onEntered: root\.selectFromPointer\(row\.index, row, \{\s*x: mouseArea\.mouseX,\s*y: mouseArea\.mouseY\s*\}\)/.test(menuQml),
  'menu samples pointer movement immediately when entering a row'
)
assert(
  /function activateIndex\(index, fromPointer\)[\s\S]*root\.setActiveMenu\(row\.target \|\| row\.itemId, true, fromPointer\)/.test(menuQml)
    && /onClicked:[\s\S]*root\.activateIndex\(row\.index, true\)/.test(menuQml),
  'mouse activation carries pointer intent into subordinate menus'
)
JS
