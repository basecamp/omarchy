import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "workspacesPro"
  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property var ids: bar ? bar.workspaceIds() : [1, 2, 3, 4, 5]
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : 26
  readonly property int slotSize: vertical ? barSize : 26
  readonly property int spacing: vertical ? 4 : 4

  readonly property int focusedIndex: {
    if (!Hyprland.focusedWorkspace) return -1
    var focused = Hyprland.focusedWorkspace.id
    for (var i = 0; i < ids.length; i++) if (ids[i] === focused) return i
    return -1
  }

  implicitWidth: vertical ? barSize : ids.length * slotSize + (ids.length - 1) * spacing + 6
  implicitHeight: vertical ? ids.length * slotSize + (ids.length - 1) * spacing + 6 : barSize

  Rectangle {
    id: indicator
    width: vertical ? root.slotSize - 8 : root.slotSize - 6
    height: vertical ? root.slotSize - 6 : root.slotSize - 8
    radius: 4
    color: root.bar.foreground
    opacity: root.focusedIndex >= 0 ? 0.25 : 0
    x: vertical ? (root.width - width) / 2 : 3 + root.focusedIndex * (root.slotSize + root.spacing) + (root.slotSize - width) / 2
    y: vertical ? 3 + root.focusedIndex * (root.slotSize + root.spacing) + (root.slotSize - height) / 2 : (root.height - height) / 2

    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 160 } }
  }

  Loader {
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalLayout : horizontalLayout
  }

  Component {
    id: horizontalLayout

    Row {
      anchors.centerIn: parent
      spacing: root.spacing

      Repeater {
        model: root.ids
        WorkspaceButton {
          required property int modelData
          workspaceId: modelData
        }
      }
    }
  }

  Component {
    id: verticalLayout

    Column {
      anchors.centerIn: parent
      spacing: root.spacing

      Repeater {
        model: root.ids
        WorkspaceButton {
          required property int modelData
          workspaceId: modelData
        }
      }
    }
  }

  component WorkspaceButton: Item {
    id: ws

    property int workspaceId: 0
    readonly property var workspace: root.bar ? root.bar.workspaceById(workspaceId) : null
    readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
    readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === workspaceId

    implicitWidth: root.slotSize
    implicitHeight: root.slotSize

    Text {
      anchors.centerIn: parent
      text: ws.focused ? "󱓻" : (ws.workspaceId === 10 ? "0" : String(ws.workspaceId))
      color: root.bar ? root.bar.foreground : "#cacccc"
      font.family: root.bar ? root.bar.fontFamily : "JetBrainsMono Nerd Font"
      font.pixelSize: ws.focused ? 13 : 11
      opacity: ws.focused ? 1 : (ws.occupied || ws.workspaceId <= 5 ? 0.8 : 0.4)

      Behavior on opacity { NumberAnimation { duration: 160 } }
      Behavior on font.pixelSize { NumberAnimation { duration: 160 } }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor

      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          Hyprland.dispatch("movetoworkspace " + ws.workspaceId)
        } else {
          root.bar.focusWorkspace(ws.workspaceId)
        }
      }

      onWheel: function(wheel) {
        if (wheel.angleDelta.y > 0) Hyprland.dispatch("workspace e-1")
        else Hyprland.dispatch("workspace e+1")
      }
    }
  }
}
