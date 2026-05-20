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
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real fieldWidth: Style.spacing.numberFieldWidth
  property bool hasCursor: false
  property bool _hovered: false
  property alias field: spin

  signal modified(int value)
  signal hovered(bool on)

  spacing: Style.spacing.md

  Text {
    visible: root.label !== ""
    text: root.label
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  QQC.SpinBox {
    id: spin
    width: root.fieldWidth
    implicitHeight: Math.max(Style.spacing.controlHeight, root.fontSize + Style.spacing.controlPaddingY * 2)
    from: root.from
    to: root.to
    stepSize: root.stepSize
    value: root.value
    editable: true
    font.family: root.fontFamily
    font.pixelSize: root.fontSize

    onValueModified: root.modified(value)

    background: Rectangle {
      readonly property bool _focused: spin.activeFocus
      readonly property bool _hot: root._hovered || root.hasCursor

      color: Style.controlFill(_focused, _hot, root.foreground, root.accent)
      border.color: Style.controlBorder(_focused, _hot, root.foreground, root.accent)
      border.width: Style.controlBorderWidth(_focused, _hot)
      radius: Style.cornerRadius

      HoverHandler {
        onHoveredChanged: {
          root._hovered = hovered
          root.hovered(hovered)
        }
      }
    }

    contentItem: TextInput {
      text: spin.displayText
      font: spin.font
      color: root.foreground
      selectionColor: Style.selectionFillFor(root.foreground, root.accent)
      selectedTextColor: root.foreground
      horizontalAlignment: Qt.AlignHCenter
      verticalAlignment: Qt.AlignVCenter
      readOnly: !spin.editable
      validator: spin.validator
      inputMethodHints: Qt.ImhFormattedNumbersOnly
    }
  }
}
