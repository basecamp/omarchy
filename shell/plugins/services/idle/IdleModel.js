function secondsFromConfig(value, fallback) {
  var n
  if (typeof value === "number") n = value
  else if (typeof value === "string" && value.trim() !== "") n = Number(value)
  else return fallback
  if (!isFinite(n) || n < 0) return fallback
  return Math.floor(n)
}

function profileBlock(idleConfig, name) {
  var block = idleConfig && idleConfig[name]
  if (!block || typeof block !== "object" || Array.isArray(block)) return null
  return block
}

function effectiveTimeouts(idleConfig, onBattery, defaults) {
  var config = idleConfig && typeof idleConfig === "object" ? idleConfig : {}
  var fallbackScreensaver = secondsFromConfig(config.screensaver, defaults && defaults.screensaver)
  var fallbackLock = secondsFromConfig(config.lock, defaults && defaults.lock)
  var profile = profileBlock(config, onBattery ? "battery" : "ac")
  if (!profile) {
    return { screensaver: fallbackScreensaver, lock: fallbackLock }
  }
  return {
    screensaver: secondsFromConfig(profile.screensaver, fallbackScreensaver),
    lock: secondsFromConfig(profile.lock, fallbackLock)
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
    profileBlock: profileBlock,
    effectiveTimeouts: effectiveTimeouts,
    eventParts: eventParts,
    screensaverWindowsAfter: screensaverWindowsAfter
  }
}
