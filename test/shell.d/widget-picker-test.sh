#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const picker = requireFromRoot('shell/plugins/widget-picker/WidgetPickerModel.js')
const pickerSource = fs.readFileSync(root + '/shell/plugins/widget-picker/WidgetPicker.qml', 'utf8')
const barSource = fs.readFileSync(root + '/shell/plugins/bar/Bar.qml', 'utf8')
const menuSource = fs.readFileSync(root + '/default/omarchy/omarchy-menu.jsonc', 'utf8')

// The picker offers installed bar widgets that are not already on the bar,
// described the way their manifests present themselves, in a stable
// category-then-name order.
const installed = {
  'omarchy.weather': {
    kinds: ['bar-widget'],
    name: 'Weather',
    barWidget: { displayName: 'Weather', description: 'Forecast at a glance', category: 'Info' }
  },
  'omarchy.audio': { kinds: ['bar-widget'], name: 'Audio', barWidget: { category: 'Hardware' } },
  'omarchy.agents': { kinds: ['bar-widget'], name: 'Agents', barWidget: { category: 'AI' } },
  'omarchy.menu': { kinds: ['bar-widget', 'menu'], name: 'Menu' },
  'omarchy.bar': { kinds: ['bar'], name: 'Bar' },
  'acme.broken': { name: 'No kinds at all' }
}
const rows = picker.pickerRows(installed, ['omarchy.audio'])
assertDeepEqual(
  rows.map(row => row.id),
  ['omarchy.agents', 'omarchy.weather', 'omarchy.menu'],
  'picker lists off-bar widgets sorted by category then name'
)
assertEqual(rows[1].description, 'Forecast at a glance', 'picker prefers the barWidget metadata description')
assertEqual(rows[2].category, 'Other', 'picker files uncategorized widgets under Other')
assertDeepEqual(picker.pickerRows(null, null), [], 'picker tolerates a missing registry')

// Filtering matches anything the user can see, plus the id known from the CLI.
assertDeepEqual(
  picker.filterRows(rows, 'forecast').map(row => row.id),
  ['omarchy.weather'],
  'picker filter matches descriptions'
)
assertDeepEqual(
  picker.filterRows(rows, 'omarchy.men').map(row => row.id),
  ['omarchy.menu'],
  'picker filter matches plugin ids'
)
assertDeepEqual(picker.filterRows(rows, '  '), rows, 'a blank filter keeps every row')

// The summon payload reduces to the keys putBarWidget understands, and a
// malformed payload degrades to the default placement instead of throwing.
assertDeepEqual(
  picker.parsePlacement('{"section":"right","before":"omarchy.clock","screen":"DP-3","stray":"x"}'),
  { placement: { section: 'right', before: 'omarchy.clock' }, screen: 'DP-3' },
  'picker keeps only placement keys from the payload'
)
assertDeepEqual(
  picker.parsePlacement('{"after":"omarchy.tray"}'),
  { placement: { after: 'omarchy.tray' }, screen: '' },
  'picker carries after placements'
)
assertDeepEqual(
  picker.parsePlacement('{"section":"right","index":9}'),
  { placement: { section: 'right', index: 9 }, screen: '' },
  'picker carries index placements for the end-of-bar add button'
)
assertDeepEqual(
  picker.parsePlacement('{"index":"junk"}'),
  { placement: {}, screen: '' },
  'picker drops an index that is not a number'
)
assertDeepEqual(
  picker.parsePlacement('not json'),
  { placement: {}, screen: '' },
  'picker shrugs off a malformed payload'
)

// Adding routes through the registry's put — the unattended verb that
// tolerates a placement target the bar no longer carries.
assert(
  /pluginRegistry\.putBarWidget\(row\.id, root\.placement\)/.test(pickerSource),
  'picker adds through the registry put with the summoned placement'
)
assert(
  /function open\(payloadJson\)/.test(pickerSource) && /function close\(\)/.test(pickerSource),
  'picker exposes the open and close lifecycle summon expects'
)

// The bar carries a + at its end that summons the picker, but an idle bar
// must be pixel-identical to one without the feature: no reserved space, no
// visible chrome. Only a pointer that dwells on the bar's end margin — a
// hunt, not a pass-through or ordinary widget traffic — reveals it, and only
// then do the end widgets slide over to make room.
const addButton = barSource.slice(barSource.indexOf('component AddWidgetButton'))
const addButtonBody = addButton.slice(0, addButton.indexOf('\n  }\n\n'))
assert(
  /concealed: !hunting/.test(addButtonBody) &&
  /interactive: hunting/.test(addButtonBody) &&
  !/keepSpace/.test(addButtonBody),
  'the add button reveals only to a hunting pointer and reserves nothing'
)
assert(
  /if \(hovered\) \{\s*\n\s*huntDwell\.restart\(\)/.test(addButtonBody) &&
  /huntDwell\.stop\(\)\s*\n\s*hunting = false/.test(addButtonBody),
  'the reveal waits for a dwell on the corner and hides the moment it ends'
)
assert(
  !/barHovered/.test(addButtonBody),
  'hovering the rest of the bar never reveals the add button'
)
assert(
  /if \(button === Qt\.LeftButton\) root\.openWidgetPicker\(root\.targetWindow\(addButton\)\)/.test(addButtonBody),
  'the add button answers a left click with the picker'
)
for (const orientation of ['horizontalBar', 'verticalBar']) {
  const section = barSource.slice(barSource.indexOf('id: ' + orientation))
  const body = section.slice(0, section.indexOf('\n    }\n'))
  assert(
    /AddWidgetButton \{/.test(body),
    `the ${orientation} carries the add button`
  )
  assert(
    /addWidgetButton\.hunting \? Style\.space\(3\) \+ addWidgetButton\.implicit(Width|Height) : Style\.space\(8\)/.test(body),
    `the ${orientation} keeps its stock end margin until the button is revealed`
  )
  assert(
    /HoverHandler \{\s*\n\s*onHoveredChanged: addWidgetButton\.setHunting\(hovered\)/.test(body),
    `the ${orientation} dwell zone drives the hunt`
  )
}
// The button sits at the outer end of the right section, so its pick lands
// exactly where it is: appended to that section.
assert(
  /var placement = \{ section: "right", index: layoutEntries\("right"\)\.length \}/.test(barSource),
  'the add button pick lands at the end of the right section'
)
assert(
  /shell\.summon\("omarchy\.widget-picker", JSON\.stringify\(placement\)\)/.test(barSource),
  'the bar summons the picker with that placement'
)

// The menu offers the same picker for people who never think to right-click.
assert(
  /"style\.bar\.add-widget":.*omarchy-shell shell summon omarchy\.widget-picker/.test(menuSource),
  'the menu carries an Add Widget entry summoning the picker'
)
JS
