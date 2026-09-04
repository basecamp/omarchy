import QtQuick

Item {
  id: root

  property real minimum: 0
  property real maximum: 100
  property real step: 1
  property bool integer: false
  property int tickCount: 0
  property real value: minimum
  property color trackColor: "#444"
  property color fillColor: Color.accent
  property color knobColor: Color.foreground
  property color tickColor: Color.background
  readonly property bool dragging: pointer.pressed
  readonly property real liveValue: pointer.pressed ? valueAt(pointer.mouseX) : value
  signal moved(real nextValue)
  signal released(real nextValue)
  signal rightClicked()

  implicitWidth: 120
  implicitHeight: 20

  function valueAt(position) {
    var raw = minimum + position / Math.max(1, width) * (maximum - minimum)
    var stepped = Math.round(raw / Math.max(step, 0.000001)) * step
    var bounded = Math.max(minimum, Math.min(maximum, stepped))
    return integer ? Math.round(bounded) : bounded
  }

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: 4
    radius: 2
    color: root.trackColor
  }
  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width * Math.max(0, Math.min(1,
      (root.liveValue - root.minimum) / Math.max(1, root.maximum - root.minimum)))
    height: 4
    radius: 2
    color: root.fillColor
  }
  Repeater {
    model: root.tickCount > 1 ? root.tickCount : 0
    Rectangle {
      required property int index
      x: parent.width * index / Math.max(1, root.tickCount - 1)
      anchors.verticalCenter: parent.verticalCenter
      width: 1
      height: 8
      color: root.tickColor
    }
  }
  Rectangle {
    x: Math.max(0, Math.min(parent.width - width,
      parent.width * (root.liveValue - root.minimum)
      / Math.max(1, root.maximum - root.minimum) - width / 2))
    anchors.verticalCenter: parent.verticalCenter
    width: 12
    height: 12
    radius: 6
    color: root.knobColor
  }
  MouseArea {
    id: pointer
    objectName: "mouseArea"
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPressed: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        root.rightClicked()
        return
      }
      root.moved(root.valueAt(mouse.x))
    }
    onPositionChanged: function(mouse) {
      if (pressed && pressedButtons & Qt.LeftButton) root.moved(root.valueAt(mouse.x))
    }
    onReleased: function(mouse) {
      if (mouse.button === Qt.LeftButton) root.released(root.valueAt(mouse.x))
    }
    onWheel: function(wheel) {
      var next = Math.max(root.minimum, Math.min(root.maximum,
        root.value + (wheel.angleDelta.y > 0 ? root.step : -root.step)))
      if (root.integer) next = Math.round(next)
      root.moved(next)
      root.released(next)
      wheel.accepted = true
    }
  }
}
