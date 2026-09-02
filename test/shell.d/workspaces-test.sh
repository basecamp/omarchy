#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const model = requireFromRoot('shell/plugins/bar/widgets/WorkspacesModel.js')
const widgetSource = fs.readFileSync(root + '/shell/plugins/bar/widgets/Workspaces.qml', 'utf8')
  .replace(/^\s*\/\/.*$/gm, '')

assertDeepEqual(model.workspaceIds([]), [1, 2, 3, 4, 5], 'workspaces always include 1-5')
assertDeepEqual(
  model.workspaceIds([{ id: 2 }, { id: 7 }, { id: -99 }, { id: 11 }]),
  [1, 2, 3, 4, 5, 7],
  'workspaces append extra ids in 1-10 and ignore the rest'
)
assertDeepEqual(
  model.workspaceIds([{ id: 10 }, { id: 6 }]),
  [1, 2, 3, 4, 5, 6, 10],
  'workspaces sort extra ids numerically'
)

const listed = [{ id: 2, name: '2' }, { id: 4, name: '4' }]
assertEqual(model.workspaceById(listed, 4).name, '4', 'workspaces find a workspace by id')
assertEqual(model.workspaceById(listed, 9), null, 'workspaces miss an unknown id')

assertEqual(model.workspaceLabel(3, false), '3', 'workspaces label an inactive workspace with its number')
assertEqual(model.workspaceLabel(10, false), '0', 'workspaces label workspace 10 as 0')
assertEqual(model.workspaceLabel(2, true), '\uDB85\uDCFB', 'workspaces label the focused workspace with the filled-square glyph')

const empty = { toplevels: { values: [] } }
const occupied = { toplevels: { values: [{ activated: false }, { activated: true }] } }
assertEqual(model.toplevelCount(null), 0, 'workspaces count no windows without a workspace')
assertEqual(model.toplevelCount(empty), 0, 'workspaces count no windows on an empty workspace')
assertEqual(model.toplevelCount(occupied), 2, 'workspaces count toplevels on a workspace')
assertEqual(model.isOccupied(empty), false, 'workspaces treat an empty workspace as unoccupied')
assertEqual(model.isOccupied(occupied), true, 'workspaces treat a workspace with toplevels as occupied')
assertEqual(model.isWindowFocused({ activated: true }), true, 'workspaces treat an activated toplevel as focused')
assertEqual(model.isWindowFocused({ activated: false }), false, 'workspaces treat an inactive toplevel as unfocused')

assertEqual(model.windowRowLength(0, 5, 2), 0, 'workspaces give an empty window row no width')
assertEqual(model.windowRowLength(1, 5, 2), 5, 'workspaces size a single window square')
assertEqual(model.windowRowLength(3, 5, 2), 19, 'workspaces size three window squares with gaps')

assert(/import "WorkspacesModel.js" as WorkspacesModel/.test(widgetSource), 'workspaces widget uses the model module')
assert(/labelVisible: false/.test(widgetSource), 'workspaces widget draws its own stacked label so window squares can sit underneath')
assert(/id: windowSlot/.test(widgetSource), 'workspaces widget reserves a slot under every workspace label')
assert(/button\.workspace\.toplevels/.test(widgetSource), 'workspaces widget repeats one square per workspace toplevel')
assert(/WorkspacesModel\.isWindowFocused\(modelData\)/.test(widgetSource), 'workspaces widget fills the square for the focused window')
assert(/anchors\.horizontalCenter: parent\.horizontalCenter/.test(widgetSource), 'workspaces widget centers window squares under the workspace glyph')
JS
