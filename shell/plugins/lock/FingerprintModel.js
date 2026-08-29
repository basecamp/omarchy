// Retry pacing and the availability signal for the lock screen's fingerprint
// loop. The signal is whether an attempt reached the reader at all: pam_fprintd
// relays a "place your finger" prompt only once the claim has landed and the
// verify is live, so an attempt that ends without ever prompting never reached
// the device -- it is wedged (a verify killed by suspend), held by another
// client, or gone. Those are what the backoff paces and the notice reports. An
// attempt that did prompt proves the reader works (the user simply has not
// swiped yet), so it clears the streak and the loop stays responsive.
//
// A finger that merely fails to match still prompted, so it resets too and
// retries fast. Consecutive unreached attempts back off exponentially to a
// ceiling above fprintd's 30-second idle exit, so a claim wedged without the
// resume hook clearing it can still recover once the retries let fprintd idle
// out.

var MATCH_RETRY_MS = 250
var ERROR_RETRY_BASE_MS = 1000
var ERROR_RETRY_CAP_MS = 40000
var UNAVAILABLE_AFTER = 3
var NUDGE_COOLDOWN_MS = 2000
var REACH_TIMEOUT_MS = 5000

function retryDelayMs(streak) {
  if (streak <= 0) return MATCH_RETRY_MS
  var delay = ERROR_RETRY_BASE_MS * Math.pow(2, streak - 1)
  return Math.min(delay, ERROR_RETRY_CAP_MS)
}

// Whether user presence should collapse the current backoff wait to a prompt
// retry: only when a wait longer than the fast interval is pending, and at most
// once per cooldown. The cooldown is what stops a moving cursor -- which raises
// one wake per motion event -- from re-collapsing every fresh wait and spinning
// the loop back up to the storm the backoff exists to prevent. It grows with
// the pending wait: presence collapses each backed-off wait once, but a user
// who keeps typing at a reader that keeps failing is still paced by the tier,
// so the cap's rate holds and fprintd gets the idle stretch it needs to exit.
function shouldNudge(nowMs, lastNudgeMs, currentIntervalMs) {
  if (currentIntervalMs <= MATCH_RETRY_MS) return false
  var elapsed = nowMs - lastNudgeMs
  // Wall-clock time can step backwards (timesyncd corrects RTC drift right
  // after resume); a negative gap is stale, not a fresh nudge, so allow it.
  if (elapsed < 0) return true
  return elapsed >= Math.max(NUDGE_COOLDOWN_MS, currentIntervalMs)
}

// The streak after an attempt: a reached attempt clears it, an unreached one
// advances it.
function nextStreak(streak, reachedDevice) {
  return reachedDevice ? 0 : streak + 1
}

// The reader is reported unavailable once enough consecutive attempts have
// failed to reach it -- past any single transient claim conflict, but still
// within a few seconds of a wake.
function isUnavailable(streak) {
  return streak >= UNAVAILABLE_AFTER
}

if (typeof module !== "undefined") {
  module.exports = {
    MATCH_RETRY_MS: MATCH_RETRY_MS,
    ERROR_RETRY_BASE_MS: ERROR_RETRY_BASE_MS,
    ERROR_RETRY_CAP_MS: ERROR_RETRY_CAP_MS,
    UNAVAILABLE_AFTER: UNAVAILABLE_AFTER,
    NUDGE_COOLDOWN_MS: NUDGE_COOLDOWN_MS,
    REACH_TIMEOUT_MS: REACH_TIMEOUT_MS,
    retryDelayMs: retryDelayMs,
    nextStreak: nextStreak,
    isUnavailable: isUnavailable,
    shouldNudge: shouldNudge
  }
}
