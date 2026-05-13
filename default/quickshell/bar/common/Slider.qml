import QtQuick

Item {
  id: root

  property QtObject bar: null
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  property bool integer: false
  property color trackColor: bar ? Qt.rgba(bar.foreground.r, bar.foreground.g, bar.foreground.b, 0.18) : "#333"
  property color fillColor: bar ? bar.foreground : "#cacccc"
  property color knobColor: bar ? bar.foreground : "#cacccc"
  property bool dragging: false
  property real trackHeight: 4

  signal moved(real value)
  signal released(real value)

  implicitWidth: 200
  implicitHeight: 22

  readonly property real range: Math.max(0.0001, maximum - minimum)
  readonly property real progress: Math.max(0, Math.min(1, (value - minimum) / range))

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.right: parent.right
    height: root.trackHeight
    radius: height / 2
    color: root.trackColor
  }

  Rectangle {
    id: fill
    anchors.verticalCenter: track.verticalCenter
    anchors.left: track.left
    height: track.height
    radius: track.radius
    color: root.fillColor
    width: track.width * root.progress

    Behavior on width {
      enabled: !root.dragging
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
  }

  Rectangle {
    id: knob
    width: 14
    height: 14
    radius: 7
    color: root.knobColor
    border.color: root.bar ? root.bar.background : "#101315"
    border.width: 2
    anchors.verticalCenter: track.verticalCenter
    x: Math.max(0, Math.min(track.width - width, track.width * root.progress - width / 2))
    scale: mouseArea.containsMouse || root.dragging ? 1.15 : 1.0

    Behavior on x {
      enabled: !root.dragging
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Behavior on scale {
      NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton

    function valueFromX(x) {
      var clamped = Math.max(0, Math.min(track.width, x))
      var raw = root.minimum + (clamped / track.width) * root.range
      if (root.integer) raw = Math.round(raw)
      return Math.max(root.minimum, Math.min(root.maximum, raw))
    }

    onPressed: function(mouse) {
      root.dragging = true
      var next = valueFromX(mouse.x)
      root.value = next
      root.moved(next)
    }
    onPositionChanged: function(mouse) {
      if (!root.dragging) return
      var next = valueFromX(mouse.x)
      root.value = next
      root.moved(next)
    }
    onReleased: function(mouse) {
      root.dragging = false
      root.released(root.value)
    }
    onWheel: function(wheel) {
      var delta = wheel.angleDelta.y > 0 ? root.step : -root.step
      var next = Math.max(root.minimum, Math.min(root.maximum, root.value + delta))
      if (root.integer) next = Math.round(next)
      root.value = next
      root.moved(next)
      root.released(next)
    }
  }
}
