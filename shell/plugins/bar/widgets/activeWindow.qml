import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "activeWindow"
  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property var toplevel: ToplevelManager.activeToplevel
  readonly property string title: toplevel ? (toplevel.title || toplevel.appId || "") : ""
  readonly property int maxLabelWidth: Number(setting("maxWidth", 280))

  readonly property bool vertical: bar ? bar.vertical : false

  visible: title !== "" && !vertical
  implicitWidth: visible ? Math.min(maxLabelWidth, labelText.implicitWidth) + 16 : 0
  implicitHeight: bar ? bar.barSize : 26

  Behavior on implicitWidth {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  Item {
    anchors.fill: parent
    anchors.leftMargin: 8
    anchors.rightMargin: 8
    clip: true

    Text {
      id: labelText
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      width: parent.width
      text: root.title
      color: root.bar ? root.bar.foreground : "#cacccc"
      font.family: root.bar ? root.bar.fontFamily : "JetBrainsMono Nerd Font"
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      opacity: 0.85
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) {
      if (!root.toplevel) return
      if (mouse.button === Qt.MiddleButton) {
        root.toplevel.close()
      } else if (mouse.button === Qt.RightButton) {
        root.toplevel.close()
      } else {
        root.toplevel.activate()
      }
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.title)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
