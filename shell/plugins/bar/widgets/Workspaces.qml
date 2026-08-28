import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : 10
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      // Static model: delegates are created once and only toggle visibility/state
      // afterwards. Rebuilding the model on every workspace create/destroy forces
      // Quickshell to recreate WidgetButton objects on the main thread, which
      // saturates the Hyprland event loop under rapid switching and makes the
      // focus indicator lag (the "stuck workspace" backlog from #8788).
      model: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedMonitor !== null && Hyprland.focusedMonitor.activeWorkspace !== null && Hyprland.focusedMonitor.activeWorkspace.id === modelData

        // Base workspaces 1-5 are always shown; extras 6-10 only when they carry
        // state, so empty non-persistent workspaces never linger in the bar (#8788).
        visible: modelData <= 5 || occupied || focused

        bar: root.bar
        text: focused ? "\uDB85\uDCFB" : (modelData === 10 ? "0" : String(modelData))
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
