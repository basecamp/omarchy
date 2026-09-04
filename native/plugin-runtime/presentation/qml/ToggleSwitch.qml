import QtQuick

Rectangle {
  id: root

  property bool checked: false
  property bool busy: false
  property color foreground: Color.foreground
  property color checkedColor: "#65d7a1"
  property color uncheckedColor: "#354052"
  signal toggled()

  implicitWidth: 34
  implicitHeight: 18
  radius: height / 2
  color: checked ? checkedColor : uncheckedColor

  Rectangle {
    width: 14
    height: 14
    radius: width / 2
    y: (parent.height - height) / 2
    x: root.checked ? root.width - width - 2 : 2
    color: "white"
  }

  MouseArea {
    anchors.fill: parent
    enabled: !root.busy
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled()
  }
}
