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

// The D-Bus inhibit daemon (omarchy-idle-inhibit-daemon) publishes its state
// as JSON to the runtime dir; the idle service reads it back through this
// parser. Tolerance is the contract: a daemon that is down, crashed mid-write,
// or publishing garbage reads as "nothing inhibited", so a broken state file
// can never pin the idle timers off permanently.
function externalInhibitFromState(raw) {
  var state = { inhibited: false }

  try {
    var parsed = JSON.parse(String(raw || ""))
    if (!parsed || typeof parsed !== "object") return state
    if (parsed.inhibited !== true) return state
    if (!Array.isArray(parsed.holders) || parsed.holders.length === 0) return state
    return { inhibited: true }
  } catch (error) {
    return state
  }
}

// The IdleMonitor gate. stayAwakeStateLoaded stays a term because an unloaded
// indicator state must not read as "idle allowed" on a race with the probe.
function idleEnabledAfter(stayAwakeStateLoaded, stayAwake, externalInhibit) {
  if (!stayAwakeStateLoaded) return false
  if (stayAwake) return false
  if (externalInhibit) return false
  return true
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
    externalInhibitFromState: externalInhibitFromState,
    idleEnabledAfter: idleEnabledAfter
  }
}
