#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const gateQml = fs.readFileSync(path.join(root, 'shell/Ui/PointerMoveGate.qml'), 'utf8')
const uiQmldir = fs.readFileSync(path.join(root, 'shell/Ui/qmldir'), 'utf8')

assert(
  /PointerMoveGate 1\.0 PointerMoveGate\.qml/.test(uiQmldir),
  'pointer movement gate is exported from qs.Ui'
)
assert(
  /property Item referenceItem: null/.test(gateQml),
  'pointer movement gate accepts a stable reference item'
)
assert(
  /property real threshold: 1/.test(gateQml),
  'pointer movement gate ignores single-pixel hover jitter'
)
assert(
  /function reset\(\)[\s\S]*root\.primed = false/.test(gateQml),
  'pointer movement gate can be disarmed after keyboard or list changes'
)
assert(
  /item\.mapToItem\(target, mouse\.x, mouse\.y\)/.test(gateQml),
  'pointer movement gate compares movement in stable target coordinates'
)
assert(
  /var didMove = root\.primed[\s\S]*Math\.abs\(point\.x - root\.lastX\) > root\.threshold[\s\S]*Math\.abs\(point\.y - root\.lastY\) > root\.threshold/.test(gateQml),
  'pointer movement gate only reports real movement after an initial sample'
)
JS
