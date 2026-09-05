function secondsFromConfig(value, fallback) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return fallback
  return Math.floor(n)
}

// ext-idle-notify treats a zero timeout as "report idle immediately", so the
// schedule never hands the monitor a zero. When nothing is armed there is no
// deadline at all: `armed` is false and the caller stops the monitor. The parked
// value keeps the returned timeout honest for anyone reading it in isolation.
var PARKED_IDLE_TIMEOUT_SECONDS = 3600

// Callers pass a timeout for every action the user left on and null for the
// rest. The fallbacks have already been applied by secondsFromConfig, so
// anything that is not a usable timeout here means "this action is off" rather
// than "use the default".
function armedSeconds(seconds) {
  if (typeof seconds !== "number" || !isFinite(seconds) || seconds < 0) return null
  return Math.floor(seconds)
}

function idleSchedule(screensaverSeconds, lockSeconds, screenOffSeconds) {
  var screensaver = armedSeconds(screensaverSeconds)
  var lock = armedSeconds(lockSeconds)
  var screenOff = armedSeconds(screenOffSeconds)

  var timeouts = [screensaver, lock, screenOff]
  var first = null
  for (var i = 0; i < timeouts.length; i++) {
    if (timeouts[i] === null) continue
    if (first === null || timeouts[i] < first) first = timeouts[i]
  }

  var armed = first !== null
  if (!armed) first = PARKED_IDLE_TIMEOUT_SECONDS
  else if (first <= 0) first = 1

  function delay(seconds) {
    return seconds === null ? 0 : Math.max(0, seconds - first)
  }

  return {
    armed: armed,
    firstIdleTimeoutSeconds: first,
    screensaverArmed: screensaver !== null,
    lockArmed: lock !== null,
    screenOffArmed: screenOff !== null,
    screensaverDelaySeconds: delay(screensaver),
    lockDelaySeconds: delay(lock),
    screenOffDelaySeconds: delay(screenOff)
  }
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
    secondsFromConfig: secondsFromConfig,
    idleSchedule: idleSchedule,
    PARKED_IDLE_TIMEOUT_SECONDS: PARKED_IDLE_TIMEOUT_SECONDS,
    eventParts: eventParts,
    screensaverWindowsAfter: screensaverWindowsAfter
  }
}
