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
  // The backoff cases all assume a sensor with heat to spare; the thermal cases
  // below swap these for the real bodies.
  state.updateThermalRatio = () => {}
  state.thermalCooldownMs = () => 0
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

// libfprint's own model, from fpi-device.c. The lock screen has to stay under
// this, so the assertions below run the real arming policy against it rather
// than against a restatement of the policy's own arithmetic.
const LIBFPRINT = {
  heatSeconds: 180,
  coolSeconds: 540,
  // TEMP_WARM_HOT_THRESH: the device starts refusing here...
  hotThresh: 1 - 0.26894142136999512075,
  // ...and TEMP_HOT_WARM_THRESH: the refusal latches until it falls back here.
  clearThresh: 0.5,
  startRatio: 0.26894142136999512075,
}

const reals = {}
const real = (name) => {
  if (!(name in reals)) {
    reals[name] = Number(capture(
      new RegExp(`readonly property real ${name}: ([\\d.]+)`),
      `${name} is declared`
    ))
  }
  return reals[name]
}

assert(
  real('thermalHeatSeconds') === LIBFPRINT.heatSeconds,
  'the heating constant tracks libfprint'
)
assert(
  real('thermalCoolSeconds') === LIBFPRINT.coolSeconds,
  'the cooling constant tracks libfprint'
)
assert(
  real('thermalArmCeiling') <= LIBFPRINT.clearThresh,
  'the arming ceiling stays at or below the threshold that clears a latched refusal'
)

const updateBody = capture(
  /function updateThermalRatio\(armed\) \{([\s\S]*?)\n  \}/,
  'the heat estimate is integrated by updateThermalRatio()'
)
const cooldownBody = capture(
  /function thermalCooldownMs\(\) \{([\s\S]*?)\n  \}/,
  'the wait for a cool sensor is computed by thermalCooldownMs()'
)

// Drives the real policy and an independent libfprint model off one clock. Only
// `armSeconds` of each cycle is time the reader is actually held open, which is
// the sole thing either model charges for.
const simulate = ({ armSeconds, minutes, gated }) => {
  const service = makeService()
  service.clock = 1e9
  service.thermalHeatSeconds = real('thermalHeatSeconds')
  service.thermalCoolSeconds = real('thermalCoolSeconds')
  service.thermalArmCeiling = real('thermalArmCeiling')
  service.thermalRatio = LIBFPRINT.startRatio
  service.thermalUpdatedAt = 0
  service.thermalArmed = false
  service.updateThermalRatio = new Function('armed', `with (this) { ${updateBody} }`).bind(service)
  service.thermalCooldownMs = new Function(`with (this) { ${cooldownBody} }`).bind(service)

  let fp = LIBFPRINT.startRatio
  let hot = false
  let everHot = false
  let armedMs = 0
  let maxGapMs = 0
  let gapMs = 0
  const advance = (ms, armed) => {
    if (armed) gapMs = 0
    else {
      gapMs += ms
      if (gapMs > maxGapMs) maxGapMs = gapMs
    }
    const seconds = ms / 1000
    if (armed) {
      const a = Math.exp(-seconds / LIBFPRINT.heatSeconds)
      fp = a * fp + 1 - a
      armedMs += ms
    } else {
      fp = Math.exp(-seconds / LIBFPRINT.coolSeconds) * fp
    }
    if (fp >= LIBFPRINT.hotThresh) hot = true
    else if (hot && fp < LIBFPRINT.clearThresh) hot = false
    if (hot) everHot = true
    service.clock += ms
  }

  const deadline = service.clock + minutes * 60000
  while (service.clock < deadline) {
    service.updateThermalRatio(false)
    const wait = gated ? service.thermalCooldownMs() : 0
    if (wait > 0) {
      advance(wait, false)
      continue
    }
    service.updateThermalRatio(true)
    advance(armSeconds * 1000, true)
    service.updateThermalRatio(false)
  }

  return { everHot, maxGapMs, duty: armedMs / (minutes * 60000), peak: fp }
}

// The bug: an unswiped verify holds the reader open for its full timeout and the
// lock screen re-arms the moment it returns, so the reader is armed essentially
// all the time and libfprint cuts it off about three minutes into every lock.
const ungated = simulate({ armSeconds: 30, minutes: 60, gated: false })
assert(
  ungated.everHot,
  're-arming on completion overheats the reader, so the guard has something to prevent'
)

// The fix, under the worst case the guard has to survive: someone sitting at an
// unblanked lock screen for an hour who never once touches the reader.
const gated = simulate({ armSeconds: 30, minutes: 60, gated: true })
assert(
  !gated.everHot,
  `the arming ceiling keeps libfprint below its cutoff, peaked at ${gated.peak.toFixed(3)}`
)
assert(
  gated.duty < 0.475,
  `the duty cycle stays under what libfprint tolerates, got ${(gated.duty * 100).toFixed(1)}%`
)

// The ceiling rations total armed time, so the duty cycle settles in the same
// place whatever the arm length -- what changes is how long a user can be left
// waiting. Attempts that end quickly have to keep the reader responsive.
const brief = simulate({ armSeconds: 2, minutes: 60, gated: true })
assert(!brief.everHot, 'short attempts stay under the cutoff too')
assert(
  brief.maxGapMs < 15000,
  `quick attempts leave the reader responsive, waited ${(brief.maxGapMs / 1000).toFixed(1)}s`
)
// The worst gap belongs to the case the nudge and the blanking gate exist to
// cover: a full unswiped timeout at an unblanked screen.
assert(
  gated.maxGapMs < 120000,
  `a full timeout still re-arms within two minutes, waited ${(gated.maxGapMs / 1000).toFixed(1)}s`
)

// The cheapest fix is not arming the reader when nobody is in front of it. That
// is what keeps it cold for the case that actually matters -- the user walking
// up to a blanked screen.
assert(
  /function startFingerprint\(\) \{[\s\S]*?if \(displayBlanked\) return/.test(serviceQml),
  'a blanked display does not arm the reader'
)
assert(
  /function runBlank\(\) \{[\s\S]*?fingerprintRetryTimer\.stop\(\)/.test(serviceQml),
  'blanking cancels a pending re-arm instead of letting it fire at a dark screen'
)
assert(
  /function runWake\(\) \{[\s\S]*?wasBlanked[\s\S]*?startFingerprint\(\)/.test(serviceQml),
  'unblanking arms the reader immediately rather than waiting out a backoff'
)
assert(
  /function scheduleFingerprintRetry\([\s\S]*?Math\.max\(fingerprintRetryDelay\(fingerprintErrorStreak\), thermalCooldownMs\(\)\)/.test(serviceQml),
  'a scheduled retry never fires earlier than the sensor can take it'
)

// Blanking disarms the reader, so waking has to be able to arm it again. PAM's
// abort() does not raise completed, so anything the completion handler would
// normally clear has to be cleared by the blank itself -- otherwise the reader
// is disarmed for the rest of the lock and the user is left swiping a dead
// sensor, which is worse than the overheating this gate exists to prevent.
const startBody = capture(
  /function startFingerprint\(\) \{([\s\S]*?)\n  \}/,
  'the reader is armed by startFingerprint()'
)
const blankBody = capture(
  /function runBlank\(\) \{([\s\S]*?)\n  \}/,
  'the display is blanked by runBlank()'
)

const makeLockScreen = () => {
  const service = makeService()
  service.clock = 1e9
  service.sessionLock = { secure: true }
  service.displayBlanked = false
  service.blankProcess = { running: false }
  service.fingerprintRetryTimer.running = false
  service.fingerprintRetryTimer.stop = function() { this.running = false }
  service.fingerprintPam = {
    active: false,
    aborted: 0,
    start() { this.active = true; return true },
    abort() { this.active = false; this.aborted++ },
  }
  service.startFingerprint = new Function(`with (this) { ${startBody} }`).bind(service)
  service.runBlank = new Function(`with (this) { ${blankBody} }`).bind(service)
  return service
}

const cycled = makeLockScreen()
cycled.startFingerprint()
assert(cycled.fingerprintPam.active, 'locking arms the reader')

cycled.runBlank()
assert(cycled.fingerprintPam.aborted === 1, 'blanking releases the reader so it can cool')
assert(!cycled.fingerprintPam.active, 'the reader is not left armed at a dark screen')

// The wake path clears displayBlanked before arming, so mirror that here.
cycled.displayBlanked = false
cycled.startFingerprint()
assert(
  cycled.fingerprintPam.active,
  'waking re-arms the reader after a blank rather than bailing on a stale attempt'
)

const dark = makeLockScreen()
dark.runBlank()
dark.startFingerprint()
assert(!dark.fingerprintPam.active, 'a blanked screen does not arm the reader')
JS
