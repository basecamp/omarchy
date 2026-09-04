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
// fprintd exits this long after its last client leaves; a claim wedged by a
// verify killed under suspend dies with it. The cap sits above it so that,
// with no hook to restart the daemon, a wait at the cap still clears it.
var FPRINTD_IDLE_EXIT_MS = 30000
var ERROR_RETRY_CAP_MS = 40000
// The idle stretch a nudge must leave fprintd at the cap: its exit plus a
// margin, so the daemon is gone before the nudged attempt claims.
var IDLE_CLEAR_MS = FPRINTD_IDLE_EXIT_MS + 2000
var UNAVAILABLE_AFTER = 3
var NUDGE_COOLDOWN_MS = 2000
// How long an attempt may go without prompting before it is aborted as stuck.
// Bounded above by pam_fprintd: its 30s verify timeout ends the attempt with a
// non-error "Verification timed out" message that would read as reached, and
// GDBus fails a Claim that never returns at 25s. Bounded below by the reader:
// aborting kills the PAM child mid-Claim, which fprintd keeps tearing down
// until the device open completes, so the bound must outlast a slow open --
// out-of-tree drivers take several seconds, more right after resume.
var REACH_TIMEOUT_MS = 20000
// Monotonic timers pause across suspend, so a wait or an attempt that took
// this much longer on the wall clock than it should have spanned a sleep.
var SLEEP_GAP_MS = 2000
// For this long after a resume the hook is restarting fprintd underneath the
// loop (a 3s stop cap plus the start), so a miss says nothing about the
// reader; misses inside it keep retrying at the first tier and never count
// toward the notice.
var RESUME_GRACE_MS = 5000

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
// who keeps typing at a reader that keeps failing is still paced by the tier.
//
// At the cap the wait itself is the cure -- it is what lets fprintd idle out
// and drop a wedged claim -- so there the idle stretch is measured from the
// last settle, not the last nudge: a nudged attempt that hung until the reach
// timeout would otherwise eat most of the window, and under continuous input
// fprintd would never be left alone long enough to exit.
function shouldNudge(nowMs, lastNudgeMs, lastSettleMs, currentIntervalMs) {
  if (currentIntervalMs <= MATCH_RETRY_MS) return false
  var sinceNudge = nowMs - lastNudgeMs
  var sinceSettle = nowMs - lastSettleMs
  // Wall-clock time can step backwards (timesyncd corrects RTC drift right
  // after resume). A negative nudge gap is stale, not a fresh nudge, so it
  // does not hold the nudge back. A negative settle gap is unknown idle time:
  // below the cap that is harmless, but at the cap the idle stretch is the
  // cure, so it counts as no idle at all rather than as enough.
  if (sinceNudge >= 0 && sinceNudge < Math.max(NUDGE_COOLDOWN_MS, currentIntervalMs)) return false
  if (sinceSettle < 0) sinceSettle = 0
  if (currentIntervalMs >= ERROR_RETRY_CAP_MS && sinceSettle < IDLE_CLEAR_MS) return false
  return true
}

// What a status probe's output means. "yes": an enrolled print exists
// (fprintd-list prints one " - #N: finger" row per print). "no": definitely
// not configured -- the probe script's own "no" (PAM file or fprintd-list
// missing) or fprintd's explicit no-prints answer. Anything else is
// "unknown": fprintd unreachable or restarting, which is exactly what the
// resume hook produces, so a probe that could not tell must not overwrite
// what the lock already knows -- concluding "no" switched off the retry
// loop, the sleep watch and the notice for the rest of the lock (#9453).
function classifyProbe(text) {
  var s = String(text || "").trim()
  if (s.indexOf(" - #") !== -1) return "yes"
  if (s === "no") return "no"
  if (/has no fingers enrolled/i.test(s)) return "no"
  return "unknown"
}

// The streak after an attempt: a reached attempt clears it, an unreached one
// advances it -- unless the machine just woke, in which case the miss is
// most likely the resume restart landing under the attempt and the streak
// holds at the first tier instead.
function nextStreak(streak, reachedDevice, inResumeGrace) {
  if (reachedDevice) return 0
  if (inResumeGrace) return 1
  return streak + 1
}

// Whether something that should have taken expectedMs of monotonic time took
// so much longer on the wall clock that the machine must have slept meanwhile.
// A stalled event loop reads the same way, and a stall over the slack opens a
// resume grace with no suspend behind it. That is tolerated: the grace only
// pins the streak at the first tier, so even a loop stalling continuously
// degrades to one attempt a second, still well under the storm it replaces.
function spannedSleep(elapsedMs, expectedMs) {
  return elapsedMs > expectedMs + SLEEP_GAP_MS
}

// Whether a resume noted at resumedAtMs still covers an attempt settling now.
function inResumeGrace(nowMs, resumedAtMs) {
  if (resumedAtMs <= 0) return false
  var elapsed = nowMs - resumedAtMs
  return elapsed >= 0 && elapsed < RESUME_GRACE_MS
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
    FPRINTD_IDLE_EXIT_MS: FPRINTD_IDLE_EXIT_MS,
    IDLE_CLEAR_MS: IDLE_CLEAR_MS,
    UNAVAILABLE_AFTER: UNAVAILABLE_AFTER,
    NUDGE_COOLDOWN_MS: NUDGE_COOLDOWN_MS,
    REACH_TIMEOUT_MS: REACH_TIMEOUT_MS,
    SLEEP_GAP_MS: SLEEP_GAP_MS,
    RESUME_GRACE_MS: RESUME_GRACE_MS,
    spannedSleep: spannedSleep,
    classifyProbe: classifyProbe,
    inResumeGrace: inResumeGrace,
    retryDelayMs: retryDelayMs,
    nextStreak: nextStreak,
    isUnavailable: isUnavailable,
    shouldNudge: shouldNudge
  }
}
