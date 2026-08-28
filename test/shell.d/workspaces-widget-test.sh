#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const source = fs.readFileSync(root + '/shell/plugins/bar/widgets/Workspaces.qml', 'utf8')

// The bar used to stop at 10 because SUPER+1..0 stops there. Hyprland does
// not, so a workspace reached by other means must still get a tile.
assert(
  /if \(id > 0 && ids\.indexOf\(id\) === -1\) ids\.push\(id\)/.test(source),
  'workspaces widget lists every positive workspace id, with no upper bound'
)
assert(!/id <= 10/.test(source), 'workspaces widget no longer caps ids at 10')

// "0" for 10 mirrors its key. It only reads that way while nothing follows.
assert(
  /modelData === 10 && root\.highestWorkspaceId <= 10\) \? "0" : String\(modelData\)/.test(source),
  'workspace 10 is written as "0" only while it ends the row'
)

// The focus dot replaces a numeral the keyboard already knows. Above 10 there
// is no key, so the number must stay visible on the focused tile.
assert(/readonly property bool keyed: modelData <= 10/.test(source), 'workspaces above 10 count as unkeyed')
assert(
  /text: focused && keyed \? "\\uDB85\\uDCFB" : numeral/.test(source),
  'only a keyed workspace swaps its numeral for the focus dot'
)
assert(/active: focused && !keyed/.test(source), 'an unkeyed focused workspace marks its focus by colour instead')
JS
