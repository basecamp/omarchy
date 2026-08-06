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

// The idle-inhibit daemon writes {count, inhibitors} to a state file. Parse the
// file text into a safe count: a missing file, unparseable JSON, or an object
// without a numeric count all mean "no inhibitors" so a daemon failure clears a
// stale nonzero count instead of disabling the lock indefinitely.
function inhibitorCountFromText(text) {
  var raw = text !== undefined && text !== null ? String(text) : ""
  if (!raw.length) return 0

  try {
    var parsed = JSON.parse(raw)
    if (parsed && typeof parsed.count === "number" && parsed.count > 0) {
      return Math.floor(parsed.count)
    }
  } catch (error) {
  }
  return 0
}

// Decide what to do when the observed inhibitor count changes. Returns a string
// the caller switches on: "cancel" (an inhibitor appeared mid-cycle, pull back
// the screensaver/lock), "rearm" (all inhibitors released, idle may resume), or
// "noop" (no transition, keep the current behavior).
function inhibitorTransition(previous, current) {
  if (previous === 0 && current > 0) return "cancel"
  if (previous > 0 && current === 0) return "rearm"
  return "noop"
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
    eventParts: eventParts,
    screensaverWindowsAfter: screensaverWindowsAfter,
    inhibitorCountFromText: inhibitorCountFromText,
    inhibitorTransition: inhibitorTransition
  }
}
