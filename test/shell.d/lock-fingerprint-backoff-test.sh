#!/bin/bash
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

const capture = (pattern, description) => {
  const match = pattern.exec(serviceQml)
  assert(match !== null, description)
  return match[1]
}

const number = (name) =>
  Number(capture(new RegExp(`readonly property int ${name}: (\\d+)`), `${name} is declared`))

const baseMs = number('fingerprintRetryBaseMs')
const maxMs = number('fingerprintRetryMaxMs')
const fastMs = number('fingerprintFastErrorMs')

const delayBody = capture(
  /function fingerprintRetryDelay\(streak\) \{([\s\S]*?)\n  \}/,
  'the retry delay is computed by fingerprintRetryDelay()'
)
const scheduleBody = capture(
  /function scheduleFingerprintRetry\(isDeviceError\) \{([\s\S]*?)\n  \}/,
  'the retry is scheduled by scheduleFingerprintRetry()'
)

// Run the real function bodies against a stand-in for the QML root so the test
// exercises the state machine rather than a paraphrase of it. `with` resolves
// bare property names against the object the way QML scoping does, and a
// shadowed Date keeps the elapsed-time branch deterministic.
const makeService = () => {
  const state = {
    lockRequested: true,
    fingerprintConfigured: true,
    fingerprintAuthenticating: false,
    fingerprintErrorStreak: 0,
    fingerprintAttemptErrored: false,
    fingerprintAttemptStartedAt: 0,
    fingerprintRetryBaseMs: baseMs,
    fingerprintRetryMaxMs: maxMs,
    fingerprintFastErrorMs: fastMs,
    fingerprintRetryTimer: { interval: 0, restarts: 0, restart() { this.restarts++ } },
    clock: 0,
  }

  state.Date = { now: () => state.clock }
  state.Math = Math
  state.fingerprintRetryDelay = new Function(
    'streak',
    `with (this) { ${delayBody} }`
  ).bind(state)
  state.scheduleFingerprintRetry = new Function(
    'isDeviceError',
    `with (this) { ${scheduleBody} }`
  ).bind(state)

  // One authentication attempt: the reader is armed, time passes, then PAM
  // reports back. A failure raises both onError and onCompleted, so replay both.
  state.attempt = ({ elapsedMs, deviceError }) => {
    state.fingerprintAttemptErrored = false
    state.fingerprintAttemptStartedAt = state.clock
    state.clock += elapsedMs
    if (deviceError) state.scheduleFingerprintRetry(true)
    state.scheduleFingerprintRetry(false)
    return state.fingerprintRetryTimer.interval
  }

  return state
}

const delay = (streak) => makeService().fingerprintRetryDelay(streak)

assert(delay(0) === baseMs, 'no error streak retries at the base interval')
assert(delay(1) === baseMs, 'first device error retries at the base interval')
assert(delay(2) === baseMs * 2, 'second consecutive device error doubles the delay')
assert(delay(3) === baseMs * 4, 'third consecutive device error doubles again')
assert(delay(80) === maxMs, 'a long error streak never exceeds the ceiling')

// The regression that shipped first: onError incremented the streak and the
// onCompleted for that same attempt reset it, pinning the backoff at one step.
const wedged = makeService()
const first = wedged.attempt({ elapsedMs: 0, deviceError: true })
const second = wedged.attempt({ elapsedMs: 0, deviceError: true })
const third = wedged.attempt({ elapsedMs: 0, deviceError: true })

assert(first === baseMs, 'a wedged reader first retries at the base interval')
assert(
  second === baseMs * 2,
  `the completed signal for a failed attempt must not reset the streak, got ${second}`
)
assert(third === baseMs * 4, `a wedged reader keeps backing off, got ${third}`)

// A reader that waits out the swipe reports the same PAM error code. Backing
// off there would leave it unarmed when the user finally does swipe.
const patient = makeService()
const waits = [0, 1, 2].map(() =>
  patient.attempt({ elapsedMs: fastMs * 15, deviceError: true })
)

assert(
  waits.every((interval) => interval === baseMs),
  `swipe timeouts stay at the base interval, got ${waits.join(', ')}`
)

// A wedged reader that recovers should return to being responsive.
const recovering = makeService()
recovering.attempt({ elapsedMs: 0, deviceError: true })
recovering.attempt({ elapsedMs: 0, deviceError: true })
const recovered = recovering.attempt({ elapsedMs: fastMs * 15, deviceError: false })

assert(recovered === baseMs, `a recovered reader returns to the base interval, got ${recovered}`)

// The point of the change: bound how hard a permanently wedged reader is hit.
const runaway = makeService()
let attempts = 0
while (runaway.clock < 60000) {
  const interval = runaway.attempt({ elapsedMs: 0, deviceError: true })
  runaway.clock += interval
  attempts++
}

assert(attempts <= 10, `a wedged reader is retried at most 10 times a minute, got ${attempts}`)

// Backing off must not leave the reader unarmed for someone standing there, so
// any sign of the user cuts the wait short -- but not so freely that a moving
// cursor spins the loop back up.
const nudgeBody = capture(
  /function nudgeFingerprint\(\) \{([\s\S]*?)\n  \}/,
  'a present user re-arms the reader through nudgeFingerprint()'
)
const cooldownMs = number('fingerprintNudgeCooldownMs')

const makeNudger = () => {
  const service = makeService()
  // resetAuthenticationState() zeroes the nudge stamp while the real clock is
  // far past it, so start the fixture's clock somewhere realistic.
  service.clock = 1e9
  service.fingerprintNudgedAt = 0
  service.fingerprintNudgeCooldownMs = cooldownMs
  service.fingerprintPam = { active: false }
  service.starts = 0
  service.startFingerprint = () => { service.starts++ }
  service.fingerprintRetryTimer.running = false
  service.fingerprintRetryTimer.stop = function() { this.running = false }
  service.nudgeFingerprint = new Function(`with (this) { ${nudgeBody} }`).bind(service)
  return service
}

const waiting = makeNudger()
waiting.fingerprintErrorStreak = 8
waiting.fingerprintRetryTimer.running = true
waiting.nudgeFingerprint()

assert(waiting.starts === 1, 'a present user re-arms the reader without waiting out the backoff')
assert(
  waiting.fingerprintErrorStreak === 8,
  `the streak survives a nudge so a wedged reader keeps backing off, got ${waiting.fingerprintErrorStreak}`
)

waiting.fingerprintRetryTimer.running = true
waiting.clock += cooldownMs - 1
waiting.nudgeFingerprint()
assert(waiting.starts === 1, 'a second nudge inside the cooldown is ignored')

waiting.clock += 2
waiting.nudgeFingerprint()
assert(waiting.starts === 2, 'a nudge after the cooldown re-arms again')

const idle = makeNudger()
idle.fingerprintRetryTimer.running = false
idle.nudgeFingerprint()
assert(idle.starts === 0, 'a nudge with no retry pending does not start a second attempt')

const busy = makeNudger()
busy.fingerprintRetryTimer.running = true
busy.fingerprintAuthenticating = true
busy.nudgeFingerprint()
assert(busy.starts === 0, 'a nudge during an attempt in flight is ignored')

assert(
  /function runWake\(\) \{[\s\S]*?nudgeFingerprint\(\)/.test(serviceQml),
  'waking the lock screen nudges the reader'
)
assert(
  /onError: function\(error\) \{[\s\S]*?scheduleFingerprintRetry\(true\)/.test(serviceQml),
  'a device error routes through scheduleFingerprintRetry() as a device error'
)
assert(
  /result === PamResult\.Success[\s\S]*?fingerprintErrorStreak = 0/.test(serviceQml),
  'a successful fingerprint clears the error streak'
)
assert(
  /fingerprintAttemptStartedAt = Date\.now\(\)/.test(serviceQml),
  'each attempt records when it started so its duration can be measured'
)
assert(
  !/interval: 250/.test(serviceQml),
  'the retry timer interval is not hardcoded alongside the backoff'
)
JS
