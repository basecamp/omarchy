#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const bar = requireFromRoot('shell/plugins/bar/BarModel.js')
const barSource = fs.readFileSync(root + '/shell/plugins/bar/Bar.qml', 'utf8')
const utilSource = fs.readFileSync(root + '/shell/Commons/Util.qml', 'utf8')
const uiQmldir = fs.readFileSync(root + '/shell/Ui/qmldir', 'utf8')
const collapsibleSource = fs.readFileSync(root + '/shell/Ui/BarCollapsible.qml', 'utf8')
const barGroupSource = fs.readFileSync(root + '/shell/plugins/bar/BarGroup.qml', 'utf8')
const traySource = fs.readFileSync(root + '/shell/plugins/bar/widgets/Tray.qml', 'utf8')

// A type:"group" entry is a structural wrapper the bar renders as a collapsible
// drawer of child widgets. BarModel recognises it and reads its children.
const group = { type: 'group', collapsed: true, items: [{ id: 'omarchy.agents' }, { id: 'omarchy.system-update' }] }
assert(bar.isGroupEntry(group), 'bar recognises a group entry')
assert(!bar.isGroupEntry({ id: 'omarchy.clock' }), 'a plain widget entry is not a group')
assert(!bar.isGroupEntry('omarchy.clock'), 'a string entry is not a group')
assert(!bar.isGroupEntry(null), 'a missing entry is not a group')
assertDeepEqual(
  bar.groupItems(group).map(bar.entryId),
  ['omarchy.agents', 'omarchy.system-update'],
  'bar reads a group child ids'
)
assert(bar.groupItems(group) !== group.items, 'bar returns a fresh group items array, not the config reference')
assertDeepEqual(bar.groupItems({ id: 'omarchy.clock' }), [], 'a non-group has no group items')
assertDeepEqual(bar.groupItems({ type: 'group' }), [], 'a group with no items reads as empty')
assertEqual(bar.entryId(group), '', 'an id-less group has no entry id')
assertEqual(bar.customModuleType(group), 'group', 'a group reports its type')

// A change anywhere inside a group is structural for the live patch: the delta
// is null so the section rebuilds rather than patching a nested entry in place.
assertEqual(
  bar.inlineSettingsDelta(
    { left: [group], center: [], right: [] },
    { left: [{ type: 'group', collapsed: false, items: group.items }], center: [], right: [] }
  ),
  null,
  'bar rebuilds when a group changes rather than patching in place'
)

// The assertions above run BarModel's exported helpers to validate behavior.
// The source-text regex checks below are deliberate: they guard QML *structure*
// the node harness cannot execute — e.g. that a group renders through the
// BarGroup file rather than an inline component (the fix for a load-time
// "inline components form a cycle" crash). Each is scoped to a specific
// regression with no runtime equivalent in this suite.

// Layout normalization must keep group entries (they have no id of their own)
// and normalize their children recursively, or the group would be dropped.
assert(/entry\.type[\s\S]*?=== "group"/.test(utilSource), 'layout normalization preserves group entries')
assert(
  /group\.items = normalizeLayoutSection\(group\.items\)/.test(utilSource),
  'layout normalization recurses into group items'
)

// The bar renders a group through the shared collapsible container, not the
// registry or custom-module loaders.
assert(/readonly property bool isGroup: customType === "group"/.test(barSource), 'bar marks a group slot')
assert(/if \(isGroup\) return groupLoader\.item/.test(barSource), 'bar routes a group slot to the group loader')

// A group is rendered from the BarGroup *file* and handed a plain ModuleList as a
// runtime Component. This is what keeps the group -> slot -> group recursion from
// making the bar's inline components form a cycle (QML forbids that, and it is a
// load-time crash, not something qmllint catches).
assert(/source: slot\.isGroup \? Qt\.resolvedUrl\("BarGroup\.qml"\)/.test(barSource), 'bar loads a group from the BarGroup file, not an inline component')
assert(/id: groupListComponent[\s\S]{0,40}ModuleList \{\}/.test(barSource), 'bar hands the group a plain ModuleList component')
assert(/BarCollapsible \{/.test(barGroupSource), 'the group renders inside the shared collapsible')
// Guard the cycle fix: the group file must not name the bar's inline types.
const barGroupCode = barGroupSource.replace(/\/\/.*$/gm, '')
assert(!/\bModuleList\b|\bModuleSlot\b/.test(barGroupCode), 'the group file names no inline bar types, so the recursion stays file-based')
assert(
  /active: !slot\.qmlCustom && !slot\.registered && !slot\.isGroup/.test(barSource),
  'a group slot is kept out of the empty-module fallback'
)

// A group and its children are not draggable, and are excluded as drop targets,
// so a reorder never tries to persist an id-less or nested entry.
assert(/&& slot\.draggable && !slot\.isGroup/.test(barSource), 'a group is not a drag source')
assert(/if \(slot\.isGroup \|\| !slot\.draggable\) continue/.test(barSource), 'a group is not a drop target')

// The shared collapsible is registered and reuses the tray drawer motion.
assert(/BarCollapsible 1\.0 BarCollapsible\.qml/.test(uiQmldir), 'the shared collapsible is registered in the Ui module')
assert(
  /duration:\s*root\.animationDuration[\s\S]*?easing\.type:\s*Easing\.OutCubic/.test(collapsibleSource),
  'the collapsible animates its reveal with an OutCubic curve'
)
assert(/animationDuration:\s*600/.test(collapsibleSource), 'the collapsible matches the tray drawer duration')

// The tray drawer and the widget group share BarCollapsible rather than forking
// the collapse/expand animation. The collapsible offers the tray's reserve-space
// mode and a chevron-press hook for its manage popup, and the tray drives both
// through it instead of running its own reveal.
assert(/property bool reserveSpace/.test(collapsibleSource), 'the collapsible offers a reserve-space (tray) mode')
assert(/signal chevronPressed/.test(collapsibleSource), 'the collapsible exposes chevron presses for the tray manage popup')
assert(/BarCollapsible \{[\s\S]*?reserveSpace: true/.test(traySource), 'the tray drawer uses BarCollapsible in reserve-space mode')
assert(/onChevronPressed:[\s\S]*?managePopupOpen/.test(traySource), 'the tray opens its manage popup from the shared chevron')
assert(!/Behavior on revealProgress/.test(traySource), 'the tray no longer runs its own forked reveal animation')
JS
