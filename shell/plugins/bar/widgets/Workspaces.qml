import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// ─────────────────────────────────────────────────────────────────────────────
// Workspaces widget — Global-workspace-aware rewrite.
//
// TERMINOLOGY
//   AW (Apparent Workspace): what the user sees — AW1 through AW5.
//     Switching to AWN moves EVERY monitor to its corresponding Hyprland WS.
//   WS (Hyprland Workspace): the underlying integer ID Hyprland tracks.
//     Each monitor owns an exclusive range (offset = monitorId * 10):
//       monitor 0  →  WS  1-10
//       monitor 1  →  WS 11-20
//       monitor 2  →  WS 21-30
//     AWN on monitor M = WS(M*10 + N).
//
// GLOBAL MODE (workspace-global.lua toggle present):
//   - Bar always shows exactly 5 buttons labelled 1-5 (AW slots).
//   - Clicking AWN calls omarchy-hyprland-workspace-global-switch N, which
//     moves all monitors to their slot-N WS simultaneously.
//   - Focused: all bars agree — derived from any monitor's activeWorkspace.
//   - Occupied: AWN is lit if ANY monitor has windows on WS(monitorId*10+N).
//
// LOCAL MODE (toggle absent):
//   - Falls back to stock omarchy behavior: shows raw Hyprland WS IDs 1-5
//     and clicking dispatches a single-monitor focus to that WS.
// ─────────────────────────────────────────────────────────────────────────────

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // ── Global-mode flag ───────────────────────────────────────────────────────

  readonly property string globalToggleDir:
    (Quickshell.env("HOME") || "") + "/.local/state/omarchy/toggles/hypr"

  property bool globalMode: false

  Process {
    id: globalFlagProbe
    running: true
    command: ["bash", "-c",
      "[[ -f $HOME/.local/state/omarchy/toggles/hypr/workspace-global.lua ]] && echo yes || echo no"]
    stdout: SplitParser {
      onRead: function(line) { root.globalMode = String(line).trim() === "yes" }
    }
  }

  // Watch the directory so we detect the flag file being created or deleted.
  FileView {
    path: root.globalToggleDir
    watchChanges: true
    printErrors: false
    onFileChanged: globalFlagProbe.running = true
  }

  // ── This bar's monitor identity ────────────────────────────────────────────
  // Needed for:
  //   (a) global mode: derive focused slot from this monitor's active WS
  //   (b) local mode: fullscreen=2 workaround targets this monitor only

  readonly property string thisMonitorName: {
    var win = root.QsWindow ? root.QsWindow.window : null
    return (win && win.screen && win.screen.name) ? String(win.screen.name) : ""
  }

  readonly property int thisMonitorId: {
    var mons = Hyprland.monitors.values
    for (var i = 0; i < mons.length; i++) {
      if (mons[i].name === root.thisMonitorName) return mons[i].id
    }
    return 0
  }

  readonly property int thisMonitorOffset: root.thisMonitorId * 10

  // ── AW slot list ───────────────────────────────────────────────────────────
  // Global mode: always [1, 2, 3, 4, 5] — stable, independent of which
  // Hyprland WS objects happen to exist at any moment.
  // Local mode: raw Hyprland WS IDs 1-10 (stock omarchy logic).

  function awSlots() {
    if (root.globalMode) {
      return [1, 2, 3, 4, 5]
    }
    // Local mode fallback — stock logic.
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }
    ids.sort(function(l, r) { return l - r })
    return ids
  }

  // ── Focused slot ───────────────────────────────────────────────────────────
  // Global mode: all monitors switch together, so any monitor's active WS
  // divided by its offset gives the current slot. We use monitor 0 (offset 0)
  // as the authoritative source — its active WS id IS the slot number.
  // All bars read the same value, so all three bars agree.
  //
  // Local mode: match Hyprland.focusedWorkspace.id (stock behavior).

  function awIsFocused(slot) {
    if (!root.globalMode) {
      return Hyprland.focusedWorkspace !== null &&
             Hyprland.focusedWorkspace.id === slot
    }
    // Read monitor 0's active workspace id — that equals the current AW slot.
    var mons = Hyprland.monitors.values
    for (var i = 0; i < mons.length; i++) {
      if (mons[i].id === 0) {
        var activeWsId = mons[i].activeWorkspace ? mons[i].activeWorkspace.id : -1
        // Monitor 0 offset is 0, so activeWsId == slot directly.
        return activeWsId === slot
      }
    }
    return false
  }

  // ── Occupied indicator ────────────────────────────────────────────────────
  // Global mode: AWN is occupied if ANY monitor has windows on WS(monId*10+N).
  // All three bars show the same occupancy state for each slot.
  //
  // Local mode: check raw WS id == slot for windows (stock behavior).

  function awIsOccupied(slot) {
    if (!root.globalMode) {
      var values = Hyprland.workspaces.values
      for (var i = 0; i < values.length; i++) {
        if (values[i].id === slot) {
          return values[i].toplevels.values.length > 0
        }
      }
      return false
    }
    // Global mode: walk all monitors, check WS(monitorId*10 + slot).
    var mons = Hyprland.monitors.values
    for (var m = 0; m < mons.length; m++) {
      var wsId = mons[m].id * 10 + slot
      var wsList = Hyprland.workspaces.values
      for (var w = 0; w < wsList.length; w++) {
        if (wsList[w].id === wsId && wsList[w].toplevels.values.length > 0) {
          return true
        }
      }
    }
    return false
  }

  // ── Switch to an AW slot ──────────────────────────────────────────────────
  // Global mode: omarchy-hyprland-workspace-global-switch <slot> handles all
  // monitors, fullscreen=2, and workspace-theft prevention internally.
  //
  // Local mode: single-monitor focus with fullscreen=2 workaround — detect the
  // blocking window by address, stash it to WS999 (no focus change), switch
  // the workspace, then restore it to its original WS by address.

  function switchToAW(slot) {
    if (!root.bar) return

    if (root.globalMode) {
      if (slot < 1 || slot > 10) return
      root.bar.run("omarchy-hyprland-workspace-global-switch " + slot)
      return
    }

    // Local mode fallback.
    var monId = root.thisMonitorId
    var bashCmd =
      "cjson=$(hyprctl clients -j 2>/dev/null || echo '[]'); " +
      "fs_addr=$(echo \"$cjson\" | jq -r --argjson mid " + monId + " " +
        "'.[] | select(.monitor == $mid and .fullscreen == 2) | .address' " +
        "2>/dev/null | head -1); " +
      "orig_ws=''; " +
      "if [ -n \"$fs_addr\" ]; then " +
      "  orig_ws=$(echo \"$cjson\" | jq -r --arg addr \"$fs_addr\" " +
        "'.[] | select(.address == $addr) | .workspace.id' 2>/dev/null); " +
      "  hyprctl eval \"hl.dispatch(hl.dsp.window.move({ workspace = '999', window = 'address:$fs_addr', follow = false }))\" >/dev/null 2>&1 || true; " +
      "fi; " +
      "hyprctl eval \"hl.dispatch(hl.dsp.focus({ workspace = '" + slot + "' }))\" >/dev/null 2>&1 || true; " +
      "if [ -n \"$fs_addr\" ] && [ -n \"$orig_ws\" ]; then " +
      "  hyprctl eval \"hl.dispatch(hl.dsp.window.move({ workspace = '$orig_ws', window = 'address:$fs_addr', follow = false }))\" >/dev/null 2>&1 || true; " +
      "fi"
    root.bar.run("bash -c " + Util.shellQuote(bashCmd))
  }

  // ── Layout ────────────────────────────────────────────────────────────────

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.awSlots().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.awSlots()

      WidgetButton {
        required property int modelData  // AW slot number (1-5)

        readonly property bool occupied: root.awIsOccupied(modelData)
        readonly property bool focused:  root.awIsFocused(modelData)

        bar: root.bar
        text: String(modelData)
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.switchToAW(modelData) }
      }
    }
  }
}
