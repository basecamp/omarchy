import QtQuick

Rectangle {
  id: root

  property bool opened: false
  property string message: ""
  property string confirmText: "Confirm"
  signal confirmed()
  signal canceled()

  visible: opened
  z: 1000
  color: Color.alpha(Color.background, 0.9)

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - 32, 340)
    height: content.implicitHeight + 28
    radius: Style.cornerRadius
    color: Color.popups.background
    border.width: 1
    border.color: Color.alpha(Color.foreground, 0.18)

    Column {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: 14
      anchors.verticalCenter: parent.verticalCenter
      spacing: 12

      Text {
        width: parent.width
        text: root.message
        color: Color.foreground
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
      }

      Row {
        anchors.right: parent.right
        spacing: 8
        Button { text: "Cancel"; onClicked: root.canceled() }
        Button { text: root.confirmText; onClicked: root.confirmed() }
      }
    }
  }
}
