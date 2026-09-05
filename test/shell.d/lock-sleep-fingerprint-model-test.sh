#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const model = requireFromRoot('shell/plugins/lock/SleepFingerprintModel.js')

// dbus-monitor emits PrepareForSleep as a header line, then a separate body
// line with the boolean. Neither line alone is enough signal.
function feed(lines) {
  let awaiting = false
  const events = []
  for (const line of lines) {
    const result = model.parseSleepSignalLine(awaiting, line)
    awaiting = result.awaitingValue
    if (result.event) events.push(result.event)
  }
  return { awaiting, events }
}

assertDeepEqual(
  feed(["signal sender=:1.2 -> member=PrepareForSleep", "   boolean true"]).events,
  ["pause"],
  "a PrepareForSleep header followed by boolean true is a pause"
)

assertDeepEqual(
  feed(["signal sender=:1.2 -> member=PrepareForSleep", "   boolean false"]).events,
  ["resume"],
  "a PrepareForSleep header followed by boolean false is a resume"
)

assertDeepEqual(
  feed(["   boolean true"]).events,
  [],
  "a boolean line with no preceding header is not mistaken for a signal"
)

assertDeepEqual(
  feed(["signal sender=:1.2 -> member=SomeOtherSignal", "   boolean true"]).events,
  [],
  "a boolean line after an unrelated member is ignored"
)

assertEqual(
  feed(["signal sender=:1.2 -> member=PrepareForSleep", "   string \"unrelated\""]).awaiting,
  true,
  "a non-boolean body line leaves the header still pending"
)

assertDeepEqual(
  feed([
    "signal sender=:1.2 -> member=PrepareForSleep",
    "   boolean true",
    "signal sender=:1.2 -> member=PrepareForSleep",
    "   boolean false"
  ]).events,
  ["pause", "resume"],
  "consecutive sleep/wake signals are each parsed independently"
)

// Resume budget: bounded by wall-clock time as well as attempt count, so a
// run of hung probes (each carrying its own timeout) cannot stretch the
// recovery window past what the budget advertises.
assert(
  model.shouldRetryResumeProbe(1, Date.now() + 5000, Date.now()),
  "retries while attempts remain and the deadline has not passed"
)
assert(
  !model.shouldRetryResumeProbe(0, Date.now() + 5000, Date.now()),
  "stops once attempts are exhausted even with time left on the clock"
)
assert(
  !model.shouldRetryResumeProbe(10, Date.now() - 1, Date.now()),
  "stops once the deadline has passed even with attempts left"
)

assert(model.RESUME_ATTEMPT_BUDGET > 0, "the attempt budget is a positive count")
assert(model.RESUME_BUDGET_MS > 0, "the wall-clock budget is a positive duration")
JS
