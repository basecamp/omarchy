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
  var rest = area.width - half
  var qh = Math.floor(height / 2)
  var qh2 = height - qh
  if (side === "l") return { x: area.x, y: y, width: half, height: height }
  if (side === "r") return { x: area.x + half, y: y, width: rest, height: height }
  if (side === "tl") return { x: area.x, y: y, width: half, height: qh }
  if (side === "tr") return { x: area.x + half, y: y, width: rest, height: qh }
  if (side === "bl") return { x: area.x, y: y + qh, width: half, height: qh2 }
  if (side === "br") return { x: area.x + half, y: y + qh, width: rest, height: qh2 }
  return { x: area.x, y: y, width: half, height: height }
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

function snapSides() {
  return ["tl", "tr", "bl", "br", "l", "r"]
}

function snapKind(win, monitor, slop, titleBar) {
  var sides = snapSides()
  var i
  for (i = 0; i < sides.length; i++) {
    if (nearRect(win, snapRect(monitor, sides[i], titleBar), slop)) return sides[i]
  }
  return "float"
}

function isSnapped(win, monitor, slop, titleBar) {
  return snapKind(win, monitor, slop, titleBar) !== "float"
}

// Win+Arrow cycle. Returns a snap kind, "max", "min", or "normal".
function nextSnap(kind, dir) {
  var k = String(kind || "float")
  var d = String(dir || "")
  if (k === "max") {
    if (d === "d") return "normal"
    if (d === "l") return "l"
    if (d === "r") return "r"
    return "max"
  }
  if (k === "float") {
    if (d === "l") return "l"
    if (d === "r") return "r"
    if (d === "u") return "max"
    if (d === "d") return "min"
    return "float"
  }
  if (k === "l") {
    if (d === "r") return "r"
    if (d === "u") return "tl"
    if (d === "d") return "bl"
    return "l"
  }
  if (k === "r") {
    if (d === "l") return "l"
    if (d === "u") return "tr"
    if (d === "d") return "br"
    return "r"
  }
  if (k === "tl") {
    if (d === "d") return "l"
    if (d === "r") return "tr"
    if (d === "u") return "max"
    return "tl"
  }
  if (k === "tr") {
    if (d === "d") return "r"
    if (d === "l") return "tl"
    if (d === "u") return "max"
    return "tr"
  }
  if (k === "bl") {
    if (d === "u") return "l"
    if (d === "r") return "br"
    if (d === "d") return "normal"
    return "bl"
  }
  if (k === "br") {
    if (d === "u") return "r"
    if (d === "l") return "bl"
    if (d === "d") return "normal"
    return "br"
  }
  return "float"
}

// After a title-bar drag, map the pointer onto Aero zones. Window box is the
// wrong input: a maximized client hits every edge at once.
function aeroZone(pointer, monitor) {
  var area = workArea(monitor)
  var x = Number(pointer && pointer.x)
  var y = Number(pointer && pointer.y)
  var edge = 28
  var corner = 48
  var leftHit = x <= area.x + edge
  var rightHit = x >= area.x + area.width - edge
  var topHit = y <= area.y + 16
  var bottomHit = y >= area.y + area.height - edge
  var topCorner = y <= area.y + corner
  var bottomCorner = y >= area.y + area.height - corner
  if (leftHit && topCorner) return "tl"
  if (rightHit && topCorner) return "tr"
  if (leftHit && bottomCorner) return "bl"
  if (rightHit && bottomCorner) return "br"
  if (topHit) return "max"
  if (leftHit) return "l"
  if (rightHit) return "r"
  if (bottomHit) return ""
  return ""
}

function serializeLayout(layout) {
  return JSON.stringify({ windows: (layout && layout.windows) || [] }, null, 2) + "\n"
}

function parseLayout(raw) {
  try {
    var parsed = JSON.parse(String(raw || "{}"))
    if (parsed && Array.isArray(parsed.windows)) return { windows: parsed.windows }
  } catch (e) {
  }
  return { windows: [] }
}

function captureLayout(windows, monitor, titleBar) {
  var list = []
  var i
  var win
  var maximized
  var kind
  windows = windows || []
  for (i = 0; i < windows.length; i++) {
    win = windows[i]
    if (!win || !win.address) continue
    maximized = Number(win.fullscreen) === 1
    kind = maximized ? "max" : (win.minimized ? "min" : snapKind(win, monitor, 8, titleBar))
    list.push({
      address: String(win.address || ""),
      appId: windowAppId(win),
      title: String(win.title || ""),
      kind: kind,
      x: Number(win.x || 0),
      y: Number(win.y || 0),
      width: Number(win.width || 0),
      height: Number(win.height || 0)
    })
  }
  return { windows: list }
}

function matchLayout(windows, layout) {
  var used = ({})
  var out = []
  var entries = (layout && layout.windows) || []
  var i
  var j
  var entry
  var found
  windows = windows || []

  function takeBy(predicate) {
    var k
    for (k = 0; k < windows.length; k++) {
      if (!windows[k] || !windows[k].address || used[windows[k].address]) continue
      if (predicate(windows[k])) return windows[k]
    }
    return null
  }

  for (i = 0; i < entries.length; i++) {
    entry = entries[i]
    if (!entry) continue
    found = null
    if (entry.address) found = takeBy(function(win) { return String(win.address) === String(entry.address) })
    if (!found) {
      found = takeBy(function(win) {
        return windowAppId(win) === normalizeId(entry.appId) || windowAppId(win) === windowAppId(entry)
      })
    }
    if (!found) continue
    used[found.address] = true
    out.push({
      address: found.address,
      kind: String(entry.kind || "float"),
      x: Number(entry.x || 0),
      y: Number(entry.y || 0),
      width: Number(entry.width || 0),
      height: Number(entry.height || 0)
    })
  }
  return out
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
    snapSides: snapSides,
    snapKind: snapKind,
    compositorMonitor: compositorMonitor,
    nearRect: nearRect,
    isSnapped: isSnapped,
    nextSnap: nextSnap,
    aeroZone: aeroZone,
    serializeLayout: serializeLayout,
    parseLayout: parseLayout,
    captureLayout: captureLayout,
    matchLayout: matchLayout,
    defaultFloatRect: defaultFloatRect
  }
}
