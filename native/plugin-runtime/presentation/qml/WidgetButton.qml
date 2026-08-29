import QtQuick

Item {
  property var bar: null
  property bool labelVisible: false
  property bool hasVisualContent: false
  property bool dimmed: false
  property string tooltipText: ""
  property real fixedWidth: -1
  property real fixedHeight: -1
  property real scaledHorizontalMargin: Style.space(6)
  property real scaledVerticalPadding: Style.space(4)
  property color foreground: Color.foreground
  signal pressed(int buttonCode)

  opacity: dimmed ? 0.5 : 1
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onPressed: mouse => parent.pressed(mouse.button)
  }
}
