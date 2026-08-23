import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "WindowModel.js" as WindowModel

// WindowService: the typed window-management capability behind the Ultimate
// taskbar, Start, caption chrome, and every window affordance
// (docs/settings-service-api.md). UI never runs hyprctl and never assembles
// shell strings; it calls these intent-named verbs. Dispatchers go through
// Hyprland.dispatch (Quickshell's Hyprland socket), not bash -c.
//
// Hyprland 0.55+ parses `dispatch …` as Lua (`hl.dispatch(…)`). Classic token
// dispatchers (`fullscreen 2`, movewindowpixel, resizeactive) fail on that
// parser. Verbs below send `hl.dsp.window.*` forms, always naming
// `window = "address:…"`.
// Minimize is CWindow::setHidden on the same workspace via the
// omarchy-minimize plugin (`hl.plugin.omarchy_minimize.*`).
QtObject {
  id: root

  property string lastError: ""
  property var _minimized: ({})
  property var _normalBounds: ({})
  // Last snap/max verb this service applied. Hyprland.refreshToplevels() does
  // not wait for lastIpcObject, and hyprctl -j clients is a 400ms poll, so Aero
  // drag-away cannot trust those boxes right after maximize().
  property var _placedKind: ({})
  property bool _desktopShown: false
  property var _batch: []
  property var savedLayout: ({ windows: [] })
  property bool cycling: false
  property int cycleIndex: 0
  property var cycleList: []
  property var pins: []
  property var shippedPins: []
  property bool userPinsMissing: false
  property string home: Quickshell.env("HOME")
  property var monitorIpc: ({})
  property var monitorsIpc: []
  property var workspacesIpc: []
  property int activeDesktopId: 1
  property var clientsIpc: []

  readonly property var windows: {
    var values = Hyprland.toplevels.values
    var out = []
    var i
    for (i = 0; i < values.length; i++) {
      var hypr = values[i]
      if (hypr)
        hypr.lastIpcObject
      var rec = root._windowRecord(hypr)
      if (rec && rec.address) {
        if (WindowModel.isSpecialWorkspace(rec.workspace)) continue
        out.push(rec)
      }
    }
    return out
  }
  readonly property var desktopWindows: WindowModel.windowsOnDesktop(root.windows, root.activeDesktopId)
  readonly property var desktopIds: WindowModel.desktopIds(root.workspacesIpc)
  readonly property var groups: WindowModel.buildGroups(root.desktopWindows, root.pins)
  readonly property string pinsPath: root.home + "/.local/state/omarchy/ultimate/taskbar-pins.json"
  readonly property string layoutPath: root.home + "/.local/state/omarchy/ultimate/window-layout.json"
  readonly property string shippedPinsPath: Quickshell.env("OMARCHY_PATH") + "/default/ultimate/taskbar-pins.json"

  function _applyShippedPinsIfNeeded() {
    if (root.userPinsMissing && root.pins.length === 0 && root.shippedPins.length > 0)
      root.pins = root.shippedPins
  }

  function _dispatchLua(expr, refresh) {
    Hyprland.dispatch(expr)
    if (refresh) Hyprland.refreshToplevels()
  }

  function _addr(address) {
    var target = String(address || "")
    if (target === "" || target === "active") return root._activeAddress()
    return root._canonAddr(target)
  }

  function _luaWindow(address) {
    return 'window = "address:' + String(address || "") + '"'
  }

  function _canonAddr(addr) {
    var s = String(addr || "")
    if (s === "") return ""
    if (s.indexOf("0x") === 0 || s.indexOf("0X") === 0) return s
    if (/^[0-9a-fA-F]+$/.test(s)) return "0x" + s
    return s
  }

  function _hyprlandToplevels() {
    if (Hyprland.toplevels && Hyprland.toplevels.values) return Hyprland.toplevels.values
    return []
  }

  function _windowRecord(hypr) {
    if (!hypr) return null
    var ipc = hypr.lastIpcObject || {}
    var ws = hypr.workspace
    var wsName = ws ? String(ws.name || "") : String((ipc.workspace && ipc.workspace.name) || "")
    var wsId = ws ? ws.id : (ipc.workspace && ipc.workspace.id)
    var cls = String(ipc.class || hypr.appId || "")
    var mon = hypr.monitor
    var address = root._canonAddr(hypr.address || ipc.address)
    var client = root._clientIpc(address)
    var at = ipc.at || (client && client.at) || [0, 0]
    var size = ipc.size || (client && client.size) || [0, 0]
    var hidden = (client && client.hidden === true) || ipc.hidden === true
    var fullscreen = 0
    if (ipc.fullscreen != null && ipc.fullscreen !== "")
      fullscreen = Number(ipc.fullscreen)
    else if (client && client.fullscreen != null)
      fullscreen = Number(client.fullscreen)
    return {
      address: address,
      title: String(hypr.title || ipc.title || ""),
      appId: cls,
      class: cls,
      x: Number(at[0] || 0),
      y: Number(at[1] || 0),
      width: Number(size[0] || 0),
      height: Number(size[1] || 0),
      mapped: ipc.mapped !== false,
      floating: ipc.floating === true,
      fullscreen: fullscreen,
      workspace: wsName,
      workspaceId: wsId,
      minimized: hidden,
      monitorName: mon ? String(mon.name || "") : "",
      xwayland: ipc.xwayland === true,
      modal: ipc.modal === true || String(ipc.contentType || "") === "dialog" || String(ipc.xdgTag || "").indexOf("dialog") >= 0
    }
  }

  function _record(address) {
    var target = root._canonAddr(address)
    if (!target) return null
    var recs = root.windows
    for (var i = 0; i < recs.length; i++) {
      if (recs[i] && recs[i].address === target) return recs[i]
    }
    return null
  }

  function _forAddress(address) {
    var target = root._canonAddr(address)
    var hypr = root._hyprlandToplevels()
    for (var i = 0; i < hypr.length; i++) {
      if (hypr[i] && root._canonAddr(hypr[i].address) === target) return hypr[i]
    }
    return null
  }

  function _activeAddress() {
    var hypr = root._hyprlandToplevels()
    for (var i = 0; i < hypr.length; i++) {
      if (hypr[i] && hypr[i].activated && hypr[i].address)
        return root._canonAddr(hypr[i].address)
    }
    return ""
  }

  function _addresses() {
    var recs = root.windows
    var list = []
    for (var i = 0; i < recs.length; i++) {
      if (recs[i] && recs[i].address) list.push(recs[i].address)
    }
    return list
  }

  function windowTitle(address) {
    var rec = root._record(address)
    return rec ? rec.title : String(address || "")
  }

  function _markMinimized(address, parked) {
    var next = ({})
    for (var key in root._minimized) next[key] = root._minimized[key]
    if (parked) next[address] = true
    else delete next[address]
    root._minimized = next
  }

  function _monitorGeom(address) {
    var hint = ""
    if (address) {
      var rec = root._record(root._addr(address))
      var client = root._clientIpc(root._addr(address))
      if (rec && rec.monitorName) hint = rec.monitorName
      else if (client && client.monitor != null) hint = client.monitor
    }
    var picked = WindowModel.pickMonitor(root.monitorsIpc, hint)
    if (!picked) picked = root.monitorIpc
    if (picked && picked.width && picked.reserved)
      return WindowModel.compositorMonitor(picked)
    root.lastError = "compositor monitor geometry is unavailable"
    return { width: 0, height: 0, reserved: [0, 0, 0, 0], x: 0, y: 0 }
  }

  function _copyMap(src) {
    var next = ({})
    for (var key in src) next[key] = src[key]
    return next
  }

  function _setPlacedKind(address, kind) {
    var target = root._canonAddr(address)
    if (!target) return
    var next = root._copyMap(root._placedKind)
    var k = String(kind || "")
    if (k === "" || k === "float" || k === "normal") delete next[target]
    else next[target] = k
    root._placedKind = next
  }

  function _isPlacedSnap(kind) {
    return kind === "l" || kind === "r" || kind === "tl" || kind === "tr" || kind === "bl" || kind === "br"
  }

  function _clientIpc(address) {
    var target = root._canonAddr(address)
    if (!target) return null
    var list = root.clientsIpc || []
    var i
    for (i = 0; i < list.length; i++) {
      if (root._canonAddr(list[i].address) === target) return list[i]
    }
    return null
  }

  function _clientRect(address) {
    var ipc = root._clientIpc(address)
    if (!ipc || !ipc.at || !ipc.size || Number(ipc.size[0]) <= 0 || Number(ipc.size[1]) <= 0) {
      root.lastError = "compositor client geometry is unavailable"
      return null
    }
    return {
      x: Number(ipc.at[0] || 0),
      y: Number(ipc.at[1] || 0),
      width: Number(ipc.size[0]),
      height: Number(ipc.size[1]),
      fullscreen: Number(ipc.fullscreen || 0),
      minimized: ipc.hidden === true
    }
  }

  function _rememberNormal(address) {
    var rec = root._clientRect(address)
    if (!rec || rec.fullscreen || rec.minimized) return
    var geom = root._monitorGeom(address)
    if (geom.width && WindowModel.isSnapped(rec, geom, 8, 32)) return
    var next = root._copyMap(root._normalBounds)
    next[address] = { x: rec.x, y: rec.y, width: rec.width, height: rec.height }
    root._normalBounds = next
  }

  function _workArea() {
    return WindowModel.workArea(root._monitorGeom())
  }

  function _persistPins() {
    root.pinFile.setText(WindowModel.serializePins(root.pins))
  }

  function pin(entry) {
    root.pins = WindowModel.withPin(root.pins, entry || {})
    root._persistPins()
  }

  function unpin(desktopId) {
    root.pins = WindowModel.withoutPin(root.pins, desktopId)
    root._persistPins()
  }

  function togglePin(group) {
    if (!group) return
    if (group.pinned) root.unpin(group.desktopId || group.id)
    else root.pin(group)
  }

  function focus(address) {
    var target = root._addr(address)
    if (!target) return
    root._dispatchLua("hl.dsp.focus({ " + root._luaWindow(target) + " })")
  }

  function close(address) {
    var target = root._addr(address)
    if (!target) return
    root._dispatchLua("hl.dsp.window.close({ " + root._luaWindow(target) + " })", true)
  }

  function closeActive() {
    var address = root._activeAddress()
    if (address) root.close(address)
  }

  function minimize(address) {
    var target = root._addr(address)
    if (!target) return
    root._markMinimized(target, true)
    root._dispatchLua("hl.plugin.omarchy_minimize.minimize({ " + root._luaWindow(target) + " })", true)
  }

  function restore(address) {
    var target = root._addr(address)
    if (!target) return
    root._dispatchLua("hl.plugin.omarchy_minimize.restore({ " + root._luaWindow(target) + " })", true)
    root._markMinimized(target, false)
  }

  function isActive(address) {
    var target = root._canonAddr(address)
    return target !== "" && target === root._activeAddress()
  }

  function isMaximized(address) {
    var target = root._addr(address)
    if (root._placedKind[target] === "max") return true
    // hyprctl -j clients is polled; after a maximize dispatcher it can still
    // hold the previous float. Hyprland.refreshToplevels() does not wait for
    // lastIpcObject. Prefer the verb we just ran, then compositor bits.
    var live = root._record(target)
    var ipc = root._clientRect(target)
    if (live && Number(live.fullscreen) === 1) return true
    if (ipc && Number(ipc.fullscreen) === 1) return true
    var rec = ipc || live
    var geom = root._monitorGeom(address)
    if (!rec || !geom.width) return false
    var area = WindowModel.workArea(geom)
    return Math.abs(Number(rec.width) - area.width) <= 16 && Number(rec.height) >= area.height - 48
  }

  function isMinimized(address) {
    var rec = root._record(root._addr(address))
    return !!(rec && rec.minimized)
  }

  function toggleFromTaskbar(address) {
    if (root.isActive(address)) root.minimize(address)
    else root.activate(address)
  }

  // Alt+Tab and taskbar activation: unhide if needed, then focus. restore()
  // alone is a no-op for a visible window and is undone if the switcher overlay
  // unmaps and returns keyboard focus to the previous client.
  function activate(address) {
    var target = root._addr(address)
    if (!target) return
    var rec = root._record(target)
    if (rec && rec.minimized) root.restore(target)
    root._dispatchLua("hl.dsp.window.bring_to_top({ " + root._luaWindow(target) + " })")
    root.focus(target)
  }

  function maximize(address) {
    var target = root._addr(address)
    if (!target) return
    root._rememberNormal(target)
    root._setPlacedKind(target, "max")
    root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"set\", " + root._luaWindow(target) + " })", true)
  }

  function unmaximize(address) {
    var target = root._addr(address)
    if (!target) return
    if (root._placedKind[target] === "max") root._setPlacedKind(target, "float")
    root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"unset\", " + root._luaWindow(target) + " })", true)
  }

  function toggleMaximize(address) {
    var target = root._addr(address)
    if (!target) return
    if (root.isMaximized(target)) root.unmaximize(target)
    else root.maximize(target)
  }

  function restoreOrMinimize(address) {
    root.snapArrow(address, "d")
  }

  function restoreNormal(address) {
    var target = root._addr(address)
    if (!target) return
    root._setPlacedKind(target, "float")
    var bounds = root._normalBounds[target]
    if (!bounds) bounds = WindowModel.defaultFloatRect(root._monitorGeom(target))
    root._applyRect(target, bounds)
  }

  function _applyRect(target, bounds) {
    if (!target || !bounds || !bounds.width || !bounds.height) return
    var win = root._luaWindow(target)
    root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"unset\", layout_aware = false, " + win + " })")
    root.unmaximize(target)
    root._dispatchLua("hl.dsp.window.float({ action = \"enable\", " + win + " })")
    root._dispatchLua("hl.dsp.window.resize({ x = " + Math.round(Number(bounds.width)) + ", y = " + Math.round(Number(bounds.height)) + ", relative = false, " + win + " })")
    root._dispatchLua("hl.dsp.window.move({ x = " + Math.round(Number(bounds.x)) + ", y = " + Math.round(Number(bounds.y)) + ", relative = false, " + win + " })", true)
  }

  function moveTo(address, x, y) {
    var target = root._addr(address)
    if (!target) return
    root._dispatchLua("hl.dsp.window.move({ x = " + Math.round(Number(x)) + ", y = " + Math.round(Number(y)) + ", relative = false, " + root._luaWindow(target) + " })")
  }

  function resizeTo(address, w, h) {
    var target = root._addr(address)
    if (!target) return
    root._dispatchLua("hl.dsp.window.resize({ x = " + Math.round(Number(w)) + ", y = " + Math.round(Number(h)) + ", relative = false, " + root._luaWindow(target) + " })")
  }

  function snapLeft(address) {
    root.snapTo(address, "l")
  }

  function snapRight(address) {
    root.snapTo(address, "r")
  }

  function snapTo(address, side) {
    root._applySnapKind(root._addr(address), String(side || ""))
  }

  function snapArrow(address, dir) {
    var target = root._addr(address)
    if (!target) return
    var kind = "float"
    if (root.isMaximized(target)) kind = "max"
    else {
      var rec = root._clientRect(target) || root._record(target)
      var geom = root._monitorGeom(target)
      if (rec && geom.width) kind = WindowModel.snapKind(rec, geom, 8, 32)
    }
    root._applySnapKind(target, WindowModel.nextSnap(kind, dir))
  }

  function aeroDragEnd(address, x, y) {
    var target = root._addr(address)
    if (!target) return
    Hyprland.refreshToplevels()
    var geom = root._monitorGeom(target)
    if (!geom.width) return
    var px = Number(x)
    var py = Number(y)
    if (x === undefined || y === undefined || x === "" || y === "" || isNaN(px) || isNaN(py)) {
      root.lastError = "aeroDragEnd needs cursor coordinates"
      return
    }
    var zone = WindowModel.aeroZone({ x: px, y: py }, geom)
    if (zone) {
      root._applySnapKind(target, zone)
      return
    }
    // Interior drop. lastIpcObject and the clients poll can still show the
    // pre-max float after maximize(), so isMaximized/isSnapped on those boxes
    // are a no-op. Trust the last verb; if that is also empty, unset
    // compositor maximize (no-op when the window is already normal).
    var placed = root._placedKind[target]
    var rec = root._clientRect(target) || root._record(target)
    if (placed === "max" || placed === "full" || root._isPlacedSnap(placed) || (rec && WindowModel.isSnapped(rec, geom, 8, 32))) {
      root.restoreNormal(target)
      return
    }
    root.unmaximize(target)
  }

  function saveLayout() {
    Hyprland.refreshToplevels()
    var recs = []
    var list = root._addresses()
    var i
    var rec
    var rect
    var geom
    var captured
    for (i = 0; i < list.length; i++) {
      rec = root._record(list[i]) || {}
      rect = root._clientRect(list[i]) || rec
      geom = root._monitorGeom(list[i])
      captured = WindowModel.captureLayout([{
        address: list[i],
        appId: rec.appId || rec.class || "",
        title: rec.title || "",
        fullscreen: Number(rect.fullscreen || rec.fullscreen || 0),
        minimized: !!(rect.minimized || rec.minimized),
        x: Number(rect.x || 0),
        y: Number(rect.y || 0),
        width: Number(rect.width || 0),
        height: Number(rect.height || 0)
      }], geom, 32)
      if (captured.windows && captured.windows[0]) recs.push(captured.windows[0])
    }
    root.savedLayout = { windows: recs }
    root.layoutFile.setText(WindowModel.serializeLayout(root.savedLayout))
  }

  function restoreLayout() {
    var matches = WindowModel.matchLayout(root.windows, root.savedLayout)
    var i
    var entry
    for (i = 0; i < matches.length; i++) {
      entry = matches[i]
      if (entry.kind === "float") root._applyRect(entry.address, entry)
      else root._applySnapKind(entry.address, entry.kind)
    }
  }

  function _applySnapKind(target, kind) {
    if (!target) return
    kind = String(kind || "")
    if (kind === "min") {
      root.minimize(target)
      return
    }
    if (kind === "normal") {
      root.restoreNormal(target)
      return
    }
    if (kind === "max") {
      root.maximize(target)
      return
    }
    if (kind === "l" || kind === "r" || kind === "tl" || kind === "tr" || kind === "bl" || kind === "br") {
      root._snap(target, kind)
    }
  }

  function _snap(target, direction) {
    if (!target) return
    var geom = root._monitorGeom(target)
    if (!geom.width || !geom.height) return
    if (root.isMaximized(target)) root.unmaximize(target)
    root._rememberNormal(target)
    // hyprbars draws above hyprctl's client box even with bar_part_of_window.
    // Inset the client top by bar_height (32, matching desktop-windows.lua) so
    // the title bar stays in the work area instead of clipping off-screen.
    var rect = WindowModel.snapRect(geom, direction, 32)
    var win = root._luaWindow(target)
    root._setPlacedKind(target, direction)
    root._dispatchLua("hl.dsp.window.float({ action = \"enable\", " + win + " })")
    root._dispatchLua("hl.dsp.window.resize({ x = " + rect.width + ", y = " + rect.height + ", relative = false, " + win + " })")
    root._dispatchLua("hl.dsp.window.move({ x = " + rect.x + ", y = " + rect.y + ", relative = false, " + win + " })", true)
  }

  function toggleShowDesktop() {
    if (root._desktopShown) {
      for (var i = 0; i < root._batch.length; i++) root.restore(root._batch[i])
      root._batch = []
    } else {
      var batch = root._addressesOnDesktop(root.activeDesktopId)
      for (var j = 0; j < batch.length; j++) root.minimize(batch[j])
      root._batch = batch
    }
    root._desktopShown = !root._desktopShown
  }

  function _addressesOnDesktop(desktopId) {
    var wins = WindowModel.windowsOnDesktop(root.windows, desktopId)
    var list = []
    var i
    for (i = 0; i < wins.length; i++) list.push(wins[i].address)
    return list
  }

  function cycleNext() {
    var list = root._addressesOnDesktop(root.activeDesktopId)
    if (list.length === 0) return
    if (!root.cycling) {
      root.cycleList = list
      root.cycling = true
      var current = root._activeAddress()
      var idx = list.indexOf(current)
      root.cycleIndex = idx < 0 ? 0 : (idx + 1) % list.length
    } else {
      root.cycleIndex = (root.cycleIndex + 1) % list.length
      root.cycleList = list
    }
  }

  function cyclePrev() {
    var list = root._addressesOnDesktop(root.activeDesktopId)
    if (list.length === 0) return
    if (!root.cycling) {
      root.cycleList = list
      root.cycling = true
      var current = root._activeAddress()
      var idx = list.indexOf(current)
      root.cycleIndex = idx < 0 ? 0 : (idx - 1 + list.length) % list.length
    } else {
      root.cycleIndex = (root.cycleIndex - 1 + list.length) % list.length
      root.cycleList = list
    }
  }

  function commitCycle() {
    if (!root.cycling) return
    var address = root.cycleList[root.cycleIndex]
    root.cancelCycle()
    if (address) root.activate(address)
  }

  function cancelCycle() {
    root.cycling = false
    root.cycleList = []
  }

  function activateFromSwitcher(address) {
    var target = root._canonAddr(address)
    root.cancelCycle()
    if (target) root.activate(target)
  }

  function isFullscreen(address) {
    var target = root._addr(address)
    if (root._placedKind[target] === "full") return true
    var rec = root._clientRect(target) || root._record(target)
    return !!(rec && Number(rec.fullscreen) === 2)
  }

  function toggleFullscreen(address) {
    var target = root._addr(address)
    if (!target) return
    // action=toggle is a no-op through hyprctl eval and is racy through
    // Quickshell when lastIpcObject still says 2 after restoreNormal. Set and
    // unset are explicit. layout_aware=false is default compositor fullscreen,
    // not a layout handler that can swallow F11 on overlapping floats.
    if (root.isFullscreen(target)) {
      root._setPlacedKind(target, "float")
      root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"unset\", layout_aware = false, " + root._luaWindow(target) + " })", true)
      return
    }
    root._rememberNormal(target)
    root._setPlacedKind(target, "full")
    root.focus(target)
    root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"set\", layout_aware = false, " + root._luaWindow(target) + " })", true)
  }

  function createDesktop() {
    var next = WindowModel.nextDesktopId(WindowModel.desktopIds(root.workspacesIpc))
    var list = (root.workspacesIpc || []).slice()
    list.push({ id: next, name: String(next) })
    root.workspacesIpc = list
    root.activeDesktopId = next
    root._dispatchLua('hl.dsp.focus({ workspace = "' + next + '" })', true)
  }

  function switchDesktop(dir) {
    var dest = WindowModel.neighborDesktop(WindowModel.desktopIds(root.workspacesIpc), root.activeDesktopId, dir)
    if (!dest || dest === root.activeDesktopId) return
    root.switchToDesktop(dest)
  }

  function switchToDesktop(id) {
    var dest = Number(id)
    if (!(dest > 0)) return
    root._dispatchLua('hl.dsp.focus({ workspace = "' + dest + '" })', true)
  }

  function moveToDesktop(address, desktopId) {
    var target = root._addr(address)
    var dest = Number(desktopId)
    if (!target || !(dest > 0)) return
    root._dispatchLua('hl.dsp.window.move({ workspace = "' + dest + '", follow = false, ' + root._luaWindow(target) + " })", true)
  }

  function closeDesktop() {
    var ids = WindowModel.desktopIds(root.workspacesIpc)
    var cur = root.activeDesktopId
    if (ids.length <= 1) return
    var dest = WindowModel.neighborDesktop(ids, cur, "l")
    if (dest === cur) dest = WindowModel.neighborDesktop(ids, cur, "r")
    if (!dest || dest === cur) return
    var wins = root._addressesOnDesktop(cur)
    var i
    for (i = 0; i < wins.length; i++) root.moveToDesktop(wins[i], dest)
    root._dispatchLua('hl.dsp.focus({ workspace = "' + dest + '" })', true)
  }

  function moveToMonitor(address, dir) {
    var target = root._addr(address)
    if (!target) return
    var rec = root._record(target)
    var client = root._clientIpc(target)
    var hint = ""
    if (rec && rec.monitorName) hint = rec.monitorName
    else if (client && client.monitor != null) hint = client.monitor
    var current = WindowModel.pickMonitor(root.monitorsIpc, hint)
    var dest = WindowModel.neighborMonitor(root.monitorsIpc, current, dir)
    if (!dest || !dest.name) {
      root.lastError = "no neighboring monitor"
      return
    }
    root._dispatchLua('hl.dsp.window.move({ monitor = "' + dest.name + '", ' + root._luaWindow(target) + " })", true)
  }

  property Process ensurePinsDir: Process {
    command: ["bash", "-c", "mkdir -p \"$0\"", root.home + "/.local/state/omarchy/ultimate"]
    running: true
  }

  property Process monitorReader: Process {
    command: ["hyprctl", "-j", "monitors"]
    running: true
    stdout: StdioCollector {
      id: monitorStdout
      waitForEnd: true
    }
    onExited: {
      try {
        var list = JSON.parse(monitorStdout.text || "[]")
        var picked = null
        var i
        for (i = 0; i < list.length; i++) {
          if (list[i] && list[i].focused) picked = list[i]
        }
        if (!picked && list.length) picked = list[0]
        if (picked && picked.width && picked.reserved) root.monitorIpc = picked
        if (Array.isArray(list)) root.monitorsIpc = list
      } catch (e) {
        root.lastError = "compositor monitor geometry is unavailable"
      }
      monitorRestart.restart()
    }
  }

  property Timer monitorRestart: Timer {
    interval: 400
    onTriggered: root.monitorReader.running = true
  }

  property Process clientsReader: Process {
    command: ["hyprctl", "-j", "clients"]
    running: true
    stdout: StdioCollector {
      id: clientsStdout
      waitForEnd: true
    }
    onExited: {
      try {
        var list = JSON.parse(clientsStdout.text || "[]")
        if (Array.isArray(list)) root.clientsIpc = list
      } catch (e) {
      }
      clientsRestart.restart()
    }
  }

  property Timer clientsRestart: Timer {
    interval: 400
    onTriggered: root.clientsReader.running = true
  }

  property Process workspaceReader: Process {
    command: ["hyprctl", "-j", "workspaces"]
    running: true
    stdout: StdioCollector {
      id: workspaceStdout
      waitForEnd: true
    }
    onExited: {
      try {
        var list = JSON.parse(workspaceStdout.text || "[]")
        if (Array.isArray(list)) root.workspacesIpc = list
      } catch (e) {
      }
      workspaceRestart.restart()
    }
  }

  property Timer workspaceRestart: Timer {
    interval: 400
    onTriggered: root.workspaceReader.running = true
  }

  property Process activeDesktopReader: Process {
    command: ["hyprctl", "-j", "activeworkspace"]
    running: true
    stdout: StdioCollector {
      id: activeDesktopStdout
      waitForEnd: true
    }
    onExited: {
      try {
        var ws = JSON.parse(activeDesktopStdout.text || "{}")
        var id = Number(ws && ws.id)
        if (id > 0) root.activeDesktopId = id
      } catch (e) {
      }
      activeDesktopRestart.restart()
    }
  }

  property Timer activeDesktopRestart: Timer {
    interval: 400
    onTriggered: root.activeDesktopReader.running = true
  }

  property FileView layoutFile: FileView {
    path: root.layoutPath
    watchChanges: true
    printErrors: false
    onLoaded: root.savedLayout = WindowModel.parseLayout(text())
    onLoadFailed: root.savedLayout = { windows: [] }
    onFileChanged: reload()
  }

  property FileView pinFile: FileView {
    path: root.pinsPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.userPinsMissing = false
      root.pins = WindowModel.parsePins(text())
    }
    onLoadFailed: {
      root.userPinsMissing = true
      root._applyShippedPinsIfNeeded()
    }
    onFileChanged: reload()
  }

  property FileView shippedPinFile: FileView {
    path: root.shippedPinsPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.shippedPins = WindowModel.parsePins(text())
      root._applyShippedPinsIfNeeded()
    }
    onLoadFailed: root.shippedPins = []
    onFileChanged: reload()
  }
}
