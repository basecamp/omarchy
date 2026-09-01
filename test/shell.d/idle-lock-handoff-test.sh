#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const idleQml = fs.readFileSync(`${root}/shell/plugins/services/idle/Service.qml`, 'utf8')
const lockQml = fs.readFileSync(`${root}/shell/plugins/lock/Service.qml`, 'utf8')
const viewQml = fs.readFileSync(`${root}/shell/plugins/lock/LockView.qml`, 'utf8')

assert(
  /lockFromIdle[\s\S]*while \[\[ \$\(omarchy-shell lock isLocked[\s\S]*\.secure \/\/ false[\s\S]*exec omarchy-system-lock/.test(idleQml),
  'idle keeps the screensaver mapped until the concealed lock reports secure'
)
assert(
  /function lockFromIdle\(\): string \{[\s\S]*root\.beginIdleLock\(\)/.test(lockQml),
  'the idle service has a dedicated lock entry point'
)
assert(
  /function beginIdleLock\(\)[\s\S]*idleTransitionConcealed = true[\s\S]*beginLock\(\)/.test(lockQml),
  'idle concealment is enabled before ext-session-lock begins'
)
assert(
  /concealAuthentication: root\.idleTransitionConcealed/.test(lockQml)
    && /property bool concealAuthentication: false/.test(viewQml)
    && /color: root\.concealAuthentication \? "black" : Color\.background/.test(viewQml)
    && /opacity: root\.concealAuthentication \? 0 : 1/.test(viewQml),
  'the lock surface conceals the wallpaper and password view during handoff'
)
assert(
  /cursorShape: root\.concealAuthentication \? Qt\.BlankCursor : Qt\.ArrowCursor/.test(viewQml),
  'the concealed handoff hides the pointer'
)
assert(
  /function handlePointerWake\(\)[\s\S]*idleTransitionConcealed && !root\.idleTransitionPointerArmed[\s\S]*runWake\(\)/.test(lockQml),
  'surface initialization cannot reveal a newly mapped concealed lock'
)
assert(
  /id: idleTransitionPointerTimer[\s\S]*sessionLock\.secure[\s\S]*idleTransitionPointerArmed = true/.test(lockQml),
  'real pointer wake is armed only after the secure lock settles'
)
assert(
  /signal pointerWakeRequested\(\)[\s\S]*onClicked: \{ root\.pointerWakeRequested\(\); root\.forcePasswordFocus\(\) \}[\s\S]*onPositionChanged: root\.pointerWakeRequested\(\)/.test(viewQml),
  'pointer activity uses the guarded wake path'
)
JS
