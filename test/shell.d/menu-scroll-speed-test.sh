#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const menuSource = fs.readFileSync(root + '/shell/plugins/menu/Menu.qml', 'utf8')

// The menu ListView must carry a WheelHandler that scales the wheel delta so
// touchpad scrolling on long lists (e.g. keybindings) feels responsive. Qt's
// default Flickable scroll on touchpads translates the small per-event
// angleDelta into tiny contentY steps, making the menu feel sluggish.
const listMatch = menuSource.match(/ListView \{[\s\S]*?id: resultList[\s\S]*?\n            \}/)
assert(listMatch, 'menu ListView with id resultList exists')
assert(/WheelHandler\s*\{/.test(listMatch[0]), 'menu ListView has a WheelHandler for scroll speed')
assert(/event\.angleDelta\.y\s*\*\s*3/.test(listMatch[0]), 'menu WheelHandler scales the wheel delta by 3x')
assert(/resultList\.contentY/.test(listMatch[0]), 'menu WheelHandler adjusts contentY directly')
assert(/resultList\.originY/.test(listMatch[0]), 'menu WheelHandler clamps to originY bounds')
pass('menu ListView scales wheel events for faster touchpad scrolling')
JS
