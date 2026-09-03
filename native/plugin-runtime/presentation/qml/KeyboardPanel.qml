import QtQuick

Item {
  property var anchorItem: null
  property var owner: null
  property var bar: null
  property bool open: true
  property var focusTarget: null
  property real contentWidth: 430
  property real contentHeight: 680

  visible: open
  width: contentWidth
  height: contentHeight
  anchors.centerIn: parent

  function fittedContentWidth(value) {
    return Math.min(parent ? parent.width : value, value)
  }

  function fittedContentHeight(value, maximum) {
    return Math.min(parent ? parent.height : maximum, Math.min(value, maximum))
  }

  onVisibleChanged: {
    if (visible && focusTarget) Qt.callLater(function() { focusTarget.forceActiveFocus() })
  }
}
