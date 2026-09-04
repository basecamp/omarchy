// Whether a tick that waited `interval` came back to a wall clock that had
// moved by something else entirely. Qt-free so it can be unit tested under
// node (test/shell.d/clock-test.sh).
//
// The comparison is against the deviation from the interval, not against the
// elapsed time itself: a tick is expected to find `interval` milliseconds
// gone, and only the surplus — or the shortfall, when the clock is stepped
// backwards — says the clock was moved rather than advanced.
function isDiscontinuity(elapsedMs, interval, threshold) {
  return Math.abs(Number(elapsedMs) - Number(interval)) >= Number(threshold)
}

if (typeof module !== "undefined") {
  module.exports = {
    isDiscontinuity: isDiscontinuity
  }
}
