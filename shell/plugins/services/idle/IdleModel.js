// The launcher path rides in as $1, never spliced into the script, so no
// configured value can escape or unbalance the isLocked guard (the same
// argv-over-interpolation idiom as Util.execArgv). A missing or non-executable
// launcher falls back to the built-in screensaver; a locked session launches
// nothing at all. The screensaver-off toggle is enforced here so every
// screensaver plugin honors it; the built-in fallback also checks it itself,
// keeping that path identical to what ran before plugin selection existed.
var SCREENSAVER_LAUNCH_SCRIPT = '[[ $(omarchy-shell lock isLocked 2>/dev/null) == "true" ]] && exit 0\n'
  + 'if [[ -n $1 && -x $1 ]] && ! omarchy-toggle-enabled screensaver-off; then\n'
  + '  "$1"\n'
  + 'else\n'
  + '  omarchy-launch-screensaver\n'
  + 'fi'

function screensaverIdFromConfig(value) {
  if (typeof value !== "string") return ""
  return value.trim()
}

function screensaverLaunch(launcherPath) {
  return {
    command: SCREENSAVER_LAUNCH_SCRIPT,
    args: ["omarchy-idle-screensaver", String(launcherPath || "")]
  }
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
    screensaverIdFromConfig: screensaverIdFromConfig,
    screensaverLaunch: screensaverLaunch,
    secondsFromConfig: secondsFromConfig,
    eventParts: eventParts,
    screensaverWindowsAfter: screensaverWindowsAfter
  }
}
