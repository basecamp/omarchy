import QtQuick

Item {
  id: root

  required property Flickable flickable
  property color color: Color.alpha(Color.foreground, 0.38)
  property real minimumThumbHeight: 24
  property real dragOffset: 0

  visible: flickable.contentHeight > flickable.height
  width: 6

  Rectangle {
    id: thumb
    width: parent.width
    height: Math.max(root.minimumThumbHeight,
      root.height * root.flickable.height / Math.max(1, root.flickable.contentHeight))
    y: (root.height - height) * root.flickable.contentY
      / Math.max(1, root.flickable.contentHeight - root.flickable.height)
    radius: width / 2
    color: root.color
  }

  MouseArea {
    anchors.fill: parent
    onPressed: function(mouse) {
      root.dragOffset = mouse.y >= thumb.y && mouse.y <= thumb.y + thumb.height
        ? mouse.y - thumb.y : thumb.height / 2
      updatePosition(mouse.y)
    }
    onPositionChanged: function(mouse) {
      if (pressed) updatePosition(mouse.y)
    }
    function updatePosition(position) {
      var travel = Math.max(1, height - thumb.height)
      var ratio = Math.max(0, Math.min(1, (position - root.dragOffset) / travel))
      root.flickable.contentY = ratio * Math.max(0,
        root.flickable.contentHeight - root.flickable.height)
    }
  }
}
