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
  property bool _desktopShown: false
  property var _batch: []
  property bool cycling: false
  property int cycleIndex: 0
  property var cycleList: []
  property var pins: []
  property var shippedPins: []
  property bool userPinsMissing: false
  property string home: Quickshell.env("HOME")
  property var monitorIpc: ({})
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
      if (rec && rec.address) out.push(rec)
    }
    return out
  }
  readonly property var groups: WindowModel.buildGroups(root.windows, root.pins)
  readonly property string pinsPath: root.home + "/.local/state/omarchy/ultimate/taskbar-pins.json"
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
    var at = ipc.at || [0, 0]
    var size = ipc.size || [0, 0]
    var ws = hypr.workspace
    var wsName = ws ? String(ws.name || "") : String((ipc.workspace && ipc.workspace.name) || "")
    var wsId = ws ? ws.id : (ipc.workspace && ipc.workspace.id)
    var cls = String(ipc.class || hypr.appId || "")
    var mon = hypr.monitor
    var address = root._canonAddr(hypr.address || ipc.address)
    var client = root._clientIpc(address)
    var hidden = (client && client.hidden === true) || ipc.hidden === true
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
      fullscreen: Number(ipc.fullscreen || 0),
      workspace: wsName,
      workspaceId: wsId,
      minimized: hidden,
      monitorName: mon ? String(mon.name || "") : ""
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

  function _monitorGeom() {
    var ipc = root.monitorIpc
    if (ipc && ipc.width && ipc.height && ipc.reserved)
      return WindowModel.compositorMonitor(ipc)
    root.lastError = "compositor monitor geometry is unavailable"
    return { width: 0, height: 0, reserved: [0, 0, 0, 0] }
  }

  function _copyMap(src) {
    var next = ({})
    for (var key in src) next[key] = src[key]
    return next
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
    var geom = root._monitorGeom()
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
    var rec = root._clientRect(root._addr(address))
    return !!(rec && rec.fullscreen === 1)
  }

  function toggleFromTaskbar(address) {
    if (root.isActive(address)) root.minimize(address)
    else root.restore(address)
  }

  function maximize(address) {
    var target = root._addr(address)
    if (!target) return
    root._rememberNormal(target)
    root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"set\", " + root._luaWindow(target) + " })", true)
  }

  function unmaximize(address) {
    var target = root._addr(address)
    if (!target) return
    root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"unset\", " + root._luaWindow(target) + " })", true)
  }

  function toggleMaximize(address) {
    var target = root._addr(address)
    if (!target) return
    if (root.isMaximized(target)) root.unmaximize(target)
    else root.maximize(target)
  }

  function restoreOrMinimize(address) {
    var target = root._addr(address)
    if (!target) return
    if (root.isMaximized(target)) {
      root.unmaximize(target)
      return
    }
    var rec = root._clientRect(target)
    var geom = root._monitorGeom()
    if (rec && geom.width && WindowModel.isSnapped(rec, geom, 8, 32)) {
      root.restoreNormal(target)
      return
    }
    root.minimize(target)
  }

  function restoreNormal(address) {
    var target = root._addr(address)
    if (!target) return
    if (root.isMaximized(target)) root.unmaximize(target)
    var bounds = root._normalBounds[target]
    if (!bounds) bounds = WindowModel.defaultFloatRect(root._monitorGeom())
    if (!bounds.width || !bounds.height) return
    var win = root._luaWindow(target)
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
    root._snap(root._addr(address), "l")
  }

  function snapRight(address) {
    root._snap(root._addr(address), "r")
  }

  function _snap(target, direction) {
    if (!target) return
    var geom = root._monitorGeom()
    if (!geom.width || !geom.height) return
    root._rememberNormal(target)
    // hyprbars draws above hyprctl's client box even with bar_part_of_window.
    // Inset the client top by bar_height (32, matching desktop-windows.lua) so
    // the title bar stays in the work area instead of clipping off-screen.
    var rect = WindowModel.snapRect(geom, direction, 32)
    var win = root._luaWindow(target)
    root._dispatchLua("hl.dsp.window.float({ action = \"enable\", " + win + " })")
    root._dispatchLua("hl.dsp.window.resize({ x = " + rect.width + ", y = " + rect.height + ", relative = false, " + win + " })")
    root._dispatchLua("hl.dsp.window.move({ x = " + rect.x + ", y = " + rect.y + ", relative = false, " + win + " })", true)
  }

  function toggleShowDesktop() {
    if (root._desktopShown) {
      for (var i = 0; i < root._batch.length; i++) root.restore(root._batch[i])
      root._batch = []
    } else {
      var batch = root._addresses()
      for (var j = 0; j < batch.length; j++) root.minimize(batch[j])
      root._batch = batch
    }
    root._desktopShown = !root._desktopShown
  }

  function cycleNext() {
    var list = root._addresses()
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
    var list = root._addresses()
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
    if (address) root.restore(address)
  }

  function cancelCycle() {
    root.cycling = false
    root.cycleList = []
  }

  function activateFromSwitcher(address) {
    var target = root._canonAddr(address)
    root.cancelCycle()
    if (target) root.restore(target)
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
