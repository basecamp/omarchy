#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')
const lockViewQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/LockView.qml'), 'utf8')

assert(
  /readonly property int faceActivityDebounce: 750/.test(serviceQml),
  'face activity waits 750 ms after the lock becomes secure'
)

assert(
  /onSecureStateChanged:[\s\S]*if \(secure\)[\s\S]*faceActivityEligibleAt = Date\.now\(\) \+ root\.faceActivityDebounce/.test(serviceQml),
  'secure lock state arms face activity without starting authentication'
)

assert(
  /function recordFaceActivity\(\) \{\s*if \(lidClosedDuringLock \|\| faceActivityEligibleAt === 0 \|\| Date\.now\(\) < faceActivityEligibleAt\) return\s*activateFaceAuthentication\(\)/.test(serviceQml),
  'activity before the debounce expires cannot start face authentication'
)

assert(
  /function resetFaceAuthentication\(\)[\s\S]*faceActivityEligibleAt = 0/.test(serviceQml),
  'lock cleanup disarms face activity'
)

assert(
  /signal activityRequested\(\)/.test(lockViewQml) &&
    /Keys\.onPressed: function\(event\) \{\s*if \(!event\.isAutoRepeat\) root\.activityRequested\(\)\s*root\.wakeRequested\(\)/.test(lockViewQml),
  'new key presses request face authentication without retriggering on auto-repeat'
)

assert(
  /TapHandler \{[\s\S]*onTapped:[\s\S]*root\.activityRequested\(\)[\s\S]*root\.forcePasswordFocus\(\)/.test(lockViewQml),
  'mouse clicks and touch taps request face authentication without replacing focus handling'
)

const mouseAreaMatch = lockViewQml.match(/MouseArea \{([\s\S]*?)\n    \}/)
const mouseArea = mouseAreaMatch ? mouseAreaMatch[1] : ''
assert(
  /onPositionChanged: root\.pointerMoved\(\)/.test(mouseArea) && !mouseArea.includes('activityRequested'),
  'pointer movement delegates wake-sensitive activation to the lock service'
)

assert(
  /function runWake\(\) \{\s*displayBlanked = false/.test(serviceQml) &&
    /function runBlank\(\) \{\s*displayBlanked = true/.test(serviceQml) &&
    /function handlePointerMoved\(\) \{\s*var wasBlanked = displayBlanked\s*runWake\(\)\s*if \(wasBlanked\) recordFaceActivity\(\)/.test(serviceQml),
  'only pointer movement that wakes a blanked lock requests face authentication'
)

assert(
  /enabled: root\.inputEnabled && !root\.authenticatingPassword/.test(lockViewQml) &&
    /readOnly: root\.authenticatingPassword/.test(lockViewQml) &&
    /onActivityRequested: root\.recordFaceActivity\(\)/.test(serviceQml) &&
    /onPointerMoved: root\.handlePointerMoved\(\)/.test(serviceQml),
  'face activity observation leaves password input enabled and is wired only by the live lock view'
)
JS
