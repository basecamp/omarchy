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
assert(model.ERROR_RETRY_CAP_MS > 30000, "the cap exceeds fprintd's 30-second idle exit so a wedged claim can clear")

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
assert(!model.shouldNudge(10000, 0, model.MATCH_RETRY_MS), 'no nudge when the wait is already the fast interval')
assert(model.shouldNudge(10000, 0, backedOff), 'a keypress collapses a backed-off wait')
assert(!model.shouldNudge(10000, 9000, backedOff), 'a second nudge inside the cooldown is refused')
assert(model.shouldNudge(10000, 10000 - model.NUDGE_COOLDOWN_MS, backedOff), 'a nudge one cooldown later is allowed')

// A cursor moving at 125 Hz raises a wake every 8 ms; over 10 s the floor caps
// the collapses at one per cooldown instead of one per event.
let last = -model.NUDGE_COOLDOWN_MS
let collapses = 0
for (let t = 0; t <= 10000; t += 8) {
  if (model.shouldNudge(t, last, backedOff)) { collapses++; last = t }
}
assert(collapses <= 10000 / model.NUDGE_COOLDOWN_MS + 1,
  'a moving cursor is capped at one collapse per cooldown, got ' + collapses)

assert(model.REACH_TIMEOUT_MS < model.ERROR_RETRY_CAP_MS,
  'the reach bound is shorter than the backoff cap, so a stuck attempt is caught well before the cap')
JS
