import QtQuick

Rectangle {
  property var anchorItem: null
  property var owner: null
  property var bar: null
  property bool open: true
  property var focusTarget: null
  property real contentWidth: 430
  property real contentHeight: 680
  property real padding: 0

  visible: open
  width: contentWidth
  height: contentHeight
  anchors.top: Style.bar.position !== "bottom"
  anchors.bottom: Style.bar.position === "bottom"
  anchors.left: Style.bar.position === "left"
  anchors.right: Style.bar.position !== "left"
  color: Color.popups.background

  function fittedContentWidth(value) {
    return Math.min(parent ? parent.width : value, value)
  }

  function fittedContentHeight(value, maximum) {
    var limit = maximum === undefined ? value : maximum
    return Math.min(parent ? parent.height : limit, Math.min(value, limit))
  }

  onVisibleChanged: {
    if (visible && focusTarget) Qt.callLater(function() { focusTarget.forceActiveFocus() })
  }
}
