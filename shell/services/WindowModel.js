function normalizeId(value) {
  var id = String(value || "").trim().toLowerCase()
  if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
  return id
}

function windowAppId(win) {
  if (!win) return ""
  return normalizeId(win.appId || win["class"] || "")
}

function windowMatchesPin(win, pin) {
  var app = windowAppId(win)
  var pinId = normalizeId(pin && (pin.id || pin.desktopId))
  if (!app || !pinId) return false
  return app === pinId || app.indexOf(pinId) !== -1 || pinId.indexOf(app) !== -1
}

function parsePins(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    if (Array.isArray(parsed)) return parsed
    if (parsed && Array.isArray(parsed.pins)) return parsed.pins
  } catch (e) {
  }
  return []
}

function serializePins(pins) {
  return JSON.stringify({ pins: pins || [] }, null, 2) + "\n"
}

function pinIndex(pins, desktopId) {
  var id = normalizeId(desktopId)
  for (var i = 0; i < (pins || []).length; i++) {
    if (normalizeId(pins[i].id || pins[i].desktopId) === id) return i
  }
  return -1
}

function withPin(pins, entry) {
  var next = (pins || []).slice()
  if (pinIndex(next, entry.desktopId || entry.id) >= 0) return next
  next.push({
    id: normalizeId(entry.id || entry.desktopId),
    desktopId: String(entry.desktopId || entry.id || ""),
    name: String(entry.name || ""),
    icon: String(entry.icon || "")
  })
  return next
}

function withoutPin(pins, desktopId) {
  var id = normalizeId(desktopId)
  var next = []
  for (var i = 0; i < (pins || []).length; i++) {
    if (normalizeId(pins[i].id || pins[i].desktopId) !== id) next.push(pins[i])
  }
  return next
}

function buildGroups(windows, pins) {
  var list = []
  var used = ({})
  var i
  var j
  var pin
  var win
  var wins
  pins = pins || []
  windows = windows || []

  for (i = 0; i < pins.length; i++) {
    pin = pins[i]
    if (!pin) continue
    wins = []
    for (j = 0; j < windows.length; j++) {
      win = windows[j]
      if (windowMatchesPin(win, pin)) {
        wins.push(win)
        if (win.address) used[win.address] = true
      }
    }
    list.push({
      id: normalizeId(pin.id || pin.desktopId),
      desktopId: String(pin.desktopId || pin.id || ""),
      name: String(pin.name || pin.desktopId || pin.id || ""),
      icon: String(pin.icon || ""),
      pinned: true,
      windows: wins
    })
  }

  var byApp = ({})
  var order = []
  for (j = 0; j < windows.length; j++) {
    win = windows[j]
    if (!win || (win.address && used[win.address])) continue
    var key = windowAppId(win) || String(win.address || j)
    if (!byApp[key]) {
      byApp[key] = {
        id: key,
        desktopId: windowAppId(win),
        name: String(win.title || key),
        icon: String(win.appId || ""),
        pinned: false,
        windows: []
      }
      order.push(key)
    }
    byApp[key].windows.push(win)
    if (win.title) byApp[key].name = String(win.title)
  }
  for (i = 0; i < order.length; i++) list.push(byApp[order[i]])
  return list
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeId: normalizeId,
    windowAppId: windowAppId,
    windowMatchesPin: windowMatchesPin,
    parsePins: parsePins,
    serializePins: serializePins,
    pinIndex: pinIndex,
    withPin: withPin,
    withoutPin: withoutPin,
    buildGroups: buildGroups
  }
}
