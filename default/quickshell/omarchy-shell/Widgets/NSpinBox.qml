import QtQuick
import QtQuick.Controls
import qs.Commons

SpinBox {
  id: root
  property string label: ""
  font.family: "JetBrainsMono Nerd Font"
  font.pixelSize: Style.fontSizeS
  editable: true
  implicitHeight: 32
  leftPadding: 10
  rightPadding: 24
  topPadding: 4
  bottomPadding: 4

  background: Rectangle {
    color: Color.mSurfaceVariant
    border.color: root.activeFocus ? Color.mPrimary : Color.mOutline
    border.width: Style.borderS
    radius: Style.radiusS
  }

  contentItem: TextInput {
    text: root.displayText
    font: root.font
    color: Color.mOnSurface
    selectionColor: Qt.rgba(Color.mOnSurface.r, Color.mOnSurface.g, Color.mOnSurface.b, 0.35)
    selectedTextColor: Color.mOnSurface
    horizontalAlignment: Qt.AlignLeft
    verticalAlignment: Qt.AlignVCenter
    readOnly: !root.editable
    validator: root.validator
    inputMethodHints: Qt.ImhFormattedNumbersOnly
  }

  up.indicator: Rectangle {
    x: root.mirrored ? 0 : root.width - width
    width: 20
    height: root.height / 2
    color: root.up.pressed
      ? Qt.rgba(Color.mOnSurface.r, Color.mOnSurface.g, Color.mOnSurface.b, 0.16)
      : root.up.hovered
        ? Qt.rgba(Color.mOnSurface.r, Color.mOnSurface.g, Color.mOnSurface.b, 0.08)
        : "transparent"
    radius: Style.radiusS
    Text {
      anchors.centerIn: parent
      text: "▲"
      font.family: root.font.family
      font.pixelSize: 7
      color: root.up.hovered ? Color.mOnSurface : Color.mOnSurfaceVariant
    }
  }

  down.indicator: Rectangle {
    x: root.mirrored ? 0 : root.width - width
    y: root.height / 2
    width: 20
    height: root.height / 2
    color: root.down.pressed
      ? Qt.rgba(Color.mOnSurface.r, Color.mOnSurface.g, Color.mOnSurface.b, 0.16)
      : root.down.hovered
        ? Qt.rgba(Color.mOnSurface.r, Color.mOnSurface.g, Color.mOnSurface.b, 0.08)
        : "transparent"
    radius: Style.radiusS
    Text {
      anchors.centerIn: parent
      text: "▼"
      font.family: root.font.family
      font.pixelSize: 7
      color: root.down.hovered ? Color.mOnSurface : Color.mOnSurfaceVariant
    }
  }
}
