import QtQuick
import QtQuick.Controls as QQC
import qs.Commons

Column {
  id: root

  property string label: ""
  property int value: 0
  property int from: 0
  property int to: 100
  property int stepSize: 1
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: "JetBrainsMono Nerd Font"
  property real fontSize: 12
  property real fieldWidth: 120
  property bool hasCursor: false
  property alias field: spin

  signal modified(int value)
  signal hovered(bool on)

  spacing: 6

  Text {
    visible: root.label !== ""
    text: root.label
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: 11
  }

  QQC.SpinBox {
    id: spin
    width: root.fieldWidth
    from: root.from
    to: root.to
    stepSize: root.stepSize
    value: root.value
    editable: true
    font.family: root.fontFamily
    font.pixelSize: root.fontSize

    onValueModified: root.modified(value)

    background: Rectangle {
      readonly property bool _hot: spin.activeFocus || (root.hasCursor && !spin.activeFocus)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, _hot ? 0.10 : 0.05)
      border.color: _hot
        ? Style.focusBorderColor
        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3)
      border.width: _hot ? Style.focusBorderWidth : 1
      radius: Style.cornerRadius

      HoverHandler {
        onHoveredChanged: root.hovered(hovered)
      }
    }

    contentItem: TextInput {
      text: spin.displayText
      font: spin.font
      color: root.foreground
      selectionColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
      selectedTextColor: root.foreground
      horizontalAlignment: Qt.AlignHCenter
      verticalAlignment: Qt.AlignVCenter
      readOnly: !spin.editable
      validator: spin.validator
      inputMethodHints: Qt.ImhFormattedNumbersOnly
    }
  }
}
