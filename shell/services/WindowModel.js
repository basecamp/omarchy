function normalizeId(value) {
  var id = String(value || "").trim().toLowerCase()
  if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
  return id
}

function windowAppId(win) {
  if (!win) return ""
  return normalizeId(win.appId || win["class"] || "")
}

function isLockSurface(win) {
  var ids = [
    normalizeId(win && (win.appId || "")),
    normalizeId(win && (win["class"] || "")),
    normalizeId(win && (win.initialClass || win.initial_class || ""))
  ]
  var i
  for (i = 0; i < ids.length; i++) {
    if (ids[i] === "org.omarchy.screensaver") return true
  }
  return false
}

// Canonical CSD classes live in default/ultimate/csd-clients.json.
// Lua (hyprbars:no_bar) and this module both compile that file.
var _csdRegexes = null

function compileCsdPatterns(jsonText) {
  var out = []
  try {
    var parsed = JSON.parse(String(jsonText || "{}"))
    var list = parsed && parsed.classPatterns
    if (!list || !list.length) return out
    var i
    for (i = 0; i < list.length; i++) {
      try {
        out.push(new RegExp(String(list[i]), "i"))
      } catch (e) {
      }
    }
  } catch (e) {
  }
  return out
}

function setCsdClientsJson(jsonText) {
  _csdRegexes = compileCsdPatterns(jsonText)
  return _csdRegexes
}

function csdClassPatterns() {
  if (_csdRegexes && _csdRegexes.length) return _csdRegexes
  return []
}

function usesWaylandCsd(win) {
  var cls = windowAppId(win)
  if (!cls) return false
  var pats = csdClassPatterns()
  var i
  for (i = 0; i < pats.length; i++) {
    if (pats[i].test(cls)) return true
  }
  return false
}

function hyprbarsSnapInset(win) {
  return usesWaylandCsd(win) ? 0 : 32
}

function windowMatchesPin(win, pin) {
  var app = windowAppId(win)
  var pinId = normalizeId(pin && (pin.id || pin.desktopId))
  if (!app || !pinId) return false
  if (app === pinId || app.indexOf(pinId) !== -1 || pinId.indexOf(app) !== -1) return true
  if ((pinId === "google-chrome" || pinId === "google-chrome-stable") && (app === "chromium" || app.indexOf("chrom") === 0))
    return true
  return false
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
  var originX = Number((monitor && monitor.x) || 0)
  var originY = Number((monitor && monitor.y) || 0)
  var width = Number((monitor && monitor.width) || 0)
  var height = Number((monitor && monitor.height) || 0)
  var r = reservedLTRB(monitor && monitor.reserved)
  return {
    x: originX + r.left,
    y: originY + r.top,
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
    name: String(ipc.name || ""),
    id: ipc.id,
    x: Number(ipc.x || 0),
    y: Number(ipc.y || 0),
    width: Number(ipc.width || 0),
    height: Number(ipc.height || 0),
    reserved: ipc.reserved || [0, 0, 0, 0],
    focused: ipc.focused === true
  }
}

function pickMonitor(monitors, hint) {
  var list = monitors || []
  var i
  if (hint != null && hint !== "") {
    for (i = 0; i < list.length; i++) {
      if (!list[i]) continue
      if (String(list[i].name) === String(hint)) return list[i]
      if (String(list[i].id) === String(hint)) return list[i]
    }
  }
  for (i = 0; i < list.length; i++) {
    if (list[i] && list[i].focused) return list[i]
  }
  return list[0] || null
}

function isSpecialWorkspace(ws) {
  var name = ""
  if (ws && typeof ws === "object") name = String(ws.name || "")
  else name = String(ws || "")
  return name.indexOf("special") === 0
}

function desktopIds(workspaces) {
  var ids = []
  var i
  var id
  workspaces = workspaces || []
  for (i = 0; i < workspaces.length; i++) {
    if (!workspaces[i] || isSpecialWorkspace(workspaces[i])) continue
    id = Number(workspaces[i].id)
    if (!(id > 0)) continue
    if (ids.indexOf(id) < 0) ids.push(id)
  }
  ids.sort(function(a, b) { return a - b })
  return ids
}

function neighborDesktop(ids, current, dir) {
  var list = ids || []
  var cur = Number(current)
  var i
  for (i = 0; i < list.length; i++) {
    if (list[i] === cur) break
  }
  if (i >= list.length) i = 0
  if (dir === "l" || dir === "left" || dir === "-1")
    return i > 0 ? list[i - 1] : list[i]
  if (dir === "r" || dir === "right" || dir === "+1")
    return i < list.length - 1 ? list[i + 1] : list[i]
  return list[i] || cur
}

function nextDesktopId(ids) {
  var max = 0
  var i
  for (i = 0; i < (ids || []).length; i++) {
    if (ids[i] > max) max = ids[i]
  }
  return max + 1
}

function neighborMonitor(monitors, current, dir) {
  var list = []
  var i
  var idx = -1
  var name = current && current.name
  monitors = monitors || []
  for (i = 0; i < monitors.length; i++) {
    if (monitors[i] && monitors[i].name) list.push(monitors[i])
  }
  list.sort(function(a, b) { return Number(a.x) - Number(b.x) })
  for (i = 0; i < list.length; i++) {
    if (list[i].name === name) {
      idx = i
      break
    }
  }
  if (idx < 0) idx = 0
  if (dir === "l" || dir === "left" || dir === "-1")
    return idx > 0 ? list[idx - 1] : null
  if (dir === "r" || dir === "right" || dir === "+1")
    return idx < list.length - 1 ? list[idx + 1] : null
  return null
}

function windowsOnDesktop(windows, desktopId) {
  var id = Number(desktopId)
  var out = []
  var i
  var win
  windows = windows || []
  for (i = 0; i < windows.length; i++) {
    win = windows[i]
    if (!win || !win.address || isSpecialWorkspace(win.workspace)) continue
    if (Number(win.workspaceId) === id) out.push(win)
  }
  return out
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

function coversWorkArea(win, monitor, slop) {
  if (!win || !monitor) return false
  var area = workArea(monitor)
  if (!area.width || !area.height) return false
  var pad = slop == null ? 16 : Number(slop)
  return Math.abs(Number(win.width) - area.width) <= pad &&
    Number(win.height) >= area.height - 48 &&
    Number(win.x) <= area.x + pad &&
    Number(win.y) <= area.y + pad
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

function defaultFloatRect(monitor, options) {
  var area = workArea(monitor)
  var csd = !!(options && options.csd)
  var maxW = csd ? 1200 : 880
  var maxH = csd ? 740 : 560
  var minW = csd ? 1100 : 640
  var minH = csd ? 680 : 400
  var width = Math.min(maxW, Math.max(minW, Math.floor(area.width * (csd ? 0.64 : 0.46))))
  var height = Math.min(maxH, Math.max(minH, Math.floor(area.height * (csd ? 0.72 : 0.54))))
  if (area.width > 0 && width > area.width - 96) width = Math.max(320, area.width - 96)
  if (area.height > 0 && height > area.height - 96) height = Math.max(240, area.height - 96)
  var x = area.x + Math.max(48, Math.floor((area.width - width) / 5))
  var y = area.y + Math.max(48, Math.floor((area.height - height) / 6))
  return { x: x, y: y, width: width, height: height }
}

function cascadeRect(monitor, index, options) {
  var base = defaultFloatRect(monitor, options)
  var area = workArea(monitor)
  var step = 32
  var n = Math.max(0, Number(index) || 0)
  var x = base.x + step * (n % 12)
  var y = base.y + step * (n % 12)
  if (x + base.width > area.x + area.width) x = area.x + Math.max(24, area.width - base.width - 24)
  if (y + base.height > area.y + area.height) y = area.y + Math.max(24, area.height - base.height - 24)
  return { x: x, y: y, width: base.width, height: base.height }
}

function clampRect(rect, monitor) {
  var area = workArea(monitor)
  var width = Math.max(320, Math.min(Number(rect && rect.width) || 880, area.width))
  var height = Math.max(240, Math.min(Number(rect && rect.height) || 560, area.height))
  var x = Number(rect && rect.x)
  var y = Number(rect && rect.y)
  if (isNaN(x)) x = area.x + 48
  if (isNaN(y)) y = area.y + 48
  if (x < area.x) x = area.x
  if (y < area.y) y = area.y
  if (x + width > area.x + area.width) x = area.x + Math.max(0, area.width - width)
  if (y + height > area.y + area.height) y = area.y + Math.max(0, area.height - height)
  return { x: x, y: y, width: width, height: height, monitor: monitor && monitor.name ? String(monitor.name) : "" }
}

function parsePlacements(raw) {
  try {
    var parsed = JSON.parse(String(raw || "{}"))
    if (parsed && parsed.placements && typeof parsed.placements === "object") return parsed.placements
  } catch (e) {
  }
  return {}
}

function serializePlacements(placements) {
  return JSON.stringify({ placements: placements || {} }, null, 2) + "\n"
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
    isLockSurface: isLockSurface,
    usesWaylandCsd: usesWaylandCsd,
    hyprbarsSnapInset: hyprbarsSnapInset,
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
    pickMonitor: pickMonitor,
    isSpecialWorkspace: isSpecialWorkspace,
    desktopIds: desktopIds,
    neighborDesktop: neighborDesktop,
    nextDesktopId: nextDesktopId,
    neighborMonitor: neighborMonitor,
    windowsOnDesktop: windowsOnDesktop,
    nearRect: nearRect,
    isSnapped: isSnapped,
    coversWorkArea: coversWorkArea,
    nextSnap: nextSnap,
    aeroZone: aeroZone,
    serializeLayout: serializeLayout,
    parseLayout: parseLayout,
    captureLayout: captureLayout,
    matchLayout: matchLayout,
    defaultFloatRect: defaultFloatRect,
    cascadeRect: cascadeRect,
    clampRect: clampRect,
    parsePlacements: parsePlacements,
    serializePlacements: serializePlacements,
    compileCsdPatterns: compileCsdPatterns,
    setCsdClientsJson: setCsdClientsJson,
    csdClassPatterns: csdClassPatterns
  }
}

if (typeof require !== "undefined" && typeof __dirname !== "undefined") {
  try {
    var fs = require("fs")
    var path = require("path")
    setCsdClientsJson(fs.readFileSync(path.join(__dirname, "../../default/ultimate/csd-clients.json"), "utf8"))
  } catch (e) {
  }
}
