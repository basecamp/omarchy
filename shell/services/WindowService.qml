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
  property var capabilityBroker: null
  property string _actor: "ui"
  property var placements: ({})
  property var _knownAddresses: ({})
  property var _lastRect: ({})
  property var _lastAppId: ({})
  property int _cascadeIndex: 0
  property bool _placementsReady: false
  property bool _placingRect: false
  property string _pendingFloatRestore: ""
  property Timer restoreFloatTimer: Timer {
    interval: 32
    repeat: false
    onTriggered: {
      var addr = root._pendingFloatRestore
      if (addr) root._restoreFloatOnScreen(addr)
    }
  }
  property Timer restoreFloatRetryTimer: Timer {
    interval: 220
    repeat: false
    onTriggered: {
      var addr = root._pendingFloatRestore
      root._pendingFloatRestore = ""
      if (addr) root._restoreFloatOnScreen(addr)
    }
  }
  property var monitorIpc: ({})
  property var monitorsIpc: []
  property var workspacesIpc: []
  property int activeDesktopId: 1
  property var clientsIpc: []
  property Timer placeNewClientsTimer: Timer {
    interval: 280
    repeat: false
    onTriggered: root._placeNewClients()
  }
  property Timer activateAtCursorTimer: Timer {
    interval: 48
    repeat: false
    onTriggered: root.activateAtCursor()
  }

  readonly property var windows: {
    var values = Hyprland.toplevels.values
    var out = []
    var seen = ({})
    var i
    var rec
    var addr
    var c
    for (i = 0; i < values.length; i++) {
      var hypr = values[i]
      if (hypr)
        hypr.lastIpcObject
      rec = root._windowRecord(hypr)
      if (rec && rec.address) {
        if (WindowModel.isSpecialWorkspace(rec.workspace)) continue
        if (root._minimized[rec.address]) rec.minimized = true
        out.push(rec)
        seen[rec.address] = true
      }
    }
    // setHidden windows can drop out of Hyprland.toplevels while hyprctl
    // clients still lists them. Keep those buttons on the taskbar.
    var clients = root.clientsIpc || []
    for (i = 0; i < clients.length; i++) {
      c = clients[i]
      if (!c || !c.address) continue
      addr = root._canonAddr(c.address)
      if (!addr || seen[addr]) continue
      if (c.hidden !== true && !root._minimized[addr]) continue
      rec = root._recordFromClient(c)
      if (!rec || !rec.address) continue
      if (WindowModel.isSpecialWorkspace(rec.workspace)) continue
      out.push(rec)
      seen[addr] = true
    }
    return out
  }
  readonly property var desktopWindows: WindowModel.windowsOnDesktop(root.windows, root.activeDesktopId)
  readonly property var desktopIds: WindowModel.desktopIds(root.workspacesIpc)
  readonly property var groups: WindowModel.buildGroups(root.desktopWindows, root.pins)
  readonly property string pinsPath: root.home + "/.local/state/omarchy/ultimate/taskbar-pins.json"
  readonly property string layoutPath: root.home + "/.local/state/omarchy/ultimate/window-layout.json"
  readonly property string placementsPath: root.home + "/.local/state/omarchy/ultimate/window-placements.json"
  readonly property string shippedPinsPath: Quickshell.env("OMARCHY_PATH") + "/default/ultimate/taskbar-pins.json"

  onWindowsChanged: root._forgetUnmapped()
  onClientsIpcChanged: {
    root._trackClientRects()
    root._schedulePlaceNewClients()
  }

  function _ok() {
    root.lastError = ""
    return { changed: true, error: null }
  }

  function _noop() {
    return { changed: false, error: null }
  }

  function _err(title, explanation, detail) {
    root.lastError = String(title || "")
    return { changed: false, error: { title: String(title || ""), explanation: String(explanation || ""), detail: String(detail || "") } }
  }

  function _finish(verb, target, result, undo) {
    if (root.capabilityBroker && typeof root.capabilityBroker.record === "function")
      root.capabilityBroker.record("window", verb, target, result, undo || null, root._actor || "ui")
    return result
  }

  function _persistPlacements() {
    root.placementFile.setText(WindowModel.serializePlacements(root.placements))
  }

  function _geomForRect(rect) {
    var list = root.monitorsIpc || []
    var i
    var m
    var name = rect && rect.monitor ? String(rect.monitor) : ""
    var picked = name ? WindowModel.pickMonitor(list, name) : null
    if (!picked && rect) {
      var x = Number(rect.x)
      var y = Number(rect.y)
      for (i = 0; i < list.length; i++) {
        m = list[i]
        if (!m) continue
        if (x >= Number(m.x || 0) && x < Number(m.x || 0) + Number(m.width || 0) &&
            y >= Number(m.y || 0) && y < Number(m.y || 0) + Number(m.height || 0)) {
          picked = m
          break
        }
      }
    }
    if (!picked) picked = root.monitorIpc
    if (picked && picked.width) return WindowModel.compositorMonitor(picked)
    return root._monitorGeom()
  }

  function _trackClientRects() {
    var list = root.clientsIpc || []
    var rects = root._copyMap(root._lastRect)
    var apps = root._copyMap(root._lastAppId)
    var kinds = root._copyMap(root._placedKind)
    var kindsChanged = false
    var i
    var c
    var addr
    var key
    var fs
    for (i = 0; i < list.length; i++) {
      c = list[i]
      if (!c || !c.address) continue
      addr = root._canonAddr(c.address)
      fs = Number(c.fullscreen || 0)
      var prev = rects[addr]
      var prevFs = prev ? Number(prev.fullscreen || 0) : 0
      if (prevFs === 0 && fs === 1 && prev && Number(prev.width) > 0) {
        var geom = root._monitorGeom(addr)
        var area = WindowModel.workArea(geom)
        var looksMax = area.width && Math.abs(Number(prev.width) - area.width) <= 16 && Number(prev.height) >= area.height - 48
        if (!looksMax) {
          var normals = root._copyMap(root._normalBounds)
          normals[addr] = { x: Number(prev.x), y: Number(prev.y), width: Number(prev.width), height: Number(prev.height) }
          root._normalBounds = normals
        }
      }
      if (prevFs === 1 && fs === 0) {
        if (kinds[addr] === "max") {
          delete kinds[addr]
          kindsChanged = true
        }
        root._queueFloatRestore(addr)
      } else if (fs === 0 && c.hidden !== true && root._knownAddresses[addr] && c.at) {
        var areaNow = WindowModel.workArea(root._monitorGeom(addr))
        if (areaNow.width && Number(c.at[1]) < areaNow.y)
          root._queueFloatRestore(addr)
      }
      if (c.at && c.size && Number(c.size[0]) > 0) {
        rects[addr] = {
          x: Number(c.at[0] || 0),
          y: Number(c.at[1] || 0),
          width: Number(c.size[0]),
          height: Number(c.size[1]),
          fullscreen: fs,
          minimized: c.hidden === true,
          monitor: String(c.monitor || "")
        }
      }
      // CSD maximize never calls WindowService.maximize(), so record the
      // compositor bit here or placement will treat the address as new.
      if (fs === 1 && kinds[addr] !== "max") {
        kinds[addr] = "max"
        kindsChanged = true
      } else if ((fs === 2 || fs === 3) && kinds[addr] !== "full") {
        kinds[addr] = "full"
        kindsChanged = true
      }
      key = WindowModel.windowAppId({ class: c.class, appId: c.initialClass || c.class })
      if (key) apps[addr] = key
    }
    root._lastRect = rects
    root._lastAppId = apps
    if (kindsChanged) root._placedKind = kinds
  }

  function _rememberPlacement(address) {
    var rec = root._record(address) || {}
    if (WindowModel.isLockSurface(rec)) return
    var rect = root._lastRect[address] || root._clientRect(address)
    var key = root._lastAppId[address] || WindowModel.windowAppId(root._record(address) || {})
    if (!key || !rect || !rect.width) return
    if (rect.fullscreen || rect.minimized) return
    var geom = root._geomForRect(rect)
    if (geom && geom.width && (WindowModel.isSnapped(rect, geom, 8, 32) || WindowModel.isSnapped(rect, geom, 8, 0)))
      return
    var next = root._copyMap(root.placements)
    next[key] = WindowModel.clampRect(rect, geom)
    root.placements = next
    root._persistPlacements()
  }

  function _hydrateIfNeeded() {
    if (root._placementsReady) return
    var list = root._addresses()
    var init = ({})
    var i
    var addr
    if (list.length === 0) {
      var clients = root.clientsIpc || []
      if (clients.length === 0) return
      for (i = 0; i < clients.length; i++) {
        if (!clients[i] || !clients[i].address) continue
        addr = root._canonAddr(clients[i].address)
        if (addr) init[addr] = true
      }
    } else {
      for (i = 0; i < list.length; i++) init[list[i]] = true
    }
    var n = 0
    for (addr in init) n++
    if (n === 0) return
    root._knownAddresses = init
    root._placementsReady = true
  }

  function _forgetUnmapped() {
    root._hydrateIfNeeded()
    if (!root._placementsReady) return
    var list = root._addresses()
    var seen = ({})
    var i
    var addr
    var kind
    for (i = 0; i < list.length; i++) seen[list[i]] = true
    var clients = root.clientsIpc || []
    for (i = 0; i < clients.length; i++) {
      if (!clients[i] || !clients[i].address) continue
      addr = root._canonAddr(clients[i].address)
      if (addr) seen[addr] = true
    }
    for (addr in root._minimized) seen[addr] = true
    for (addr in root._placedKind) {
      kind = root._placedKind[addr]
      if (kind === "max" || kind === "full") seen[addr] = true
    }
    for (addr in root._knownAddresses) {
      if (seen[addr]) continue
      root._rememberPlacement(addr)
    }
    var next = ({})
    for (addr in root._knownAddresses) {
      if (seen[addr]) next[addr] = true
    }
    root._knownAddresses = next
  }

  function _schedulePlaceNewClients() {
    if (!root.placeNewClientsTimer) return
    root._hydrateIfNeeded()
    if (!root._placementsReady) return
    if (!root._hasUnplacedClient()) return
    if (!root.placeNewClientsTimer.running) root.placeNewClientsTimer.start()
  }

  function _hasUnplacedClient() {
    var list = root.clientsIpc || []
    var i
    var c
    var addr
    for (i = 0; i < list.length; i++) {
      c = list[i]
      if (!c || !c.address) continue
      addr = root._canonAddr(c.address)
      if (!addr || root._knownAddresses[addr]) continue
      if (c.hidden === true || c.mapped === false) continue
      if (Number(c.fullscreen || 0) > 0) continue
      if (root._minimized[addr]) continue
      if (root._placedKind[addr] === "max" || root._placedKind[addr] === "full") continue
      if (root.isMaximized(addr)) continue
      if (WindowModel.isLockSurface({
        class: c.class,
        appId: c.initialClass || c.class,
        initialClass: c.initialClass
      })) continue
      if (!WindowModel.windowAppId({ class: c.class, appId: c.initialClass || c.class })) continue
      return true
    }
    return false
  }

  function _placeNewClients() {
    if (!root._placementsReady) return
    var list = root.clientsIpc || []
    var known = root._copyMap(root._knownAddresses)
    var i
    var c
    var addr
    var key
    var geom
    var rec
    for (i = 0; i < list.length; i++) {
      c = list[i]
      if (!c || !c.address) continue
      addr = root._canonAddr(c.address)
      if (!addr || known[addr]) continue
      if (c.hidden === true || c.mapped === false) continue
      if (Number(c.fullscreen || 0) > 0) {
        known[addr] = true
        continue
      }
      if (root._minimized[addr] || root._placedKind[addr] === "max" || root._placedKind[addr] === "full") {
        known[addr] = true
        continue
      }
      if (root.isMaximized(addr)) {
        known[addr] = true
        continue
      }
      if (WindowModel.isLockSurface({
        class: c.class,
        appId: c.initialClass || c.class,
        initialClass: c.initialClass,
        title: c.title
      })) {
        known[addr] = true
        continue
      }
      key = WindowModel.windowAppId({ class: c.class, appId: c.initialClass || c.class })
      if (!key) continue
      rec = root._record(addr) || {}
      if (rec.modal || c.mapped === false) {
        known[addr] = true
        continue
      }
      geom = root._monitorGeom(addr)
      var remembered = key && root.placements[key] && root.placements[key].width ? root.placements[key] : null
      if (remembered && geom && geom.width && (WindowModel.isSnapped(remembered, geom, 8, 32) || WindowModel.isSnapped(remembered, geom, 8, 0)))
        remembered = null
      if (remembered)
        root._applyRect(addr, WindowModel.clampRect(remembered, geom))
      else {
        root._applyRect(addr, WindowModel.cascadeRect(geom, root._cascadeIndex))
        root._cascadeIndex++
      }
      known[addr] = true
    }
    root._knownAddresses = known
  }

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
      initialClass: String(ipc.initialClass || (client && client.initialClass) || ""),
      x: Number(at[0] || 0),
      y: Number(at[1] || 0),
      width: Number(size[0] || 0),
      height: Number(size[1] || 0),
      mapped: ipc.mapped !== false,
      floating: ipc.floating === true,
      fullscreen: fullscreen,
      workspace: wsName,
      workspaceId: wsId,
      minimized: hidden || !!root._minimized[address],
      monitorName: mon ? String(mon.name || "") : "",
      xwayland: ipc.xwayland === true,
      modal: ipc.modal === true || String(ipc.contentType || "") === "dialog" || String(ipc.xdgTag || "").indexOf("dialog") >= 0
    }
  }

  function _recordFromClient(c) {
    if (!c) return null
    var address = root._canonAddr(c.address)
    if (!address) return null
    var at = c.at || [0, 0]
    var size = c.size || [0, 0]
    var ws = c.workspace || {}
    var hidden = c.hidden === true || !!root._minimized[address]
    return {
      address: address,
      title: String(c.title || ""),
      appId: String(c.class || ""),
      class: String(c.class || ""),
      initialClass: String(c.initialClass || c.class || ""),
      x: Number(at[0] || 0),
      y: Number(at[1] || 0),
      width: Number(size[0] || 0),
      height: Number(size[1] || 0),
      mapped: c.mapped !== false,
      floating: c.floating === true,
      fullscreen: Number(c.fullscreen || 0),
      workspace: String(ws.name || ""),
      workspaceId: ws.id,
      minimized: hidden,
      monitorName: String(c.monitor || ""),
      xwayland: c.xwayland === true,
      modal: c.modal === true
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

  function _hyprbarsInset(address) {
    Hyprland.refreshToplevels()
    var rec = root._record(address) || {}
    var ipc = root._clientIpc(address) || {}
    var cls = rec.class || rec.appId || ipc.class || ipc.initialClass || ""
    return WindowModel.hyprbarsSnapInset({ class: cls, appId: cls })
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
    if (geom.width && WindowModel.isSnapped(rec, geom, 8, root._hyprbarsInset(address))) return
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
    return root._finish("pin", (entry && (entry.desktopId || entry.id)) || "", root._ok())
  }

  function unpin(desktopId) {
    root.pins = WindowModel.withoutPin(root.pins, desktopId)
    root._persistPins()
    return root._finish("unpin", desktopId, root._ok())
  }

  function togglePin(group) {
    if (!group) return root._noop()
    if (group.pinned) return root.unpin(group.desktopId || group.id)
    return root.pin(group)
  }

  function focus(address) {
    var target = root._addr(address)
    if (!target) return root._finish("focus", address, root._err("No window", "There is no window to focus.", ""))
    root._dispatchLua("hl.dsp.focus({ " + root._luaWindow(target) + " })")
    return root._finish("focus", target, root._ok())
  }

  function close(address) {
    var target = root._addr(address)
    if (!target) return root._finish("close", address, root._err("No window", "There is no window to close.", ""))
    root._rememberPlacement(target)
    root._dispatchLua("hl.dsp.window.close({ " + root._luaWindow(target) + " })", true)
    return root._finish("close", target, root._ok(), { verb: "activate", address: target })
  }

  function closeActive() {
    var address = root._activeAddress()
    if (address) return root.close(address)
    return root._finish("closeActive", "", root._err("No window", "There is no active window to close.", ""))
  }

  function minimize(address) {
    var target = root._addr(address)
    if (!target) return root._finish("minimize", address, root._err("No window", "There is no window to minimize.", ""))
    root._markMinimized(target, true)
    root._dispatchLua("hl.plugin.omarchy_minimize.minimize({ " + root._luaWindow(target) + " })", true)
    return root._finish("minimize", target, root._ok(), { verb: "restore", address: target })
  }

  function restore(address) {
    var target = root._addr(address)
    if (!target) return root._finish("restore", address, root._err("No window", "There is no window to restore.", ""))
    root._dispatchLua("hl.plugin.omarchy_minimize.restore({ " + root._luaWindow(target) + " })", true)
    root._markMinimized(target, false)
    var rec = root._clientRect(target)
    if (rec && Number(rec.fullscreen) !== 1) {
      var area = WindowModel.workArea(root._monitorGeom(target))
      if (area.width && (Number(rec.y) < area.y || Number(rec.x) + Number(rec.width) < area.x + 80)) {
        root._restoreFloatOnScreen(target, true)
        root._queueFloatRestore(target)
      }
    }
    return root._finish("restore", target, root._ok(), { verb: "minimize", address: target })
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
    var target = root._addr(address)
    if (root._minimized[target]) return true
    var rec = root._record(target)
    return !!(rec && rec.minimized)
  }

  function toggleFromTaskbar(address) {
    if (root.isMinimized(address)) return root.activate(address)
    if (root.isActive(address)) return root.minimize(address)
    return root.activate(address)
  }

  // Start click-through: the non-consuming left-click bind dismisses Start via
  // Quickshell IPC. Unmapping an OnDemand layer then restores the window that
  // had focus when Start opened, after the click already raised the target.
  // Do not Hyprland.dispatch from dismissOutside itself — the compositor is
  // still inside that bind and the socket deadlocks. activateAtCursorTimer
  // fires after the bind returns.
  function activateAtCursorSoon() {
    root.activateAtCursorTimer.restart()
  }

  function activateAtCursor() {
    // Hit-test in compositor Lua so this does not hyprctl from QML and does
    // not assemble a shell string around a window address.
    root._dispatchLua(
      "function() " +
      "local pos = hl.get_cursor_pos() " +
      "if not pos then return end " +
      "local hit, best = nil, 999999 " +
      "local wins = hl.get_windows({ mapped = true }) or {} " +
      "local i, w, x, y, ww, hh, fh " +
      "for i = 1, #wins do " +
      "w = wins[i] " +
      "if w and (not w.hidden) and w.visible and w.at and w.size then " +
      "x, y, ww, hh = w.at.x, w.at.y, w.size.x, w.size.y " +
      "if pos.x >= x and pos.y >= y and pos.x < x + ww and pos.y < y + hh then " +
      "fh = w.focus_history_id or 999 " +
      "if fh < best then best = fh; hit = w end " +
      "end end end " +
      "if hit then " +
      "hl.dispatch(hl.dsp.window.bring_to_top({ window = hit })) " +
      "hl.dispatch(hl.dsp.focus({ window = hit })) " +
      "end end"
    )
    return root._finish("activateAtCursor", "", root._ok())
  }

  // Alt+Tab and taskbar activation: unhide if needed, then focus. restore()
  // alone is a no-op for a visible window and is undone if the switcher overlay
  // unmaps and returns keyboard focus to the previous client.
  function activate(address) {
    var target = root._addr(address)
    if (!target) return root._finish("activate", address, root._err("No window", "There is no window to activate.", ""))
    var rec = root._record(target)
    if ((rec && rec.minimized) || root._minimized[target]) root.restore(target)
    root._dispatchLua("hl.dsp.window.bring_to_top({ " + root._luaWindow(target) + " })")
    root.focus(target)
    return root._finish("activate", target, root._ok())
  }

  function maximize(address) {
    var target = root._addr(address)
    if (!target) return root._finish("maximize", address, root._err("No window", "There is no window to maximize.", ""))
    root._rememberNormal(target)
    root._setPlacedKind(target, "max")
    root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"set\", " + root._luaWindow(target) + " })", true)
    return root._finish("maximize", target, root._ok(), { verb: "restoreNormal", address: target })
  }

  function unmaximize(address) {
    var target = root._addr(address)
    if (!target) return root._finish("unmaximize", address, root._err("No window", "There is no window to restore.", ""))
    if (root._placedKind[target] === "max") root._setPlacedKind(target, "float")
    root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"unset\", " + root._luaWindow(target) + " })", true)
    root._restoreFloatOnScreen(target, true)
    root._queueFloatRestore(target)
    return root._finish("unmaximize", target, root._ok())
  }

  function toggleMaximize(address) {
    var target = root._addr(address)
    if (!target) return root._finish("toggleMaximize", address, root._err("No window", "There is no window to maximize.", ""))
    if (root.isMaximized(target)) return root.unmaximize(target)
    return root.maximize(target)
  }

  function restoreOrMinimize(address) {
    return root.snapArrow(address, "d")
  }

  function restoreNormal(address) {
    var target = root._addr(address)
    if (!target) return root._finish("restoreNormal", address, root._err("No window", "There is no window to restore.", ""))
    root._setPlacedKind(target, "float")
    var bounds = root._normalBounds[target]
    if (!bounds) bounds = WindowModel.defaultFloatRect(root._monitorGeom(target))
    root._applyRect(target, bounds)
    return root._finish("restoreNormal", target, root._ok())
  }

  function _queueFloatRestore(addr) {
    if (!addr) return
    root._pendingFloatRestore = addr
    if (root.restoreFloatTimer) root.restoreFloatTimer.restart()
    if (root.restoreFloatRetryTimer) root.restoreFloatRetryTimer.restart()
  }

  function _restoreFloatOnScreen(target, force) {
    if (!target || root._placingRect) return
    var rec = root._clientRect(target)
    if (!force) {
      if (root._placedKind[target] === "max" || root._placedKind[target] === "full") return
      if (rec && Number(rec.fullscreen) === 1) return
    }
    var bounds = root._normalBounds[target]
    if (!bounds || !bounds.width) bounds = rec || root._lastRect[target]
    if (!bounds || !bounds.width) return
    root._applyRect(target, bounds)
  }

  function _applyRect(target, bounds) {
    if (!target || !bounds || !bounds.width || !bounds.height) return
    if (root._placingRect) return
    root._placingRect = true
    var geom = root._monitorGeom(target)
    if (geom && geom.width) bounds = WindowModel.clampRect(bounds, geom)
    var win = root._luaWindow(target)
    root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"unset\", layout_aware = false, " + win + " })")
    if (root._placedKind[target] === "max") root._setPlacedKind(target, "float")
    root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"unset\", " + win + " })")
    root._dispatchLua("hl.dsp.window.float({ action = \"enable\", " + win + " })")
    root._dispatchLua("hl.dsp.window.resize({ x = " + Math.round(Number(bounds.width)) + ", y = " + Math.round(Number(bounds.height)) + ", relative = false, " + win + " })")
    root._dispatchLua("hl.dsp.window.move({ x = " + Math.round(Number(bounds.x)) + ", y = " + Math.round(Number(bounds.y)) + ", relative = false, " + win + " })", true)
    root._placingRect = false
  }

  function moveTo(address, x, y) {
    var target = root._addr(address)
    if (!target) return root._finish("moveTo", address, root._err("No window", "There is no window to move.", ""))
    root._dispatchLua("hl.dsp.window.move({ x = " + Math.round(Number(x)) + ", y = " + Math.round(Number(y)) + ", relative = false, " + root._luaWindow(target) + " })")
    return root._finish("moveTo", target, root._ok())
  }

  function resizeTo(address, w, h) {
    var target = root._addr(address)
    if (!target) return root._finish("resizeTo", address, root._err("No window", "There is no window to resize.", ""))
    root._dispatchLua("hl.dsp.window.resize({ x = " + Math.round(Number(w)) + ", y = " + Math.round(Number(h)) + ", relative = false, " + root._luaWindow(target) + " })")
    return root._finish("resizeTo", target, root._ok())
  }

  function snapLeft(address) {
    return root.snapTo(address, "l")
  }

  function snapRight(address) {
    return root.snapTo(address, "r")
  }

  function snapTo(address, side) {
    var target = root._addr(address)
    if (!target) return root._finish("snapTo", address, root._err("No window", "There is no window to snap.", ""))
    root._applySnapKind(target, String(side || ""))
    return root._finish("snapTo", target, root._ok(), { verb: "restoreNormal", address: target })
  }

  function snapArrow(address, dir) {
    var target = root._addr(address)
    if (!target) return root._finish("snapArrow", address, root._err("No window", "There is no window to snap.", ""))
    var kind = "float"
    if (root.isMaximized(target)) kind = "max"
    else {
      var rec = root._clientRect(target) || root._record(target)
      var geom = root._monitorGeom(target)
      if (rec && geom.width) kind = WindowModel.snapKind(rec, geom, 8, root._hyprbarsInset(target))
    }
    root._applySnapKind(target, WindowModel.nextSnap(kind, dir))
    return root._finish("snapArrow", target, root._ok())
  }

  function aeroDragEnd(address, x, y) {
    var target = root._addr(address)
    if (!target) return root._finish("aeroDragEnd", address, root._err("No window", "There is no window to snap.", ""))
    Hyprland.refreshToplevels()
    var geom = root._monitorGeom(target)
    if (!geom.width) return root._finish("aeroDragEnd", target, root._err("No monitor", "The window's monitor geometry is unavailable.", ""))
    var px = Number(x)
    var py = Number(y)
    if (x === undefined || y === undefined || x === "" || y === "" || isNaN(px) || isNaN(py)) {
      return root._finish("aeroDragEnd", target, root._err("Missing cursor", "aeroDragEnd needs cursor coordinates.", ""))
    }
    var zone = WindowModel.aeroZone({ x: px, y: py }, geom)
    if (zone) {
      root._applySnapKind(target, zone)
      return root._finish("aeroDragEnd", target, root._ok(), { verb: "restoreNormal", address: target })
    }
    // Interior drop. lastIpcObject and the clients poll can still show the
    // pre-max float after maximize(), so isMaximized/isSnapped on those boxes
    // are a no-op. Trust the last verb; if that is also empty, unset
    // compositor maximize (no-op when the window is already normal).
    var placed = root._placedKind[target]
    var rec = root._clientRect(target) || root._record(target)
    if (placed === "max" || placed === "full" || root._isPlacedSnap(placed) || (rec && WindowModel.isSnapped(rec, geom, 8, root._hyprbarsInset(target)))) {
      return root.restoreNormal(target)
    }
    return root.unmaximize(target)
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
      }], geom, root._hyprbarsInset(list[i]))
      if (captured.windows && captured.windows[0]) recs.push(captured.windows[0])
    }
    root.savedLayout = { windows: recs }
    root.layoutFile.setText(WindowModel.serializeLayout(root.savedLayout))
    return root._finish("saveLayout", "", root._ok(), { verb: "restoreLayout" })
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
    return root._finish("restoreLayout", "", root._ok())
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
    // SSD clients inset 32px (bar_height). CSD clients use hyprbars:no_bar, so
    // the fused caption is already inside the client box.
    var rect = WindowModel.snapRect(geom, direction, root._hyprbarsInset(target))
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
    return root._finish("toggleShowDesktop", "", root._ok())
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
    if (list.length === 0) return root._finish("cycleNext", "", root._noop())
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
    return root._finish("cycleNext", "", root._ok())
  }

  function cyclePrev() {
    var list = root._addressesOnDesktop(root.activeDesktopId)
    if (list.length === 0) return root._finish("cyclePrev", "", root._noop())
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
    return root._finish("cyclePrev", "", root._ok())
  }

  function commitCycle() {
    if (!root.cycling) return root._finish("commitCycle", "", root._noop())
    var address = root.cycleList[root.cycleIndex]
    root.cancelCycle()
    if (address) return root.activate(address)
    return root._finish("commitCycle", "", root._ok())
  }

  function cancelCycle() {
    root.cycling = false
    root.cycleList = []
    return root._finish("cancelCycle", "", root._ok())
  }

  function activateFromSwitcher(address) {
    var target = root._canonAddr(address)
    root.cancelCycle()
    if (target) return root.activate(target)
    return root._finish("activateFromSwitcher", address, root._err("No window", "There is no window to activate.", ""))
  }

  function isFullscreen(address) {
    var target = root._addr(address)
    if (root._placedKind[target] === "full") return true
    var rec = root._clientRect(target) || root._record(target)
    return !!(rec && Number(rec.fullscreen) === 2)
  }

  function toggleFullscreen(address) {
    var target = root._addr(address)
    if (!target) return root._finish("toggleFullscreen", address, root._err("No window", "There is no window to fullscreen.", ""))
    // action=toggle is a no-op through hyprctl eval and is racy through
    // Quickshell when lastIpcObject still says 2 after restoreNormal. Set and
    // unset are explicit. layout_aware=false is default compositor fullscreen,
    // not a layout handler that can swallow F11 on overlapping floats.
    if (root.isFullscreen(target)) {
      root._setPlacedKind(target, "float")
      root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"unset\", layout_aware = false, " + root._luaWindow(target) + " })", true)
      return root._finish("toggleFullscreen", target, root._ok())
    }
    root._rememberNormal(target)
    root._setPlacedKind(target, "full")
    root.focus(target)
    root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"set\", layout_aware = false, " + root._luaWindow(target) + " })", true)
    return root._finish("toggleFullscreen", target, root._ok(), { verb: "restoreNormal", address: target })
  }

  function createDesktop() {
    var next = WindowModel.nextDesktopId(WindowModel.desktopIds(root.workspacesIpc))
    var list = (root.workspacesIpc || []).slice()
    list.push({ id: next, name: String(next) })
    root.workspacesIpc = list
    root.activeDesktopId = next
    root._dispatchLua('hl.dsp.focus({ workspace = "' + next + '" })', true)
    return root._finish("createDesktop", String(next), root._ok())
  }

  function switchDesktop(dir) {
    var dest = WindowModel.neighborDesktop(WindowModel.desktopIds(root.workspacesIpc), root.activeDesktopId, dir)
    if (!dest || dest === root.activeDesktopId) return root._finish("switchDesktop", "", root._noop())
    return root.switchToDesktop(dest)
  }

  function switchToDesktop(id) {
    var dest = Number(id)
    if (!(dest > 0)) return root._finish("switchToDesktop", id, root._err("Invalid desktop", "Desktop id must be a positive number.", String(id)))
    root._dispatchLua('hl.dsp.focus({ workspace = "' + dest + '" })', true)
    return root._finish("switchToDesktop", String(dest), root._ok())
  }

  function moveToDesktop(address, desktopId) {
    var target = root._addr(address)
    var dest = Number(desktopId)
    if (!target || !(dest > 0)) return root._finish("moveToDesktop", address, root._err("Cannot move", "Window or desktop is missing.", ""))
    root._dispatchLua('hl.dsp.window.move({ workspace = "' + dest + '", follow = false, ' + root._luaWindow(target) + " })", true)
    return root._finish("moveToDesktop", target, root._ok())
  }

  function closeDesktop() {
    var ids = WindowModel.desktopIds(root.workspacesIpc)
    var cur = root.activeDesktopId
    if (ids.length <= 1) return root._finish("closeDesktop", "", root._noop())
    var dest = WindowModel.neighborDesktop(ids, cur, "l")
    if (dest === cur) dest = WindowModel.neighborDesktop(ids, cur, "r")
    if (!dest || dest === cur) return root._finish("closeDesktop", "", root._noop())
    var wins = root._addressesOnDesktop(cur)
    var i
    for (i = 0; i < wins.length; i++) root.moveToDesktop(wins[i], dest)
    root._dispatchLua('hl.dsp.focus({ workspace = "' + dest + '" })', true)
    return root._finish("closeDesktop", String(cur), root._ok())
  }

  function moveToMonitor(address, dir) {
    var target = root._addr(address)
    if (!target) return root._finish("moveToMonitor", address, root._err("No window", "There is no window to move.", ""))
    var rec = root._record(target)
    var client = root._clientIpc(target)
    var hint = ""
    if (rec && rec.monitorName) hint = rec.monitorName
    else if (client && client.monitor != null) hint = client.monitor
    var current = WindowModel.pickMonitor(root.monitorsIpc, hint)
    var dest = WindowModel.neighborMonitor(root.monitorsIpc, current, dir)
    if (!dest || !dest.name) {
      return root._finish("moveToMonitor", target, root._err("No neighboring monitor", "There is no monitor in that direction.", String(dir)))
    }
    root._dispatchLua('hl.dsp.window.move({ monitor = "' + dest.name + '", ' + root._luaWindow(target) + " })", true)
    return root._finish("moveToMonitor", target, root._ok())
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

  property FileView csdClientsFile: FileView {
    path: Quickshell.env("OMARCHY_PATH") + "/default/ultimate/csd-clients.json"
    watchChanges: true
    printErrors: false
    onLoaded: WindowModel.setCsdClientsJson(text())
    onFileChanged: reload()
  }

  property FileView placementFile: FileView {
    path: root.placementsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.placements = WindowModel.parsePlacements(text())
    onLoadFailed: root.placements = ({})
    onFileChanged: reload()
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
