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

// The screensaver's own window mapping registers as input, so a dismissal
// monitor cannot treat its first activity as the user. It arms only once input
// has gone quiet while the screensaver is on screen; the next activity after
// that is a real keypress, click, or pointer move and dismisses the screensaver.
function screensaverDismissAction(armed, isIdle, screensaverVisible) {
  if (!screensaverVisible) return "ignore"
  if (isIdle) return armed ? "ignore" : "arm"
  return armed ? "dismiss" : "ignore"
}

if (typeof module !== "undefined") {
  module.exports = {
    secondsFromConfig: secondsFromConfig,
    eventParts: eventParts,
    screensaverWindowsAfter: screensaverWindowsAfter,
    screensaverDismissAction: screensaverDismissAction
  }
}
