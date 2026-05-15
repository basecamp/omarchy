import QtQuick

Item {
  id: root

  property var bar: null
  property string text: ""
  property string fontFamily: bar ? bar.fontFamily : "JetBrainsMono Nerd Font"
  property real fontSize: 12
  property color foreground: bar ? bar.foreground : "#cacccc"
  property color activeColor: bar ? bar.urgent : "#a55555"
  property bool active: false
  property real horizontalMargin: 8.5
  property real verticalPadding: 6
  property real fixedWidth: -1
  property real fixedHeight: -1
  property real textRotation: 0
  property bool keepSpace: false
  property string tooltipText: ""
  property real hoverScale: 1.0
  property real pressScale: 0.92

  signal pressed(int button)
  signal wheelMoved(int delta)

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : 26

  visible: text !== "" || keepSpace
  opacity: text === "" ? 0 : 1
  implicitWidth: fixedWidth > 0 ? fixedWidth : (vertical ? barSize : Math.max(12, label.implicitWidth + horizontalMargin * 2))
  implicitHeight: fixedHeight > 0 ? fixedHeight : (vertical ? Math.max(12, label.implicitHeight + verticalPadding * 2) : barSize)

  Behavior on opacity {
    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: root.active ? root.activeColor : root.foreground
    font.family: root.fontFamily
    font.pointSize: root.fontSize * 0.75
    renderType: Text.NativeRendering
    rotation: root.textRotation
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    scale: mouseArea.pressed ? root.pressScale : (mouseArea.containsMouse ? root.hoverScale : 1.0)

    Behavior on color {
      ColorAnimation { duration: 160 }
    }

    Behavior on scale {
      NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipText)
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: function(mouse) {
      if (root.bar) root.bar.hideTooltip(root)
      root.pressed(mouse.button)
    }
    onWheel: function(wheel) { root.wheelMoved(wheel.angleDelta.y) }
  }
}
