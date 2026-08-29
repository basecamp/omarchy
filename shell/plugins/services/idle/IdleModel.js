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

var DEFAULT_GAMEPAD_GRACE_SECONDS = 120

// The compositor's idle timer only sees what libinput reports, which leaves
// gamepads and media playback invisible to it. omarchy-idle-activity watches
// both; these shape the call and read its answers.
function activitySettings(idleConfig) {
  var config = idleConfig || {}

  return {
    gamepad: config.inhibitWhenGamepadActive === undefined ? true : !!config.inhibitWhenGamepadActive,
    audio: config.inhibitWhenAudioPlaying === undefined ? true : !!config.inhibitWhenAudioPlaying,
    gamepadGrace: secondsFromConfig(config.gamepadGrace, DEFAULT_GAMEPAD_GRACE_SECONDS)
  }
}

function activityWatchWanted(settings) {
  return !!(settings && (settings.gamepad || settings.audio))
}

function activityCommand(settings) {
  var command = ["omarchy-idle-activity"]

  if (!settings.gamepad) command.push("--no-gamepad")
  if (!settings.audio) command.push("--no-audio")
  command.push("--gamepad-grace", String(settings.gamepadGrace))

  return command
}

function isActivityLine(line) {
  return String(line).trim() === "ACTIVE"
}

if (typeof module !== "undefined") {
  module.exports = {
    secondsFromConfig: secondsFromConfig,
    eventParts: eventParts,
    screensaverWindowsAfter: screensaverWindowsAfter,
    activitySettings: activitySettings,
    activityWatchWanted: activityWatchWanted,
    activityCommand: activityCommand,
    isActivityLine: isActivityLine
  }
}
