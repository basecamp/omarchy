#!/bin/bash

# PanelSlider sits in ScrollViews. preventStealing keeps the pointer grab;
# onCanceled clears dragging if that grab is still lost.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const sliderQml = fs.readFileSync(path.join(root, 'shell/Ui/PanelSlider.qml'), 'utf8')

assert(
  /preventStealing:\s*true/.test(sliderQml),
  'panel slider keeps the pointer grab so a ScrollView Flickable cannot steal it'
)
assert(
  /onCanceled:\s*endDrag\(\)/.test(sliderQml),
  'panel slider ends the drag when the pointer grab is canceled'
)
JS
