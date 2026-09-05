// Parsing and pacing for pausing fingerprint checks across suspend. login1
// emits PrepareForSleep as a multi-line dbus-monitor block: a header line
// naming the member, then a separate body line carrying the boolean
// argument. Track "we just saw the header" independently of the value line
// itself, so a change of interface or path in the header can never be read
// as a boolean that happens to appear nearby.

function parseSleepSignalLine(awaitingValue, line) {
  var text = String(line || "")

  if (text.indexOf("member=PrepareForSleep") !== -1) {
    return { awaitingValue: true, event: null }
  }

  if (!awaitingValue) return { awaitingValue: false, event: null }

  if (text.indexOf("boolean true") !== -1) {
    return { awaitingValue: false, event: "pause" }
  }

  if (text.indexOf("boolean false") !== -1) {
    return { awaitingValue: false, event: "resume" }
  }

  return { awaitingValue: awaitingValue, event: null }
}

// A small margin, not the reader's full recovery envelope: every observed
// resume on the reproducer hardware succeeded on the very first post-resume
// check, so this is cheap insurance for hardware slower than that, not a
// budget sized off a witnessed worst case.
var RESUME_ATTEMPT_BUDGET = 3
var RESUME_BUDGET_MS = 5000

// The reader can take a moment to recover after resume, so re-probe instead
// of trusting the first answer -- but bounded by wall-clock time as well as
// attempt count. Each probe carries its own timeout, so a run of genuinely
// hung probes must not be able to stretch this past the budget attempt
// count alone would suggest.
function shouldRetryResumeProbe(attemptsRemaining, deadlineAt, now) {
  return attemptsRemaining > 0 && now < deadlineAt
}

if (typeof module !== "undefined") {
  module.exports = {
    RESUME_ATTEMPT_BUDGET: RESUME_ATTEMPT_BUDGET,
    RESUME_BUDGET_MS: RESUME_BUDGET_MS,
    parseSleepSignalLine: parseSleepSignalLine,
    shouldRetryResumeProbe: shouldRetryResumeProbe
  }
}
