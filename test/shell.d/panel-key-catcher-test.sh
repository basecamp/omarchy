#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const panelKeyCatcher = fs.readFileSync(path.join(root, 'shell/Ui/PanelKeyCatcher.qml'), 'utf8')

assert(
  /event\.key === Qt\.Key_Escape\s*\|\| \(event\.key === Qt\.Key_BracketLeft && event\.modifiers === Qt\.ControlModifier\)/.test(panelKeyCatcher),
  'panel key catcher treats Ctrl+[ as Escape'
)
JS
