import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "WorkspacesModel.js" as WorkspacesModel

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // A Repeater compares its model by identity, so this array is replaced only
  // when the ids really differ. WorkspacesModel carries the reasoning and the
  // tests.
  property var ids: [1, 2, 3, 4, 5]
  property var byId: ({})

  // Tracked as a binding so the dependency on Hyprland's workspace list is
  // declared rather than guessed at through a signal name.
  readonly property var liveWorkspaces: Hyprland.workspaces.values
  onLiveWorkspacesChanged: root.refreshWorkspaces()

  function refreshWorkspaces() {
    var values = root.liveWorkspaces || []
    root.byId = WorkspacesModel.byId(values)
    root.ids = WorkspacesModel.stableIds(root.ids, WorkspacesModel.workspaceIds(values))
  }

  Component.onCompleted: root.refreshWorkspaces()

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
    columns: root.vertical ? 1 : root.ids.length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.ids

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.byId[modelData] || null
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
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
