#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')

const cursorSrc = fs.readFileSync(root + '/shell/Ui/Cursor.js', 'utf8').replace(/^\.pragma library\s*/, '')
const Cursor = vm.runInNewContext(cursorSrc + '\n({ applyHover: applyHover })')

let claimed = 0
let released = 0
const claim = () => { claimed += 1 }
const release = () => { released += 1 }

Cursor.applyHover(true, false, claim, release)
assertEqual(claimed, 1, 'cursor hover enter claims')
assertEqual(released, 0, 'cursor hover enter does not release')

Cursor.applyHover(false, true, claim, release)
assertEqual(claimed, 1, 'cursor hover leave of owner does not claim again')
assertEqual(released, 1, 'cursor hover leave of owner releases including keyboard selection')

Cursor.applyHover(false, false, claim, release)
assertEqual(released, 1, 'cursor hover leave of a different item does not steal the new cursor')

const buttonQml = fs.readFileSync(root + '/shell/Ui/Button.qml', 'utf8')
assert(/onContainsMouseChanged: root\.hovered\(containsMouse\)/.test(buttonQml), 'Button emits hovered from containsMouse so leave fires')
assert(!/HoverHandler/.test(buttonQml), 'Button does not use overlay HoverHandler for hovered')

const surfaceQml = fs.readFileSync(root + '/shell/Ui/CursorSurface.qml', 'utf8')
assert(/signal hovered\(bool isHovered\)/.test(surfaceQml), 'CursorSurface emits hovered')
assert(/acceptedButtons: Qt\.NoButton/.test(surfaceQml), 'CursorSurface pointer area does not steal clicks')
assert(/pointer leave releases it/.test(surfaceQml), 'CursorSurface contract says leave releases the cursor')

const panels = [
  'shell/plugins/panels/audio/Panel.qml',
  'shell/plugins/panels/bluetooth/Panel.qml',
  'shell/plugins/panels/network/Panel.qml',
  'shell/plugins/panels/monitor/Panel.qml',
  'shell/plugins/panels/power/Panel.qml',
  'shell/plugins/panels/dropbox/Panel.qml',
  'shell/plugins/panels/tailscale/Panel.qml'
]
for (const panel of panels) {
  const src = fs.readFileSync(root + '/' + panel, 'utf8')
  assert(src.includes('Cursor.applyHover'), panel + ' uses Cursor.applyHover')
  assert(src.includes('root.cursorActive = false') || src.includes('mullvadRegionIndex = -1'), panel + ' releases the cursor on pointer leave')
}
JS
