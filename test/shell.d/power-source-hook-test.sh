#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')
const qml = fs.readFileSync(path.join(root, 'shell/plugins/services/battery/Service.qml'), 'utf8')
assert(qml.includes('Component.onCompleted: initializePowerSource()'), 'component completion seeds an already-ready service')
assert(/target: UPower\.displayDevice\s+function onReadyChanged\(\) \{ root\.initializePowerSource\(\) \}/.test(qml), 'display device readiness seeds the startup baseline')
// Execute the actual service methods with controlled UPower and Process state.
const methods = ['initializePowerSource', 'dispatchPowerSourceHook', 'runPendingPowerSourceHook']
const code = methods.map(name => qml.match(new RegExp('  function ' + name + '\\(\\) \\{[\\s\\S]*?\\n  \\}'))[0]).join('\n')
function service(onBattery, ready = false) {
  const state = {
    UPower: { onBattery, displayDevice: { ready } },
    lastPowerSource: '', pendingPowerSourceHook: '',
    powerSourceHookProcess: { running: false, command: [] }
  }
  vm.createContext(state)
  vm.runInContext(code, state)
  state.initializePowerSource()
  return state
}
for (const onBattery of [false, true]) {
  const s = service(false)
  s.UPower.onBattery = onBattery
  s.dispatchPowerSourceHook()
  assert(!s.powerSourceHookProcess.running, 'initial hydration is silent on ' + (onBattery ? 'battery' : 'AC'))
  s.UPower.displayDevice.ready = true
  s.initializePowerSource()
  assert(!s.powerSourceHookProcess.running, 'readiness establishes a silent baseline')
  s.dispatchPowerSourceHook()
  assert(!s.powerSourceHookProcess.running, 'unchanged source does not dispatch a hook')
  s.UPower.onBattery = !onBattery
  s.dispatchPowerSourceHook()
  assertDeepEqual(s.powerSourceHookProcess.command, ['omarchy-hook', 'power-source-change', onBattery ? 'ac' : 'battery'], 'first real transition is delivered')
}
const s = service(true, true)
s.dispatchPowerSourceHook()
assert(!s.powerSourceHookProcess.running, 'loading into an initialized shell is silent')
s.UPower.onBattery = false
s.dispatchPowerSourceHook()
s.initializePowerSource()
assertEqual(s.lastPowerSource, 'ac', 'initialization does not reset an established baseline')
s.UPower.onBattery = true
s.dispatchPowerSourceHook()
s.UPower.onBattery = false
s.dispatchPowerSourceHook()
assertEqual(s.pendingPowerSourceHook, 'ac', 'busy hook retains the latest source')
assertDeepEqual(s.powerSourceHookProcess.command, ['omarchy-hook', 'power-source-change', 'ac'], 'busy process command is not replaced')
s.powerSourceHookProcess.running = false
s.runPendingPowerSourceHook()
assertEqual(s.pendingPowerSourceHook, '', 'queued source is consumed')
JS
