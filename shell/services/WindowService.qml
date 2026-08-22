import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "WindowModel.js" as WindowModel

// WindowService: the typed window-management capability behind the Ultimate
// taskbar, Start, and every window affordance (docs/settings-service-api.md).
// UI never runs hyprctl and never touches ToplevelManager directly; it calls
// these intent-named verbs.
//
// Hyprland 0.55+ parses `hyprctl dispatch …` as Lua (`hl.dispatch(…)`). Classic
// token dispatchers (`fullscreen 2`, classic pixel-move, `resizeactive`) fail
// with a parse error on that parser. Verbs below send `hl.dsp.window.*` forms,
// always naming `window = "address:…"`, proven live on Hyprland 0.56.2.
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

  // Quickshell.execDetached, not a Process child of this QtObject. Live:
  // a dynamic Process object never started; a named Process queue dropped
  // the third minimize and the restore that followed. Independent hyprctl
  // verbs (three minimizes) must not share one runner. Snap stays one bash
  // -c so float && resize && move cannot race.
  function _spawn(command) {
    Quickshell.execDetached(command)
  }

  function _dispatchLua(expr) {
    Quickshell.execDetached(["hyprctl", "dispatch", expr])
  }

  function _addr(address) {
    var target = String(address || "")
    if (target === "" || target === "active") return root._activeAddress()
    return target
  }

  function _luaWindow(address) {
    return 'window = "address:' + String(address || "") + '"'
  }

  function _restoreFromSpecial(address) {
    root._spawn([
      "bash", "-c",
      "hyprctl dispatch \"hl.dsp.window.move({ workspace = \\\"$(hyprctl activeworkspace -j | jq -r .id)\\\", follow = true, " + 'window = \\"address:$1\\" })"',
      "omarchy-restore",
      String(address || "")
    ])
  }

  function _forAddress(address) {
    var target = root._canonAddr(address)
    var hypr = root._hyprlandToplevels()
    var i
    for (i = 0; i < hypr.length; i++) {
      if (hypr[i] && root._canonAddr(hypr[i].address) === target) return hypr[i].wayland || hypr[i]
    }
    var values = ToplevelManager.toplevels.values
    for (i = 0; i < values.length; i++) {
      var win = values[i]
      if (!win) continue
      var addr = win.address
      if (!addr && win.HyprlandToplevel) addr = win.HyprlandToplevel.address
      if (root._canonAddr(addr) === target) return win
    }
    return null
  }

  function _activeAddress() {
    var hypr = root._hyprlandToplevels()
    var i
    for (i = 0; i < hypr.length; i++) {
      if (hypr[i] && hypr[i].activated && hypr[i].address) return root._canonAddr(hypr[i].address)
    }
    var active = root.activeToplevel
    if (!active) return ""
    var addr = active.address
    if (!addr && active.HyprlandToplevel) addr = active.HyprlandToplevel.address
    return root._canonAddr(addr)
  }

  function _canonAddr(addr) {
    var s = String(addr || "")
    if (s === "") return ""
    if (s.indexOf("0x") === 0 || s.indexOf("0X") === 0) return s
    if (/^[0-9a-fA-F]+$/.test(s)) return "0x" + s
    return s
  }

  function _hyprlandToplevels() {
    try {
      if (Hyprland.toplevels && Hyprland.toplevels.values) return Hyprland.toplevels.values
    } catch (e) {
    }
    return []
  }

  function _addresses() {
    var list = []
    var hypr = root._hyprlandToplevels()
    var i
    for (i = 0; i < hypr.length; i++) {
      var hyprAddr = root._canonAddr(hypr[i] && hypr[i].address)
      if (hyprAddr) list.push(hyprAddr)
    }
    if (list.length) return list
    var values = ToplevelManager.toplevels.values
    for (i = 0; i < values.length; i++) {
      var win = values[i]
      if (!win) continue
      var addr = win.address
      if (!addr && win.HyprlandToplevel) addr = win.HyprlandToplevel.address
      addr = root._canonAddr(addr)
      if (addr) list.push(addr)
    }
    return list
  }

  function _markMinimized(address, parked) {
    var next = ({})
    for (var key in root._minimized) next[key] = root._minimized[key]
    if (parked) next[address] = true
    else delete next[address]
    root._minimized = next
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
    var win = root._forAddress(target)
    if (win) win.activate()
    else if (target) root._dispatchLua("hl.dsp.focus({ " + root._luaWindow(target) + " })")
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
    var target = root._addr(address)
    if (!target) return
    root._markMinimized(target, true)
    root._dispatchLua("hl.dsp.window.move({ workspace = \"special:minimized\", follow = false, " + root._luaWindow(target) + " })")
  }

  function restore(address) {
    var target = root._addr(address)
    if (!target) return
    // Always move onto the active workspace. Toplevel.activate() on a
    // special:minimized client does not restore it (live: address stayed
    // on workspace -98 until a later hyprctl move ran).
    root._restoreFromSpecial(target)
    root._markMinimized(target, false)
  }

  function isActive(address) {
    return root.activeToplevel !== null && root.activeToplevel.address === address
  }

  function toggleFromTaskbar(address) {
    if (root.isActive(address)) root.minimize(address)
    else root.restore(address)
  }

  function maximize(address) {
    var target = root._addr(address)
    if (!target) return
    root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"set\", " + root._luaWindow(target) + " })")
  }

  function unmaximize(address) {
    var target = root._addr(address)
    if (!target) return
    root._dispatchLua("hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"unset\", " + root._luaWindow(target) + " })")
  }

  function snapLeft(address) {
    root._snap(root._addr(address), "l")
  }

  function snapRight(address) {
    root._snap(root._addr(address), "r")
  }

  function _snap(target, direction) {
    if (!target) return
    // Percent sizes are rejected by hl.dsp.window.resize; compute pixels from
    // the focused monitor and issue float → resize → move as one ordered shell
    // so they cannot race. Live-proven on Hyprland 0.56.2 / virtio-vga 1920x1080.
    root._spawn([
      "bash", "-c",
      'mon=$(hyprctl -j monitors | jq -c ".[] | select(.focused == true)")\n' +
      'w=$(jq -r .width <<<"$mon")\n' +
      'h=$(jq -r .height <<<"$mon")\n' +
      'top=$(jq -r ".reserved[0]" <<<"$mon")\n' +
      'right=$(jq -r ".reserved[1]" <<<"$mon")\n' +
      'bot=$(jq -r ".reserved[2]" <<<"$mon")\n' +
      'left=$(jq -r ".reserved[3]" <<<"$mon")\n' +
      'ww=$((w - left - right))\n' +
      'wh=$((h - top - bot))\n' +
      'half=$((ww / 2))\n' +
      'if [[ $1 == l ]]; then x=$left; else x=$((left + half)); fi\n' +
      'hyprctl dispatch "hl.dsp.window.float({ action = \\"enable\\", window = \\"address:$2\\" })" && ' +
      'hyprctl dispatch "hl.dsp.window.resize({ x = $half, y = $wh, relative = false, window = \\"address:$2\\" })" && ' +
      'hyprctl dispatch "hl.dsp.window.move({ x = $x, y = $top, relative = false, window = \\"address:$2\\" })"',
      "omarchy-snap",
      direction,
      target
    ])
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
