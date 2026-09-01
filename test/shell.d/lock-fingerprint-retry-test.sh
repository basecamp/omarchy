#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const model = requireFromRoot('shell/plugins/lock/FingerprintModel.js')

// Pacing: a reached attempt (streak 0) retries fast; unreached attempts back
// off exponentially to a ceiling above fprintd's 30-second idle exit.
assertEqual(model.retryDelayMs(0), model.MATCH_RETRY_MS, 'a reached attempt retries at the fast interval')
assertEqual(model.retryDelayMs(1), model.ERROR_RETRY_BASE_MS, 'the first unreached attempt backs off')
assertEqual(model.retryDelayMs(2), model.ERROR_RETRY_BASE_MS * 2, 'consecutive unreached attempts double the delay')
assertEqual(model.retryDelayMs(3), model.ERROR_RETRY_BASE_MS * 4, 'the backoff keeps doubling')
assertEqual(model.retryDelayMs(50), model.ERROR_RETRY_CAP_MS, 'the backoff is capped')
assertEqual(model.FPRINTD_IDLE_EXIT_MS, 30000, "the model carries fprintd's 30-second idle exit")
assert(model.ERROR_RETRY_CAP_MS > model.FPRINTD_IDLE_EXIT_MS, "the cap exceeds fprintd's idle exit so a wedged claim can clear")
assert(model.IDLE_CLEAR_MS > model.FPRINTD_IDLE_EXIT_MS && model.IDLE_CLEAR_MS <= model.ERROR_RETRY_CAP_MS,
  'the idle stretch a nudge must leave at the cap covers the exit and fits inside the cap')

let previous = 0
let monotonic = true
for (let streak = 1; streak <= 20; streak++) {
  const delay = model.retryDelayMs(streak)
  if (delay < previous) monotonic = false
  previous = delay
}
assert(monotonic, 'the backoff never shrinks while attempts keep failing to reach the reader')

// The signal: reaching the device (a prompt) clears the streak; not reaching it
// advances it. This is what keeps a healthy-but-untouched reader off the notice
// while a wedged or held one climbs toward it.
assertEqual(model.nextStreak(0, true), 0, 'reaching the reader keeps the streak at zero')
assertEqual(model.nextStreak(5, true), 0, 'reaching the reader clears an accumulated streak')
assertEqual(model.nextStreak(0, false), 1, 'failing to reach the reader starts the streak')
assertEqual(model.nextStreak(2, false), 3, 'failing to reach the reader advances the streak')

// Availability: reported unavailable only past a few consecutive misses, so a
// single transient claim conflict does not flash the notice.
assert(!model.isUnavailable(0), 'a working reader is not reported unavailable')
assert(!model.isUnavailable(model.UNAVAILABLE_AFTER - 1), 'a couple of misses do not report unavailable')
assert(model.isUnavailable(model.UNAVAILABLE_AFTER), 'enough consecutive misses report the reader unavailable')

// End to end: repeatedly failing to reach the reader crosses the threshold, and
// the first attempt that reaches it clears both the streak and the notice.
let streak = 0
for (let i = 0; i < model.UNAVAILABLE_AFTER; i++) streak = model.nextStreak(streak, false)
assert(model.isUnavailable(streak), 'a run of unreached attempts ends up unavailable')
streak = model.nextStreak(streak, true)
assert(!model.isUnavailable(streak), 'one reached attempt clears the unavailable state')

// Presence nudge: it only collapses a backed-off wait, and only once per
// cooldown, so a moving cursor cannot respin the loop.
const backedOff = model.retryDelayMs(2)
assert(!model.shouldNudge(10000, 0, 0, model.MATCH_RETRY_MS), 'no nudge when the wait is already the fast interval')
assert(model.shouldNudge(10000, 0, 0, backedOff), 'a keypress collapses a backed-off wait')
assert(!model.shouldNudge(10000, 9000, 0, backedOff), 'a second nudge inside the cooldown is refused')
assert(model.shouldNudge(10000, 10000 - model.NUDGE_COOLDOWN_MS, 0, backedOff), 'a nudge one cooldown later is allowed')
assert(model.shouldNudge(10000, 11500, 0, backedOff), 'a clock stepped backwards does not refuse the nudge')
assert(model.shouldNudge(10000, 0, 11500, backedOff), 'a clock stepped backwards since the settle does not refuse it either')
assert(model.shouldNudge(10000, 0, 9990, backedOff), 'below the cap a fresh settle does not hold the nudge')

// A cursor moving at 125 Hz raises a wake every 8 ms; over 10 s the floor caps
// the collapses at one per cooldown instead of one per event.
let last = -model.NUDGE_COOLDOWN_MS
let collapses = 0
for (let t = 0; t <= 10000; t += 8) {
  if (model.shouldNudge(t, last, 0, backedOff)) { collapses++; last = t }
}
assert(collapses <= 10000 / model.NUDGE_COOLDOWN_MS + 1,
  'a moving cursor is capped at one collapse per cooldown, got ' + collapses)

// Once the wait has backed off past the cooldown, the tier paces the nudges:
// presence collapses each wait once, but typing at a reader that keeps failing
// cannot pull the loop under the tier's rate.
const capped = model.retryDelayMs(50)
const longAgo = -capped
assert(model.shouldNudge(capped, 0, longAgo, capped), 'a nudge one tier later is allowed')
assert(!model.shouldNudge(capped - 1, 0, longAgo, capped), 'a nudge inside the tier is refused')
last = -capped
collapses = 0
for (let t = 0; t <= 4 * capped; t += 8) {
  if (model.shouldNudge(t, last, longAgo, capped)) { collapses++; last = t }
}
assertEqual(collapses, 5, 'continuous input at the cap collapses once per tier')

// At the cap a fresh settle holds the nudge until fprintd has had its idle
// stretch, then lets it through -- before the cap's own timer would fire.
assert(!model.shouldNudge(model.IDLE_CLEAR_MS - 1, longAgo, 0, capped), 'a nudge before the idle stretch is refused at the cap')
assert(model.shouldNudge(model.IDLE_CLEAR_MS, longAgo, 0, capped), 'a nudge after the idle stretch is allowed at the cap')
// A clock stepped back past the settle says nothing about how long fprintd
// has been idle, so at the cap it must not stand in for the idle stretch.
assert(!model.shouldNudge(10000, longAgo, 15000, capped), 'a clock stepped back past the settle does not bypass the idle guard at the cap')
assert(model.shouldNudge(10000, 15000, longAgo, capped), 'a clock stepped back past the nudge still allows the nudge at the cap once idle')

// At the cap the idle stretch is measured from the settle: a nudged attempt
// that hangs until the reach timeout must not eat into fprintd's idle exit.
// Simulate continuous input at 125 Hz against a reader whose every attempt
// hangs for the full reach bound, and check the gap fprintd is left between
// one attempt ending and the next claiming.
let settle = 0
let nudge = 0
let attemptStart = model.MATCH_RETRY_MS
let minIdle = Infinity
let cycles = 0
for (let t = attemptStart; cycles < 5; t += 8) {
  const attemptEnd = attemptStart + model.REACH_TIMEOUT_MS
  if (t < attemptEnd) continue
  if (t === attemptEnd || settle < attemptStart) settle = attemptEnd
  const timerFires = t >= settle + capped
  if (timerFires || model.shouldNudge(t, nudge, settle, capped)) {
    if (!timerFires) nudge = t
    const claimAt = t + model.MATCH_RETRY_MS
    minIdle = Math.min(minIdle, claimAt - settle)
    attemptStart = claimAt
    cycles++
  }
}
assert(minIdle >= model.FPRINTD_IDLE_EXIT_MS,
  'continuous input against attempts that hang to the reach bound still leaves fprintd its idle exit, got ' + minIdle + 'ms')
assert(minIdle < capped,
  'the nudge still shortens the wait at the cap rather than being dead there, got ' + minIdle + 'ms')

// Resume grace: right after a wake the hook is restarting fprintd under the
// loop, so a miss there holds the streak at the first tier instead of
// climbing toward the notice; a reached attempt still clears it.
assertEqual(model.nextStreak(0, false, true), 1, 'a miss inside the resume grace holds the streak at the first tier')
assertEqual(model.nextStreak(5, false, true), 1, 'the grace pins any accumulated streak to the first tier')
assertEqual(model.nextStreak(5, true, true), 0, 'a reached attempt inside the grace clears the streak')
assertEqual(model.nextStreak(1, false, false), 2, 'outside the grace misses accumulate')
assert(model.RESUME_GRACE_MS >= 3000 + 1000, "the grace outlasts fprintd's 3s stop cap plus its start")
assert(model.RESUME_GRACE_MS < model.ERROR_RETRY_CAP_MS, 'the grace is shorter than the cap, so it cannot mask a reader that is really gone')
assert(!model.inResumeGrace(5000, 0), 'no resume noted means no grace')
assert(model.inResumeGrace(1000 + model.RESUME_GRACE_MS - 1, 1000), 'an attempt settling inside the window is in grace')
assert(!model.inResumeGrace(1000 + model.RESUME_GRACE_MS, 1000), 'an attempt settling at the window edge is not')
assert(!model.inResumeGrace(500, 1000), 'a clock stepped back past the resume is not grace')

// Sleep detection: an unreached attempt cannot outlive the reach bound on the
// monotonic clock, so one that did on the wall clock spanned a suspend.
assert(!model.spannedSleep(model.REACH_TIMEOUT_MS + model.SLEEP_GAP_MS, model.REACH_TIMEOUT_MS), 'the bound plus slack is not a sleep')
assert(model.spannedSleep(model.REACH_TIMEOUT_MS + model.SLEEP_GAP_MS + 1, model.REACH_TIMEOUT_MS), 'longer than the bound plus slack is a sleep')
assert(model.spannedSleep(1000 + 8 * 3600 * 1000, 1000), 'an eight-hour wait on a one-second timer is a sleep')

// End to end: the async resume hook lands a fresh daemon ~3.3s after wake in
// the worst case (SIGTERM-ignoring fprintd, 3s stop cap). Every attempt until
// then misses; none may show the notice, and the loop must still be retrying
// at the first tier when the daemon comes back.
const resumedAt = 1000
let graceStreak = 0
let attemptAt = resumedAt + model.MATCH_RETRY_MS
let attempts = 0
while (attemptAt < resumedAt + 3300) {
  graceStreak = model.nextStreak(graceStreak, false, model.inResumeGrace(attemptAt, resumedAt))
  assert(!model.isUnavailable(graceStreak), 'a miss ' + (attemptAt - resumedAt) + 'ms after resume must not show the notice')
  attemptAt += model.retryDelayMs(graceStreak)
  attempts++
}
assert(attempts >= 3, 'the loop keeps retrying through the restart window, got ' + attempts)
assert(attemptAt - resumedAt < 3300 + model.ERROR_RETRY_BASE_MS + model.MATCH_RETRY_MS,
  'the first attempt after the daemon is back comes within a tier, at ' + (attemptAt - resumedAt) + 'ms')

// Probe classification (#9453): only a definitive answer may change state.
assertEqual(model.classifyProbe('found 1 devices\nFingerprints for user g on X:\n - #0: right-index-finger'), 'yes', 'an enrolled print row reads yes')
assertEqual(model.classifyProbe('no'), 'no', "the probe script's own no reads no")
assertEqual(model.classifyProbe('found 1 devices\nUser bob has no fingers enrolled.'), 'no', "fprintd's explicit no-prints answer reads no")
assertEqual(model.classifyProbe('Impossible to get devices: GDBus.Error:org.freedesktop.DBus.Error.NameHasNoOwner: Could not activate remote peer'), 'unknown', 'an activation failure reads unknown, not unconfigured')
assertEqual(model.classifyProbe('ListEnrolledFingers failed: Timeout was reached'), 'unknown', 'a D-Bus timeout reads unknown')
assertEqual(model.classifyProbe(''), 'unknown', 'empty output reads unknown')

assert(model.REACH_TIMEOUT_MS < model.ERROR_RETRY_CAP_MS,
  'the reach bound is shorter than the backoff cap, so a stuck attempt is caught well before the cap')
assert(model.REACH_TIMEOUT_MS < 25000,
  "the reach bound lands before GDBus fails a stuck Claim at 25s and pam_fprintd's 30s verify timeout reports as a non-error message")
assert(model.REACH_TIMEOUT_MS >= 10000,
  'the reach bound outlasts a slow device open, so a reader that takes seconds to claim is not killed mid-Claim on every attempt')
JS
