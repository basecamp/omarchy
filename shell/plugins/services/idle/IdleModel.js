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

function playerHaystack(player) {
  return [
    player && player.dbusName,
    player && player.desktopEntry,
    player && player.identity
  ].join(" ").toLowerCase()
}

function isProxyPlayer(player) {
  return playerHaystack(player).indexOf("playerctld") !== -1
}

function isFirefoxFamilyPlayer(player) {
  if (!player || isProxyPlayer(player)) return false

  var dbus = String(player.dbusName || "").toLowerCase()
  var desktop = String(player.desktopEntry || "").toLowerCase()
  var identity = String(player.identity || "").toLowerCase()
  var hay = dbus + " " + desktop + " " + identity

  if (hay.indexOf("firefox") !== -1) return true
  if (hay.indexOf("librewolf") !== -1) return true
  if (hay.indexOf("zen-browser") !== -1) return true
  if (hay.indexOf("zen browser") !== -1) return true
  if (/\.zen(\.|$)/.test(dbus)) return true
  if (desktop === "zen" || desktop.indexOf("zen.") === 0) return true
  return false
}

function firefoxFamilyIsPlaying(players) {
  var list = Array.isArray(players) ? players : []
  for (var i = 0; i < list.length; i++) {
    if (isFirefoxFamilyPlayer(list[i]) && list[i].isPlaying) return true
  }
  return false
}

function idleEnabledAfter(stayAwakeStateLoaded, stayAwake, mediaInhibiting) {
  return !!stayAwakeStateLoaded && !stayAwake && !mediaInhibiting
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
    playerHaystack: playerHaystack,
    isProxyPlayer: isProxyPlayer,
    isFirefoxFamilyPlayer: isFirefoxFamilyPlayer,
    firefoxFamilyIsPlaying: firefoxFamilyIsPlaying,
    idleEnabledAfter: idleEnabledAfter,
    screensaverWindowsAfter: screensaverWindowsAfter
  }
}
