#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const panelQml = fs.readFileSync(path.join(root, 'shell/Ui/KeyboardPanel.qml'), 'utf8')

assert(
  /exclusionMode: ExclusionMode\.Auto/.test(panelQml),
  'bar panels respect the reserved area of an on-screen keyboard'
)
assert(
  !/exclusionMode: ExclusionMode\.Ignore/.test(panelQml),
  'bar panels do not cover exclusive zones (OSK taps would dismiss the popdown)'
)
assert(
  /WlrLayershell\.keyboardFocus: open/.test(panelQml) &&
    /focusPrimed \? WlrKeyboardFocus\.OnDemand : WlrKeyboardFocus\.Exclusive/.test(panelQml),
  'bar panels settle on OnDemand keyboard focus so pointer input can reach an OSK'
)
JS
