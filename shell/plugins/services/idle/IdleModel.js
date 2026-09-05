// Empty legacy state files mean indefinitely; timed files contain a Unix deadline in milliseconds.
function stayAwakeState(line, now) {
  if (line.indexOf("yes:") !== 0) return { enabled: false, until: 0, expired: false }
  var value = line.slice(4)
  var until = Number(value)
  if (value === "") return { enabled: true, until: 0, expired: false }
  if (!isFinite(until) || until <= now) return { enabled: false, until: 0, expired: true }
  return { enabled: true, until: until, expired: false }
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
    secondsFromConfig: secondsFromConfig,
    eventParts: eventParts,
    screensaverWindowsAfter: screensaverWindowsAfter
  }
}
