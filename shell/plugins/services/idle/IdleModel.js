var DISABLED_SECONDS = -1

// Timer.interval is a signed 32-bit millisecond count, so anything past this
// many seconds wraps around and fires immediately -- the opposite of what a
// very long timeout asks for.
var MAX_SECONDS = 2147483

var DISABLED_WORDS = ["off", "never", "none", "no", "false", "disabled"]

function isDisabled(seconds) {
  return seconds === DISABLED_SECONDS
}

function secondsFromConfig(value, fallback) {
  if (value === null || value === false) return DISABLED_SECONDS
  if (value === undefined || value === true) return fallback

  if (typeof value === "string") {
    var word = value.trim().toLowerCase()
    if (word === "") return fallback
    if (DISABLED_WORDS.indexOf(word) !== -1) return DISABLED_SECONDS
  }

  var n = Number(value)
  if (!isFinite(n)) return fallback
  if (n < 0) return DISABLED_SECONDS
  return Math.min(Math.floor(n), MAX_SECONDS)
}

// The idle monitor arms once, at whichever timeout comes first; a disabled
// timing does not get a say in when that is.
function firstIdleTimeout(screensaverSeconds, lockSeconds) {
  if (isDisabled(screensaverSeconds)) return isDisabled(lockSeconds) ? 0 : lockSeconds
  if (isDisabled(lockSeconds)) return screensaverSeconds
  return Math.min(screensaverSeconds, lockSeconds)
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
    DISABLED_SECONDS: DISABLED_SECONDS,
    MAX_SECONDS: MAX_SECONDS,
    isDisabled: isDisabled,
    secondsFromConfig: secondsFromConfig,
    firstIdleTimeout: firstIdleTimeout,
    eventParts: eventParts,
    screensaverWindowsAfter: screensaverWindowsAfter
  }
}
