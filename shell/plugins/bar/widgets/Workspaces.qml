import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "WorkspacesModel.js" as WorkspacesModel

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceById(id) {
    return WorkspacesModel.workspaceById(Hyprland.workspaces.values, id)
  }

  function workspaceIds() {
    return WorkspacesModel.workspaceIds(Hyprland.workspaces.values)
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)
  readonly property int windowSquare: Style.space(5)
  readonly property int windowGap: Style.space(2)
  readonly property int windowSlotMargin: Style.space(2)

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
        id: button
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: WorkspacesModel.isOccupied(workspace)
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property int windowCount: WorkspacesModel.toplevelCount(workspace)
        readonly property int windowRowWidth: WorkspacesModel.windowRowLength(windowCount, root.windowSquare, root.windowGap)

        bar: root.bar
        text: WorkspacesModel.workspaceLabel(modelData, focused)
        labelVisible: false
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Math.max(Style.space(20), windowRowWidth + Style.space(6))
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }

        Text {
          id: workspaceLabel
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: windowSlot.top
          text: button.text
          color: button.foreground
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          renderType: Text.NativeRendering
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }

        Item {
          id: windowSlot
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.windowSlotMargin
          height: root.windowSquare
          width: Math.max(root.windowSquare, button.windowRowWidth)

          Row {
            id: windowRow
            anchors.centerIn: parent
            spacing: root.windowGap

            Repeater {
              model: button.workspace ? button.workspace.toplevels : 0

              Rectangle {
                required property var modelData

                width: root.windowSquare
                height: root.windowSquare
                color: WorkspacesModel.isWindowFocused(modelData) ? button.foreground : "transparent"
                border.width: Style.spacing.hairline
                border.color: button.foreground
                antialiasing: false
              }
            }
          }
        }
      }
    }
  }
}
