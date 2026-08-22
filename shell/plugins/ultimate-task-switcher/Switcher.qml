import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property var windowService: shell ? shell.windowService : null
  readonly property var cycleList: windowService ? windowService.cycleList : []
  readonly property int cycleIndex: windowService ? windowService.cycleIndex : 0

  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  PanelWindow {
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // Quickshell only maps a layer surface when it is anchored to screen
    // edges. implicitWidth/Height alone never produced omarchy-task-switcher
    // (live: emojis overlay mapped, this one did not, with two feet open).
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "omarchy-task-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Rectangle {
      anchors.centerIn: parent
      width: Math.min(parent.width - 32, 120 * Math.max(1, cycleList.length) + 40)
      height: 140
      color: Tokens.surface.glass
      radius: Tokens.radius.large
      border.color: Tokens.border.subtle
      border.width: 1

      Row {
        anchors.centerIn: parent
        spacing: 8
        Repeater {
          model: cycleList
          delegate: Rectangle {
            width: 96
            height: 96
            radius: Tokens.radius.medium
            color: index === cycleIndex ? Util.alpha(Tokens.accent.primary, 0.28) : Tokens.surface.raised
            border.color: index === cycleIndex ? Tokens.accent.primary : Tokens.border.subtle
            border.width: 1

            Text {
              anchors.centerIn: parent
              width: parent.width - 8
              wrapMode: Text.Wrap
              horizontalAlignment: Text.AlignHCenter
              text: {
                if (!windowService) return String(modelData)
                var win = windowService._forAddress ? windowService._forAddress(modelData) : null
                if (win && win.title) return win.title
                return String(modelData)
              }
              color: Tokens.text.primary
              font.pixelSize: Style.font.bodySmall
              font.family: Style.font.family
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
