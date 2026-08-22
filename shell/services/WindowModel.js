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

// Hyprland 0.56 `hyprctl -j monitors` reserved is left, top, right, bottom
// (CReservedArea in HyprCtl.cpp). Older wiki text said top, right, bottom, left;
// reading that order turns a bottom taskbar into a left inset.
function reservedLTRB(reserved) {
  var r = reserved || []
  return {
    left: Number(r[0] || 0),
    top: Number(r[1] || 0),
    right: Number(r[2] || 0),
    bottom: Number(r[3] || 0)
  }
}

function workArea(monitor) {
  var width = Number((monitor && monitor.width) || 0)
  var height = Number((monitor && monitor.height) || 0)
  var r = reservedLTRB(monitor && monitor.reserved)
  return {
    x: r.left,
    y: r.top,
    width: width - r.left - r.right,
    height: height - r.top - r.bottom
  }
}

function snapRect(monitor, side, titleBar) {
  var area = workArea(monitor)
  var top = Number(titleBar || 0)
  var y = area.y + top
  var height = area.height - top
  if (height < 1) height = area.height
  var half = Math.floor(area.width / 2)
  if (side === "l") {
    return { x: area.x, y: y, width: half, height: height }
  }
  return { x: area.x + half, y: y, width: area.width - half, height: height }
}

// Quickshell Hyprland.Monitor.width/height can already exclude gaps. Snap must
// use compositor JSON (hyprctl -j monitors / lastIpcObject) only.
function compositorMonitor(ipc) {
  ipc = ipc || {}
  return {
    width: Number(ipc.width || 0),
    height: Number(ipc.height || 0),
    reserved: ipc.reserved || [0, 0, 0, 0]
  }
}

function nearRect(win, rect, slop) {
  if (!win || !rect) return false
  var n = slop == null ? 8 : Number(slop)
  var x = Number(win.x)
  var y = Number(win.y)
  var w = Number(win.width)
  var h = Number(win.height)
  if (win.at) {
    if (win.x == null) x = Number(win.at[0] || 0)
    if (win.y == null) y = Number(win.at[1] || 0)
  }
  if (win.size) {
    if (win.width == null) w = Number(win.size[0] || 0)
    if (win.height == null) h = Number(win.size[1] || 0)
  }
  return Math.abs(x - rect.x) <= n
    && Math.abs(y - rect.y) <= n
    && Math.abs(w - rect.width) <= n
    && Math.abs(h - rect.height) <= n
}

function isSnapped(win, monitor, slop, titleBar) {
  return nearRect(win, snapRect(monitor, "l", titleBar), slop) || nearRect(win, snapRect(monitor, "r", titleBar), slop)
}

function defaultFloatRect(monitor) {
  var area = workArea(monitor)
  var width = Math.min(880, Math.max(640, Math.floor(area.width * 0.46)))
  var height = Math.min(560, Math.max(400, Math.floor(area.height * 0.54)))
  if (area.width > 0 && width > area.width - 96) width = Math.max(320, area.width - 96)
  if (area.height > 0 && height > area.height - 96) height = Math.max(240, area.height - 96)
  var x = area.x + Math.max(48, Math.floor((area.width - width) / 5))
  var y = area.y + Math.max(48, Math.floor((area.height - height) / 6))
  return { x: x, y: y, width: width, height: height }
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
    buildGroups: buildGroups,
    reservedLTRB: reservedLTRB,
    workArea: workArea,
    snapRect: snapRect,
    compositorMonitor: compositorMonitor,
    nearRect: nearRect,
    isSnapped: isSnapped,
    defaultFloatRect: defaultFloatRect
  }
}
