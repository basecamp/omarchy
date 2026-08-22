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
  property string pendingActivate: ""

  readonly property var windowService: shell ? shell.windowService : null
  readonly property var cycleList: windowService ? windowService.cycleList : []
  readonly property int cycleIndex: windowService ? windowService.cycleIndex : 0

  Timer {
    id: activateAfterHide
    interval: 16
    repeat: false
    onTriggered: {
      var target = root.pendingActivate
      root.pendingActivate = ""
      if (target && windowService && typeof windowService.activateFromSwitcher === "function")
        windowService.activateFromSwitcher(target)
    }
  }

  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    root.opened = false
    // pick() stashes pendingActivate then hide() invokes close(). Do not
    // cancel that commit; dismiss-without-pick leaves pendingActivate empty.
    if (root.pendingActivate !== "")
      return
    activateAfterHide.stop()
    if (windowService && typeof windowService.cancelCycle === "function")
      windowService.cancelCycle()
  }

  function pick(address) {
    root.pendingActivate = String(address || "")
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide("omarchy.ultimate-task-switcher")
    activateAfterHide.restart()
  }

  PanelWindow {
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // Quickshell only maps a layer surface when it is anchored to screen
    // edges. implicitWidth/Height alone never produced omarchy-task-switcher.
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "omarchy-task-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // Keyboard Alt+Tab is WindowService IPC, not this surface. Taking
    // OnDemand/Exclusive focus makes unmap restore the previous window and
    // undo the card pick (painted-card click with no address change).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      anchors.centerIn: parent
      width: Math.min(parent.width - 32, 120 * Math.max(1, cycleList.length) + 40)
      height: 160
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
            width: 120
            height: 120
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
                var title = windowService ? windowService.windowTitle(modelData) : String(modelData)
                if (windowService && typeof windowService.isMinimized === "function" && windowService.isMinimized(modelData))
                  return title + "\nminimized"
                return title
              }
              color: Tokens.text.primary
              font.pixelSize: Style.font.bodySmall
              font.family: "sans-serif"
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.pick(String(modelData || ""))
            }
          }
        }
      }
    }
  }
}
