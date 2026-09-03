import QtQuick

Item {
  id: root

  property real minimum: 0
  property real maximum: 100
  property real step: 1
  property bool integer: false
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
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
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
  }
}
