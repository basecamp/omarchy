#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// A lid-close lock lands a few hundred milliseconds before suspend. Any fprintd
// call in that window activates the daemon mid-transition, and the reader it
// resets while the USB bus drops comes back unusable for that daemon's life.
assert(
  /command: \["dbus-monitor", "--system",\s*"type='signal',sender='org\.freedesktop\.login1',interface='org\.freedesktop\.login1\.Manager',member='PrepareForSleep'"\]/.test(serviceQml),
  'the lock follows logind PrepareForSleep for the life of the shell'
)

assert(
  /if \(text\.indexOf\("boolean true"\) !== -1\) root\.prepareForSleep\(true\)\s*else if \(text\.indexOf\("boolean false"\) !== -1\) root\.prepareForSleep\(false\)/.test(serviceQml),
  'suspend and resume both reach the lock'
)

assert(
  /function startFingerprint\(\) \{\s*if \([^)]*\|\| suspending\) return/.test(serviceQml),
  'no fingerprint scan starts while suspending'
)

assert(
  /function refreshFingerprintStatus\(\) \{[\s\S]*?if \(suspending\) \{[\s\S]*?return[\s\S]*?fingerprintCheckProc\.running = true/.test(serviceQml),
  'the fingerprint availability check waits for resume'
)

assert(
  /function refreshFingerprintStatus\(\) \{[\s\S]*?if \(suspending\) \{\s*fingerprintCheckDeferred = true\s*return\s*\}/.test(serviceQml),
  'a check held back by suspend is remembered for resume'
)

// fprintd suspends and resumes the reader itself, and libfprint only lets the
// kernel re-enumerate the reader after sleep while a scan is running. Aborting
// that scan at suspend makes fprintd close the reader mid-transition instead,
// and it wakes with stale firmware state that fails every scan until the
// daemon exits.
const prepareForSleep = serviceQml.match(/function prepareForSleep\(sleeping\) \{[\s\S]*?\n  \}/)[0]
assert(!/abort\(\)/.test(prepareForSleep), 'suspend leaves a running scan alone')

assert(
  /if \(sleeping\) \{\s*fingerprintRetryTimer\.stop\(\)\s*\} else if \(fingerprintCheckDeferred\) \{\s*fingerprintCheckDeferred = false\s*refreshFingerprintStatus\(\)\s*\} else if \(lockRequested\) \{\s*startFingerprint\(\)\s*\}/.test(prepareForSleep),
  'suspend stops retries; resume runs the held-back check or restarts the scan'
)

// A monitor that died cannot deliver resume, so its exit must not leave the
// lock stuck in password-only mode.
assert(
  /onExited: function\(exitCode\) \{[\s\S]*?root\.prepareForSleep\(false\)\s*sleepMonitorRestartTimer\.restart\(\)/.test(serviceQml),
  'a dead sleep monitor clears the suspending state and is restarted'
)
JS
