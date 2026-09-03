import QtQuick

Rectangle {
  property var borderSpec: ({color: "transparent", width: 0})
  readonly property real borderLeft: border.width
  readonly property real borderRight: border.width
  readonly property real borderBottom: border.width
  border.color: borderSpec.color || "transparent"
  border.width: Number(borderSpec.width || 0)
}
