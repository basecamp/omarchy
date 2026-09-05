// Empty legacy files mean indefinitely. A timed file contains its deadline in milliseconds.
var maxStayAwakeSeconds = 24 * 60 * 60

function stayAwakeDeadline(seconds, now) {
  var duration = Number(seconds)
  if (!Number.isInteger(duration) || duration <= 0 || duration > maxStayAwakeSeconds) return 0
  return now + duration * 1000
}

function stayAwakeState(raw, now) {
  var disabled = { enabled: false, until: 0 }
  if (raw === "yes:") return { enabled: true, until: 0 }
  if (raw.indexOf("yes:") !== 0 || raw.length > 32) return disabled

  var value = raw.slice(4).replace(/\n+$/, "")
  if (/^[0-9]{1,10}:[0-9]{1,5}:[0-9]{1,5}$/.test(value)) return { enabled: true, until: 0 }
  var until = Number(value)
  if (!/^[0-9]{1,16}$/.test(value) || !Number.isSafeInteger(until)) return disabled
  if (until <= now || until > now + maxStayAwakeSeconds * 1000) return disabled
  return { enabled: true, until: until }
}

function secondsFromConfig(value, fallback) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return fallback
  return Math.floor(n)
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
    stayAwakeState: stayAwakeState,
    stayAwakeDeadline: stayAwakeDeadline,
    secondsFromConfig: secondsFromConfig,
    eventParts: eventParts,
    screensaverWindowsAfter: screensaverWindowsAfter
  }
}
