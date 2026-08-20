// Timer.interval and IdleMonitor.timeout are signed 32-bit millisecond
// properties. A timeout past this ceiling wraps to a negative interval, which
// Qt clamps to 1ms and re-arms for the whole idle cycle, flooding the instance
// log. Clamp here rather than fall back to the default: someone writing a huge
// number means "as good as never", and a silent drop to 5 minutes locks them
// out of their session. Every derived delay is at most the timeout it came
// from, so this one ceiling keeps the delay timers in range too.
var MAX_TIMEOUT_SECONDS = Math.floor(2147483647 / 1000)

function secondsFromConfig(value, fallback) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return fallback
  return Math.min(Math.floor(n), MAX_TIMEOUT_SECONDS)
}

function eventParts(event, count) {
  try {
    if (event && event.parse) return event.parse(count)
  } catch (error) {
  }
  return String(event && event.data ? event.data : "").split(",")
}

function screensaverWindowsAfter(windows, address, visible) {
  var key = String(address || "")
  if (!key) {
    var current = windows || {}
    var existingCount = 0
    for (var currentKey in current) {
      if (current[currentKey]) existingCount++
    }
    return { windows: current, count: existingCount }
  }

  var next = {}
  var count = 0
  for (var existing in windows || {}) {
    if (existing !== key && windows[existing]) {
      next[existing] = true
      count++
    }
  }

  if (visible) {
    next[key] = true
    count++
  }

  return {
    windows: next,
    count: count
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_TIMEOUT_SECONDS: MAX_TIMEOUT_SECONDS,
    secondsFromConfig: secondsFromConfig,
    eventParts: eventParts,
    screensaverWindowsAfter: screensaverWindowsAfter
  }
}
