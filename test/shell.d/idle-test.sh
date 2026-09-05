#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const idle = requireFromRoot('shell/plugins/services/idle/IdleModel.js')

assertEqual(idle.secondsFromConfig('42.9', 10), 42, 'idle floors configured seconds')
assertEqual(idle.secondsFromConfig('-1', 10), 10, 'idle rejects negative seconds')
assertEqual(idle.secondsFromConfig('nope', 10), 10, 'idle rejects invalid seconds')
assertEqual(idle.secondsFromConfig(null, 10), 10, 'idle rejects null seconds')

const defaults = { screensaver: 150, lock: 300 }
const stock = { screensaver: 150, lock: 300, ac: { screensaver: 300, lock: 1800 } }

assertDeepEqual(
  idle.effectiveTimeouts(stock, false, defaults),
  { screensaver: 300, lock: 1800 },
  'idle uses the ac profile while plugged in'
)
assertDeepEqual(
  idle.effectiveTimeouts(stock, true, defaults),
  { screensaver: 150, lock: 300 },
  'idle keeps the top-level pair on battery when no battery profile is set'
)
assertDeepEqual(
  idle.effectiveTimeouts({ screensaver: 150, lock: 300, battery: { screensaver: 60, lock: 90 } }, true, defaults),
  { screensaver: 60, lock: 90 },
  'idle uses the battery profile while on battery'
)
assertDeepEqual(
  idle.effectiveTimeouts({ screensaver: 150, lock: 300, ac: { lock: 1800 } }, false, defaults),
  { screensaver: 150, lock: 1800 },
  'idle falls back per-key when an ac override omits screensaver'
)
assertDeepEqual(
  idle.effectiveTimeouts({ screensaver: 150, lock: 300, ac: { screensaver: 'nope', lock: -1 } }, false, defaults),
  { screensaver: 150, lock: 300 },
  'idle rejects invalid ac overrides'
)
assertDeepEqual(
  idle.effectiveTimeouts(null, false, defaults),
  { screensaver: 150, lock: 300 },
  'idle uses builtin defaults without an idle config'
)
assertEqual(idle.profileBlock({ ac: [300] }, 'ac'), null, 'idle ignores a non-object power profile')

assertDeepEqual(idle.eventParts({ data: 'a,b,c' }, 2), ['a', 'b', 'c'], 'idle parses raw event data')
assertDeepEqual(
  idle.eventParts({ parse: function(count) { return ['parsed', count] } }, 4),
  ['parsed', 4],
  'idle prefers event parser when available'
)

assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true }, 'b', true),
  { windows: { a: true, b: true }, count: 2 },
  'idle adds visible screensaver windows'
)
assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true, b: true }, 'a', false),
  { windows: { b: true }, count: 1 },
  'idle removes closed screensaver windows'
)
assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true }, '', false),
  { windows: { a: true }, count: 1 },
  'idle leaves screensaver windows unchanged without an address'
)
JS

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
mkdir -p "$test_home"

HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" stay-awake >/dev/null
[[ -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "Stay Awake toggle persists enabled state"

HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" allow-idle >/dev/null
[[ ! -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "Stay Awake toggle persists disabled state"

if rg -q 'omarchy-shell' "$ROOT/bin/omarchy-toggle-idle"; then
  fail "Stay Awake toggle avoids reentrant shell IPC"
fi

pass "Stay Awake toggle persists state without reentrant shell IPC"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/services/idle/Service.qml'), 'utf8')

assert(
  /import Quickshell\.Services\.UPower/.test(serviceQml),
  'idle service reads the power source from UPower'
)
assert(
  /IdleModel\.effectiveTimeouts\(idleConfig, UPower\.onBattery/.test(serviceQml),
  'idle service resolves timeouts through IdleModel.effectiveTimeouts'
)
assert(
  /IdleMonitor \{[\s\S]*?enabled:\s*root\.idleEnabled && root\.monitorArmed/.test(serviceQml),
  'IdleMonitor.enabled is gated on monitorArmed'
)
assert(
  /onScreensaverTimeoutSecondsChanged:\s*root\.handleIdleTimeoutsChanged\(\)/.test(serviceQml) &&
    /onLockTimeoutSecondsChanged:\s*root\.handleIdleTimeoutsChanged\(\)/.test(serviceQml),
  'timeout changes invoke the idle-monitor re-arm'
)
assert(
  /root\.monitorArmed = false[\s\S]*?Qt\.callLater\(function\(\) \{ root\.monitorArmed = true \}\)/.test(serviceQml),
  're-arm disables the monitor and enables it again on the next tick'
)
JS
