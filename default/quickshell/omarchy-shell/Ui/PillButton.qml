import QtQuick
import QtQuick.Controls
import qs.Commons

Rectangle {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property color foreground: "#cacccc"
  property color background: "transparent"
  property color hoverBackground: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  property color pressedBackground: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.22)
  property color tooltipBackground: "#101315"
  property color tooltipForeground: foreground
  property string fontFamily: "JetBrainsMono Nerd Font"
  property real fontSize: 12
  property real iconSize: 14
  property real horizontalPadding: 10
  property real verticalPadding: 6
  property bool active: false
  property bool leftAlign: false
  property color activeBackground: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)

  // Keyboard cursor flag. When true, the pill renders the same fill + border
  // as a mouse hover — so j/k navigation and pointer hover are visually
  // indistinguishable. Default false; bind from a panel's cursor state.
  property bool hasCursor: false

  ToolTip {
    visible: root.tooltipText !== "" && mouseArea.containsMouse
    text: root.tooltipText
    delay: 400
    padding: 0

    background: Rectangle {
      color: root.tooltipBackground
      border.color: root.tooltipForeground
      border.width: 1
      radius: 0
      opacity: 0.97
    }

    contentItem: Text {
      text: root.tooltipText
      color: root.tooltipForeground
      font.family: root.fontFamily
      font.pixelSize: 11
      leftPadding: 10
      rightPadding: 10
      topPadding: 6
      bottomPadding: 6
    }
  }

  signal clicked()
  signal rightClicked()

  implicitWidth: row.implicitWidth + horizontalPadding * 2
  implicitHeight: row.implicitHeight + verticalPadding * 2
  radius: Style.cornerRadius

  // Hot = mouse hover OR keyboard cursor. Pressed wins over both; otherwise
  // hot beats `active` (so a cursor on an already-active pill still reads
  // as hovered, matching CursorSurface's behaviour for navigable rows).
  readonly property bool hot: mouseArea.containsMouse || hasCursor

  color: mouseArea.pressed ? pressedBackground
    : hot ? hoverBackground
    : (active ? activeBackground : background)
  border.width: hot ? 1 : 0
  border.color: foreground

  Behavior on color {
    ColorAnimation { duration: 120 }
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: root.leftAlign ? parent.left : undefined
    anchors.leftMargin: root.leftAlign ? root.horizontalPadding : 0
    anchors.horizontalCenter: root.leftAlign ? undefined : parent.horizontalCenter
    spacing: 8

    Text {
      visible: root.iconText !== ""
      text: root.iconText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.iconSize
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      visible: root.text !== ""
      text: root.text
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.rightClicked()
      else root.clicked()
    }
  }
}
