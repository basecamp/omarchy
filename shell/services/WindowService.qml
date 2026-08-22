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
QtObject {
  id: root

  property string lastError: ""
  property var _minimized: ({})
  property bool _desktopShown: false
  property var _batch: []
  property bool cycling: false
  property int cycleIndex: 0
  property var cycleList: []
  property var pins: []
  property string home: Quickshell.env("HOME")
  readonly property int captionHeight: 28

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
    return {
      address: root._canonAddr(hypr.address || ipc.address),
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
      minimized: wsName === "special:minimized",
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
    var mon = Hyprland.focusedMonitor
    if (!mon) return { width: 0, height: 0, reserved: [] }
    Hyprland.refreshMonitors()
    var ipc = mon.lastIpcObject || {}
    return {
      width: Number(mon.width || ipc.width || 0),
      height: Number(mon.height || ipc.height || 0),
      reserved: ipc.reserved
    }
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
    root._dispatchLua("hl.dsp.window.move({ workspace = \"special:minimized\", follow = false, " + root._luaWindow(target) + " })", true)
  }

  function restore(address) {
    var target = root._addr(address)
    if (!target) return
    var ws = Hyprland.focusedWorkspace
    var id = ws ? String(ws.id) : "1"
    root._dispatchLua("hl.dsp.window.move({ workspace = \"" + id + "\", follow = true, " + root._luaWindow(target) + " })", true)
    root._markMinimized(target, false)
  }

  function isActive(address) {
    var target = root._canonAddr(address)
    return target !== "" && target === root._activeAddress()
  }

  function isMaximized(address) {
    var hypr = root._forAddress(root._addr(address))
    if (!hypr) return false
    var ipc = hypr.lastIpcObject || {}
    return Number(ipc.fullscreen || 0) === 1
  }

  function toggleFromTaskbar(address) {
    if (root.isActive(address)) root.minimize(address)
    else root.restore(address)
  }

  function maximize(address) {
    var target = root._addr(address)
    if (!target) return
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
    if (root.isMaximized(target)) root.unmaximize(target)
    else root.minimize(target)
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
    var rect = WindowModel.snapRect(geom, direction)
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
    root.cycling = false
    root.cycleList = []
    if (address) root.restore(address)
  }

  function activateFromSwitcher(address) {
    var target = root._canonAddr(address)
    root.cycling = false
    root.cycleList = []
    if (target) root.restore(target)
  }

  property Process ensurePinsDir: Process {
    command: ["bash", "-c", "mkdir -p \"$0\"", root.home + "/.local/state/omarchy/ultimate"]
    running: true
  }

  property FileView pinFile: FileView {
    path: root.pinsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.pins = WindowModel.parsePins(text())
    onLoadFailed: root.pins = []
    onFileChanged: reload()
  }
}
