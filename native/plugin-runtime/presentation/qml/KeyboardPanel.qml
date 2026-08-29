import QtQuick
Rectangle {
  property Item anchorItem
  property Item owner
  property var bar: null
  property bool open: false
  property Item focusTarget
  property real contentWidth: 0
  property real contentHeight: 0
  property real padding: 0
  visible: open
  width: contentWidth
  height: contentHeight
  color: "#151820"
  function fittedContentWidth(value) { return value }
  function fittedContentHeight(value, maximum) { return Math.min(value, maximum) }
}
