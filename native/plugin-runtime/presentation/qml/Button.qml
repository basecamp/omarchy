import QtQuick

Rectangle {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property bool selected: false
  property bool active: false
  property bool focusable: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property int fontSize: 14
  signal clicked()

  implicitWidth: Math.max(32, label.implicitWidth + 20)
  implicitHeight: 32
  radius: 6
  color: selected || active ? Style.selectedFillFor(foreground, accent)
    : (pointer.containsMouse ? Style.hoverFillFor(foreground, accent) : "transparent")
  opacity: enabled ? 1 : 0.45
  activeFocusOnTab: focusable

  Text {
    id: label
    anchors.centerIn: parent
    text: root.iconText || root.text
    color: root.foreground
    font.family: Style.font.menuFamily
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
