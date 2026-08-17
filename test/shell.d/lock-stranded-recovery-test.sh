#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// The compositor holds the lock past its client, so a fresh shell must retake it.
assert(
  /Component\.onCompleted:[\s\S]*checkStrandedLock\(\)/.test(serviceQml),
  'the lock service asks the compositor whether the session is locked at startup'
)

assert(
  /id: strandedLockCheckProc[\s\S]*omarchy-hyprland-session-locked/.test(serviceQml),
  'the startup check goes through the shared session lock helper'
)

// "No output to read" taken for "unlocked" leaves the failsafe up for good.
assert(
  /onExited: function\(exitCode\) \{[\s\S]*if \(exitCode === 2\) return/.test(serviceQml),
  'an undetermined answer never resolves the check'
)

assert(
  /if \(exitCode === 2\) return\s*\n\s*root\.strandedLockResolved = true/.test(serviceQml),
  'only a compositor that reports a lock counts as a stranded lock'
)

// omarchy-restart-shell re-locks a fresh shell, possibly mid-question.
// `locked` includes stale sessionLock.secure and would hide an orphan.
assert(
  /root\.strandedLock = exitCode === 0 && !root\.sessionLock\.locked && !root\.lockRequested/.test(serviceQml),
  'a lock this shell took while the check was in flight is not stranded'
)

assert(
  /id: strandedLockRetryTimer[\s\S]*running: !root\.strandedLockResolved && remaining > 0/.test(serviceQml),
  'the check retries while the compositor cannot answer, and stops once it has'
)

// A display asleep for hours outlasts any retry budget.
assert(
  /function onScreensChanged\(\) \{[\s\S]*root\.checkStrandedLock\(\)/.test(serviceQml),
  'a screen coming back re-asks whether a lock is stranded'
)

// One probe is not enough: a monitor still coming up cannot answer.
assert(
  /function onScreensChanged\(\) \{[\s\S]*strandedLockRetryTimer\.rearm\(\)[\s\S]*root\.checkStrandedLock\(\)/.test(serviceQml),
  'a screen coming back gives the check its settling time again'
)

assert(
  /function rearm\(\) \{\s*if \(!root\.strandedLockResolved\) remaining = budget/.test(serviceQml),
  're-arming never restarts a check that already has its answer'
)

// A lock this shell owns ends the search. sessionLock.secure alone is not ours.
assert(
  /function checkStrandedLock\(\) \{\s*if \(strandedLockResolved \|\| strandedLockCheckProc\.running\) return[\s\S]*if \(sessionLock\.locked \|\| lockRequested\) \{\s*strandedLockResolved = true/.test(serviceQml),
  'a lock this shell took is not treated as stranded'
)

assert(
  /readonly property bool lockSurfaceOrphaned: sessionSecured && !lockOwned/.test(serviceQml),
  'an orphan is a compositor-secured session with no surface this client owns'
)

assert(
  /function recoverStrandedLock\(\) \{\s*if \(!strandedLock \|\| !passwordPamConfigured\) return/.test(serviceQml),
  'recovery is skipped unless a stranded lock is waiting and PAM can authenticate it'
)

assert(
  /function recoverStrandedLock\(\) \{[\s\S]*if \(lockSurfaceOrphaned\) \{\s*restartForOrphanedLock\(\)/.test(serviceQml),
  'stranded recovery restarts only when the lock surface is an in-process orphan'
)

assert(
  /function recoverStrandedLock\(\) \{[\s\S]*if \(sessionLock\.locked\) return/.test(serviceQml),
  'recovery is skipped when this client already owns a lock surface'
)

assert(
  /function requestSessionLock\(\) \{[\s\S]*if \(!lockRequested \|\| sessionLock\.locked\) return/.test(serviceQml),
  'requesting a lock does not treat sessionLock.secure as proof this client owns it'
)

assert(
  /lockSurfaceOrphaned[\s\S]*restartForOrphanedLock\(\)/.test(serviceQml),
  'a compositor-secured session with no surface restarts instead of setting locked'
)

// The compositor answer and the PAM config land asynchronously, in either
// order, so whichever arrives last has to drive the recovery.
assert(
  /onPasswordPamConfiguredChanged: \{[\s\S]*checkStrandedLock\(\)/.test(serviceQml),
  'recovery retries once the PAM config has loaded'
)

// The failsafe can be cleared from a TTY while PAM is still loading.
assert(
  /onPasswordPamConfiguredChanged: \{\s*if \(!passwordPamConfigured\) return\s*\n\s*strandedLock = false\s*\n\s*strandedLockResolved = false/.test(serviceQml),
  'a late PAM config re-asks the compositor instead of trusting a stale answer'
)

assert(
  /logEvent\("lock-stranded: recovering"\)\s*\n\s*beginLock\(\)/.test(serviceQml),
  'a fresh process takes the stranded compositor lock in-process'
)

assert(
  /function restartForOrphanedLock\(\) \{[\s\S]*if \(sessionLock\.locked \|\| !lockSurfaceOrphaned\) return/.test(serviceQml),
  'a shell restart is reserved for an orphaned lock surface'
)

assert(
  /logEvent\("lock-stranded: restarting-for-orphan"\)\s*\n\s*restartShellProc\.running = true/.test(serviceQml),
  'an in-process orphan restarts the shell instead of beginLock'
)

assert(
  /id: restartShellProc[\s\S]*omarchy-restart-shell/.test(serviceQml),
  'orphan recovery goes through omarchy-restart-shell so relock happens in a new process'
)

assert(
  /property bool strandedRestartAttempted/.test(serviceQml),
  'orphan recovery attempts a shell restart at most once per process'
)

assert(
  /id: pendingSessionLockTimer[\s\S]*if \(attempts > 50\)/.test(serviceQml),
  'a lock that never attaches gives up instead of spinning at 10 Hz'
)
JS
