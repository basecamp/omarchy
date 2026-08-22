import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: true

  readonly property var windowService: shell ? shell.windowService : null
  readonly property var modeProfile: shell ? shell.modeProfileService : null
  readonly property bool enabled: modeProfile ? modeProfile.feature("floatingWindows") : true
  readonly property int barHeight: windowService ? windowService.captionHeight : 28

  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    root.opened = true
  }

  Variants {
    model: windowService ? windowService.windows : []
    delegate: Component {
      PanelWindow {
        id: caption
        required property var modelData

        readonly property string address: String((modelData && modelData.address) || "")
        readonly property int winX: Number((modelData && modelData.x) || 0)
        readonly property int winY: Number((modelData && modelData.y) || 0)
        readonly property int winW: Number((modelData && modelData.width) || 0)
        readonly property bool parked: !!(modelData && modelData.minimized)
        readonly property bool fullscreen: Number((modelData && modelData.fullscreen) || 0) === 2
        readonly property bool maximized: Number((modelData && modelData.fullscreen) || 0) === 1
        readonly property bool shown: root.enabled && root.opened && address !== "" && modelData && modelData.mapped !== false && !parked && !fullscreen && winW >= 64

        property bool dragging: false
        property int dragX: 0
        property int dragY: 0
        property int originX: 0
        property int originY: 0
        property real grabGX: 0
        property real grabGY: 0

        visible: shown
        screen: {
          var name = modelData && modelData.monitorName
          var screens = Quickshell.screens
          if (name) {
            for (var i = 0; i < screens.length; i++) {
              if (String(screens[i].name || "") === String(name))
                return screens[i]
            }
          }
          return screens[0]
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: Math.max(64, winW)
        implicitHeight: root.barHeight
        margins.left: dragging ? dragX : winX
        margins.top: dragging ? dragY : winY
        anchors.left: true
        anchors.top: true
        WlrLayershell.namespace: "omarchy-window-chrome"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
          anchors.fill: parent
          color: Tokens.surface.glass
          border.color: windowService && windowService.isActive(caption.address) ? Tokens.accent.primary : Tokens.border.subtle
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 2
            spacing: 2

            Text {
              id: titleText
              Layout.fillWidth: true
              Layout.fillHeight: true
              verticalAlignment: Text.AlignVCenter
              text: String((modelData && modelData.title) || "")
              color: Tokens.text.primary
              font.pixelSize: Style.font.bodySmall
              font.family: "sans-serif"
              elide: Text.ElideRight

              MouseArea {
                id: dragArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SizeAllCursor
                onPressed: function(mouse) {
                  var g = dragArea.mapToItem(null, mouse.x, mouse.y)
                  caption.grabGX = g.x
                  caption.grabGY = g.y
                  caption.originX = caption.winX
                  caption.originY = caption.winY
                  caption.dragX = caption.winX
                  caption.dragY = caption.winY
                  caption.dragging = true
                  if (windowService) windowService.focus(caption.address)
                }
                onPositionChanged: function(mouse) {
                  if (!caption.dragging || !windowService) return
                  var g = dragArea.mapToItem(null, mouse.x, mouse.y)
                  caption.dragX = caption.originX + Math.round(g.x - caption.grabGX)
                  caption.dragY = caption.originY + Math.round(g.y - caption.grabGY)
                  windowService.moveTo(caption.address, caption.dragX, caption.dragY)
                }
                onReleased: caption.dragging = false
                onCanceled: caption.dragging = false
                onDoubleClicked: {
                  if (windowService) windowService.toggleMaximize(caption.address)
                }
              }
            }

            IconButton {
              Layout.preferredWidth: root.barHeight - 2
              Layout.preferredHeight: root.barHeight - 2
              size: root.barHeight - 2
              bordered: true
              iconText: "\u2013"
              tooltipText: "Minimize"
              onClicked: { if (windowService) windowService.minimize(caption.address) }
            }
            IconButton {
              Layout.preferredWidth: root.barHeight - 2
              Layout.preferredHeight: root.barHeight - 2
              size: root.barHeight - 2
              bordered: true
              iconText: caption.maximized ? "\u239A" : "\u25A1"
              tooltipText: caption.maximized ? "Restore" : "Maximize"
              onClicked: { if (windowService) windowService.toggleMaximize(caption.address) }
            }
            IconButton {
              Layout.preferredWidth: root.barHeight - 2
              Layout.preferredHeight: root.barHeight - 2
              size: root.barHeight - 2
              bordered: true
              iconText: "\u00D7"
              tooltipText: "Close"
              danger: true
              onClicked: { if (windowService) windowService.close(caption.address) }
            }
          }
        }
      }
    }
  }
}
