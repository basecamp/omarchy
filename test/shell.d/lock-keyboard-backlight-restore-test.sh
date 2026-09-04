#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// A wake fired while another is already running used to just vanish, so the
// keyboard restore it carried never happened if it lost that race.
assert(
  /function runWake\(\) \{[\s\S]*if \(!wakeProcess\.running\) wakeProcess\.running = true\s*\n\s*else wakeRerunRequested = true/.test(serviceQml),
  'a wake that arrives while one is already running is queued, not dropped'
)

assert(
  /onExited: \{\s*if \(!root\.wakeRerunRequested\) return\s*\n\s*root\.wakeRerunRequested = false\s*\n\s*wakeProcess\.running = true/.test(serviceQml),
  'a queued wake reruns once the in-flight one finishes'
)

// Restoring on every unlock regardless overwrote whatever the user actually
// had (e.g. set with a firmware-handled brightness key) with a stale value.
assert(
  /function beginLock\(\) \{[\s\S]*keyboardBlanked = false\s*\n\s*keyboardOffSaved = false/.test(serviceQml),
  'each lock session starts assuming it never blanked the keyboard'
)

assert(
  /function runBlank\(\) \{\s*(?:\/\/[^\n]*\n\s*)*keyboardBlanked = true\s*\n\s*keyboardOffSaved = true/.test(serviceQml),
  'the real off is what makes brightnessctl\'s own restore trustworthy again'
)

assert(
  /if \(Date\.now\(\) - armedAt > interval \+ 2000\) \{[\s\S]*root\.keyboardBlanked = true/.test(serviceQml),
  'a suspend detected via the frozen timer also counts as reason to restore, even though this session never ran the blank itself'
)

assert(
  /if \(Date\.now\(\) - armedAt > interval \+ 2000\) \{[\s\S]{0,400}\bkeyboardOffSaved\b/.test(serviceQml) === false,
  'the suspend-frozen guard never claims the real off ran, since it never did'
)

// A software change (e.g. the default Fn-key bindings calling
// omarchy-brightness-keyboard) never reaches the hardware-change watcher, so
// once the real off has captured it, that saved state must win over the
// poll-tracked value -- which the watcher never updated for a software change
// in the first place.
assert(
  /root\.keyboardOffSaved\s*\n\s*\? "; omarchy-brightness-keyboard restore"/.test(serviceQml),
  'a session that ran the real off restores through brightnessctl\'s own save, correct for both software- and hardware-driven changes'
)

// Only reached when a suspend was detected without the blank timer ever
// getting a turn: brightnessctl's saved state was never updated, so this is
// the only thing that might still reflect what was showing beforehand.
assert(
  /: \(root\.savedKeyboardBrightness >= 0[\s\S]*brightnessctl -d '" \+ root\.kbdDeviceName \+ "' set " \+ root\.savedKeyboardBrightness/.test(serviceQml),
  'the poll-tracked value is only ever used as a fallback, not the primary restore path'
)

// Without this, a session that never touches the brightness key would have
// no value to restore to.
assert(
  /findKbdDeviceProc[\s\S]*cat \\"\$c\/brightness\\"/.test(serviceQml),
  'the starting brightness is captured alongside the device name'
)

// brightness_hw_changed is only present on drivers that call
// led_classdev_notify_brightness_hw_changed(); without this check the watcher
// would loop forever trying to open a file that never exists on hardware
// that doesn't support it.
assert(
  /\[\[ -e \$c\/brightness_hw_changed \]\] && echo yes \|\| echo no/.test(serviceQml),
  'hardware-change notification support is checked before the watcher starts'
)

assert(
  /if \(\(lines\[2\] \|\| ""\)\.trim\(\) === "yes"\) kbdWatcherProc\.running = true/.test(serviceQml),
  'the watcher only starts on hardware that actually supports the notification'
)

// A firmware-handled brightness key changes the LED value directly, with no
// regular write for a file watch to see; brightness_hw_changed is the LED
// class's own poll()-able notification for exactly this case.
assert(
  /select\.poll\(\)[\s\S]*p\.register\(f, select\.POLLPRI \| select\.POLLERR\)/.test(serviceQml),
  'the watcher blocks on the driver-notified event rather than checking on a timer'
)

// Before the first hardware-notified change since boot, the kernel has
// nothing to report yet and reads raise ENODATA -- an uncaught read there
// would crash the watcher on every restart until one happens to land during
// one of the brief windows it is actually running.
assert(
  /if e\.errno != errno\.ENODATA: raise/.test(serviceQml),
  'only ENODATA is swallowed while priming the watcher; any other read error still surfaces'
)

assert(
  /drain\(f\); f\.seek\(0\)[\s\S]*?p = select\.poll\(\)/.test(serviceQml),
  'the poll is registered even when there is nothing to prime yet, rather than only after a successful read'
)

assert(
  /if \(!root\.kbdTrackingSuspended\) root\.savedKeyboardBrightness = val/.test(serviceQml),
  'a value the watcher reports while locked is ignored, not treated as the new baseline'
)

assert(
  /readonly property bool kbdTrackingSuspended: locked/.test(serviceQml),
  'tracking is suspended for a session\'s entire lock, not toggled around individual wake/blank events'
)

assert(
  /onExited: kbdWatcherRestartTimer\.restart\(\)/.test(serviceQml),
  'the watcher restarts if it ever exits, rather than leaving the session untracked for good'
)
JS
