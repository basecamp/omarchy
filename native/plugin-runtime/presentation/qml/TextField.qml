import QtQuick

FocusScope {
  id: root

  property alias text: editor.text
  property alias placeholderText: placeholder.text
  property alias maximumLength: editor.maximumLength
  property color foreground: Color.foreground
  property color accent: Color.accent
  signal textEdited()
  signal accepted()

  implicitWidth: 240
  implicitHeight: 36

  function clear() { editor.clear() }
  function selectAll() { editor.selectAll() }

  Rectangle {
    anchors.fill: parent
    radius: 6
    color: Color.alpha(root.foreground, 0.06)
    border.color: root.activeFocus ? root.accent : Color.alpha(root.foreground, 0.18)
    border.width: 1
  }
  Text {
    id: placeholder
    anchors.left: parent.left
    anchors.leftMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    visible: editor.text.length === 0 && !editor.activeFocus
    color: Color.alpha(root.foreground, 0.55)
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
    textFormat: Text.PlainText
  }
  TextInput {
    id: editor
    anchors.fill: parent
    anchors.leftMargin: 10
    anchors.rightMargin: 10
    verticalAlignment: TextInput.AlignVCenter
    color: root.foreground
    selectionColor: root.accent
    selectedTextColor: Color.background
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
    focus: root.activeFocus
    onTextEdited: root.textEdited()
    Keys.onReturnPressed: root.accepted()
    Keys.onEnterPressed: root.accepted()
  }
  MouseArea {
    anchors.fill: parent
    visible: !editor.activeFocus
    cursorShape: Qt.IBeamCursor
    onPressed: function(mouse) {
      editor.forceActiveFocus()
      editor.cursorPosition = editor.positionAt(mouse.x - editor.x)
    }
  }
}
