#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const idleQml = fs.readFileSync(`${root}/shell/plugins/services/idle/Service.qml`, 'utf8')
const lockQml = fs.readFileSync(`${root}/shell/plugins/lock/Service.qml`, 'utf8')
const viewQml = fs.readFileSync(`${root}/shell/plugins/lock/LockView.qml`, 'utf8')

assert(
  /omarchy-shell lock lockAndBlank >\/dev\/null 2>&1 \|\| true; omarchy-system-lock/.test(idleQml),
  'idle lock requests a dark transition without bypassing normal lock cleanup'
)

assert(
  /function lockAndBlank\(\): string \{[\s\S]*idleBlankTimer\.stop\(\)[\s\S]*root\.runBlank\(\)/.test(lockQml),
  'the lock service blanks immediately for an already-dark idle transition'
)

assert(
  /function runBlank\(\) \{[\s\S]*?displayBlanked = true[\s\S]*?pointerWakeArmed = false/.test(lockQml),
  'blanking resets pointer wake arming'
)

assert(
  /concealAuthentication: root\.displayBlanked/.test(lockQml)
    && /property bool concealAuthentication: false/.test(viewQml)
    && /color: root\.concealAuthentication \? "black" : Color\.background/.test(viewQml)
    && /opacity: root\.concealAuthentication \? 0 : 1/.test(viewQml),
  'the lock surface stays visually black while real DPMS catches up'
)

assert(
  /cursorShape: root\.concealAuthentication \? Qt\.BlankCursor : Qt\.ArrowCursor/.test(viewQml),
  'the concealed transition cannot expose a live pointer over black'
)

assert(
  /function handlePointerWake\(\)[\s\S]*if \(displayBlanked && !pointerWakeArmed\) return[\s\S]*runWake\(\)/.test(lockQml),
  'surface initialization cannot wake a newly blanked lock'
)

assert(
  /id: pointerWakeMonitor[\s\S]*enabled: root\.displayBlanked[\s\S]*timeout: root\.pointerWakeSettleSeconds[\s\S]*onIsIdleChanged: root\.handlePointerWakeMonitorChanged\(\)/.test(lockQml),
  'compositor-side idle arms real pointer wake after initialization settles'
)

assert(
  /signal pointerWakeRequested\(\)[\s\S]*onClicked: \{ root\.pointerWakeRequested\(\); root\.forcePasswordFocus\(\) \}[\s\S]*onPositionChanged: root\.pointerWakeRequested\(\)/.test(viewQml),
  'pointer activity uses the guarded wake path'
)
JS
