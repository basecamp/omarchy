#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')
const lockViewQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/LockView.qml'), 'utf8')

function bodyOf(src, name, label) {
  const start = src.indexOf(`function ${name}(`)
  assert(start !== -1, `${label}: source defines ${name}()`)
  const open = src.indexOf('{', start)
  let depth = 0
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') depth += 1
    else if (src[i] === '}') {
      depth -= 1
      if (depth === 0) return src.slice(open + 1, i)
    }
  }
  fail(`${label}: ${name}() has balanced braces`)
}

const wake = bodyOf(serviceQml, 'runWake', 'display wake')
assert(wake.includes('displayBlanked = false'), 'a wake clears the blanked state')
assert(wake.includes('focusRequestVersion += 1'), 'a wake re-arms password focus')
assert(
  wake.includes('if (!blankProcess.running && !wakeProcess.running)'),
  'a wake waits for an in-flight blank instead of racing its DPMS off'
)

const blank = bodyOf(serviceQml, 'runBlank', 'display blank')
assert(blank.indexOf('displayBlanked = true') < blank.indexOf('blankProcess.running = true'), 'blanked state is published before DPMS off starts')
assert(
  /id: blankProcess[\s\S]*onExited: if \(!root\.displayBlanked && !wakeProcess\.running\) wakeProcess\.running = true/.test(serviceQml),
  'a wake held behind DPMS off is dispatched when the blank finishes'
)

assert(
  /IdleMonitor \{[\s\S]*enabled: root\.lockRequested[\s\S]*respectInhibitors: false/.test(serviceQml),
  'compositor input monitoring is armed for the whole lock'
)
assert(
  /onIsIdleChanged: \{[\s\S]*root\.focusRequestVersion \+= 1[\s\S]*if \(root\.displayBlanked\) root\.runWake\(\)/.test(serviceQml),
  'keyboard activity wakes a blank display without depending on field focus'
)

assert(
  /displayBlanked: root\.displayBlanked[\s\S]*focusRequestVersion: root\.focusRequestVersion/.test(serviceQml),
  'each lock view receives display and compositor-focus state'
)

const armFocus = bodyOf(lockViewQml, 'armPasswordFocusRetry', 'password focus retry')
assert(
  armFocus.includes('!inputEnabled || authenticatingPassword || displayBlanked'),
  'focus retry idles when input cannot be accepted'
)
assert(
  armFocus.includes('focusRetry.remaining = focusRetry.budget') && armFocus.includes('focusRetry.restart()'),
  'every focus-loss event receives a fresh bounded retry budget'
)

for (const handler of [
  'onInputEnabledChanged: armPasswordFocusRetry()',
  'onAuthenticatingPasswordChanged: armPasswordFocusRetry()',
  'onDisplayBlankedChanged: armPasswordFocusRetry()',
  'onFocusRequestVersionChanged: armPasswordFocusRetry()',
]) {
  assert(lockViewQml.includes(handler), `${handler.split(':')[0]} re-arms password focus`)
}

const timer = lockViewQml.match(/id: focusRetry[\s\S]*?readonly property int budget: (\d+)[\s\S]*?property int remaining: 0[\s\S]*?onTriggered: \{([\s\S]*?)\n    \}/)
assert(timer, 'the password focus retry has a fixed budget and trigger')
assert(Number(timer[1]) > 0 && Number(timer[1]) <= 100, 'the retry budget is finite and practical')
assert(timer[2].includes('passwordInput.activeFocus'), 'the retry stops as soon as focus is acquired')
assert(timer[2].includes('if (remaining <= 0) stop()'), 'an unfocusable hotplugged surface cannot retry forever')

assert(
  /onActiveFocusChanged: \{[\s\S]*if \(activeFocus\) focusRetry\.stop\(\)[\s\S]*else root\.armPasswordFocusRetry\(\)/.test(lockViewQml),
  'later focus loss re-arms the bounded retry'
)
JS
