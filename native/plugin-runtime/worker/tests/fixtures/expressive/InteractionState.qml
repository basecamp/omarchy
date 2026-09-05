import QtQuick

FocusScope {
  id: root

  width: 64
  height: 32
  objectName: "focused=" + editor.activeFocus + ";keys=" + editor.keyPresses
              + ";text=" + editor.text + ";drag=" + dragArea.stage

  TextInput {
    id: editor

    width: parent.width
    height: parent.height / 2
    focus: true
    property int keyPresses: 0

    Keys.onPressed: function(event) {
      keyPresses += 1
      event.accepted = true
    }
  }

  MouseArea {
    id: dragArea

    y: parent.height / 2
    width: parent.width
    height: parent.height / 2
    property int stage: 0

    onPressed: stage = 1
    onPositionChanged: {
      if (pressed)
        stage = 2
    }
    onReleased: stage = stage === 2 ? 3 : 90
    onCanceled: stage = 4
  }
}
