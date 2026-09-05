import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  readonly property bool hideEmptyWorkspaces: setting("hideEmptyWorkspaces", false) === true

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceOccupied(workspace) {
    return workspace !== null && workspace.toplevels.values.length > 0
  }

  function workspaceIds() {
    var ids = root.hideEmptyWorkspaces ? [] : [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values
    var focusedId = Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : 0

    for (var i = 0; i < values.length; i++) {
      var workspace = values[i]
      var id = workspace.id

      if (id < 1 || id > 10 || ids.indexOf(id) !== -1) continue
      // The focused workspace survives the filter even when empty: hiding it
      // would leave nothing on the bar saying where you are.
      if (root.hideEmptyWorkspaces && id !== focusedId && !root.workspaceOccupied(workspace)) continue

      ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
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
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: root.workspaceOccupied(workspace)
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

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
