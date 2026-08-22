import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "WindowModel.js" as WindowModel

// WindowService: the typed window-management capability behind the Ultimate
// taskbar, Start, and every window affordance (docs/settings-service-api.md).
// UI never runs hyprctl and never touches ToplevelManager directly; it calls
// these intent-named verbs.
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

  readonly property var windows: ToplevelManager.toplevels.values
  readonly property var activeToplevel: ToplevelManager.activeToplevel
  readonly property var groups: WindowModel.buildGroups(root.windows, root.pins)
  readonly property string pinsPath: root.home + "/.local/state/omarchy/ultimate/taskbar-pins.json"

  function _spawn(command) {
    var proc = Qt.createQmlObject("import Quickshell.Io; Process {}", root, "ws-proc")
    proc.command = command
    proc.exited = function(code) {
      if (code !== 0) root.lastError = command.join(" ") + " exited " + code
      proc.destroy()
    }
    proc.running = true
  }

  function _run(args) {
    root._spawn(["hyprctl"].concat(args))
  }

  function _dispatchTokens(tokens) {
    root._run(["dispatch"].concat(tokens))
  }

  function _restoreFromSpecial(address) {
    root._spawn([
      "bash", "-c",
      "hyprctl dispatch movetoworkspacesilent \"$(hyprctl activeworkspace -j | jq -r .id),address:$0\"",
      String(address || "")
    ])
  }

  function _forAddress(address) {
    var values = ToplevelManager.toplevels.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].address === address) return values[i]
    }
    return null
  }

  function _activeAddress() {
    return root.activeToplevel ? root.activeToplevel.address : ""
  }

  function _markMinimized(address, parked) {
    var next = ({})
    for (var key in root._minimized) next[key] = root._minimized[key]
    if (parked) next[address] = true
    else delete next[address]
    root._minimized = next
  }

  function _persistPins() {
    pinFile.setText(WindowModel.serializePins(root.pins))
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
    var win = root._forAddress(address)
    if (win) win.activate()
  }

  function close(address) {
    var win = root._forAddress(address)
    if (win) win.close()
  }

  function closeActive() {
    var address = root._activeAddress()
    if (address) root.close(address)
  }

  function minimize(address) {
    if (!address) return
    root._markMinimized(address, true)
    root._dispatchTokens(["movetoworkspacesilent", "special:minimized,address:" + address])
  }

  function restore(address) {
    if (root._minimized[address]) {
      root._restoreFromSpecial(address)
      root._markMinimized(address, false)
    }
    var win = root._forAddress(address)
    if (win) {
      if (typeof win.minimize === "function") win.minimize(false)
      win.activate()
      return
    }
    root._restoreFromSpecial(address)
    root._dispatchTokens(["focuswindow", "address:" + address])
  }

  function isActive(address) {
    return root.activeToplevel !== null && root.activeToplevel.address === address
  }

  function toggleFromTaskbar(address) {
    if (root.isActive(address)) root.minimize(address)
    else root.restore(address)
  }

  function maximize(address) {
    root.focus(address)
    root._dispatchTokens(["fullscreen", "2"])
  }

  function unmaximize(address) {
    root._dispatchTokens(["fullscreen", "0"])
  }

  function snapLeft(address) {
    var target = address || root._activeAddress()
    if (target) root.focus(target)
    root._snapActive("l")
  }

  function snapRight(address) {
    var target = address || root._activeAddress()
    if (target) root.focus(target)
    root._snapActive("r")
  }

  function _snapActive(direction) {
    root._dispatchTokens(["setfloating"])
    root._dispatchTokens(["resizeactive", "exact", "50%", "100%"])
    if (direction === "l") root._dispatchTokens(["movewindowpixel", "exact", "0", "0"])
    else root._dispatchTokens(["movewindowpixel", "exact", "50%", "0"])
  }

  function toggleShowDesktop() {
    if (root._desktopShown) {
      for (var i = 0; i < root._batch.length; i++) root.restore(root._batch[i])
      root._batch = []
    } else {
      var values = ToplevelManager.toplevels.values
      var batch = []
      for (var j = 0; j < values.length; j++) {
        batch.push(values[j].address)
        root.minimize(values[j].address)
      }
      root._batch = batch
    }
    root._desktopShown = !root._desktopShown
  }

  function _addresses() {
    var values = ToplevelManager.toplevels.values
    var list = []
    for (var i = 0; i < values.length; i++) {
      if (values[i] && values[i].address) list.push(values[i].address)
    }
    return list
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

  Process {
    command: ["bash", "-c", "mkdir -p \"$0\"", root.home + "/.local/state/omarchy/ultimate"]
    running: true
  }

  FileView {
    id: pinFile
    path: root.pinsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.pins = WindowModel.parsePins(text())
    onLoadFailed: root.pins = []
    onFileChanged: reload()
  }
}
