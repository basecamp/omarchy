import QtQuick

Rectangle {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property bool selected: false
  property bool active: false
  property bool focusable: false
  property bool bordered: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color hoverColor: accent
  property string fontFamily: Style.font.menuFamily
  property int fontSize: 14
  property real verticalPadding: 0
  signal clicked()

  implicitWidth: Math.max(32, label.implicitWidth + 20)
  implicitHeight: Math.max(32, label.implicitHeight + verticalPadding * 2)
  radius: 6
  color: selected || active ? Style.selectedFillFor(foreground, accent)
    : (pointer.containsMouse ? Style.hoverFillFor(foreground, hoverColor) : "transparent")
  border.color: bordered ? Color.alpha(foreground, 0.18) : "transparent"
  border.width: bordered ? 1 : 0
  opacity: enabled ? 1 : 0.45
  activeFocusOnTab: focusable

  Text {
    id: label
    anchors.centerIn: parent
    text: root.iconText || root.text
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    textFormat: Text.PlainText
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    onClicked: {
      if (root.focusable) root.forceActiveFocus()
      root.clicked()
    }
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        || event.key === Qt.Key_Space) {
      root.clicked()
      event.accepted = true
    }
  }

  ToolTip {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.top
    anchors.bottomMargin: 6
    text: root.tooltipText
    shown: pointer.containsMouse
  }
}
