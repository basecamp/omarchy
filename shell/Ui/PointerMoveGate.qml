import QtQuick

// Filters synthetic hover churn from moving delegates under a stationary
// pointer. Call reset() after keyboard/list mutations, then moved() from a
// row MouseArea's onPositionChanged before changing cursor selection.
QtObject {
  id: root

  property Item referenceItem: null
  property real threshold: 1
  property bool primed: false
  property real lastX: 0
  property real lastY: 0

  function reset() {
    root.primed = false
    root.lastX = 0
    root.lastY = 0
  }

  function moved(item, mouse) {
    if (!item || !mouse) {
      root.reset()
      return false
    }

    var target = root.referenceItem || item
    var point = item.mapToItem(target, mouse.x, mouse.y)
    var didMove = root.primed
      && (Math.abs(point.x - root.lastX) > root.threshold || Math.abs(point.y - root.lastY) > root.threshold)

    root.lastX = point.x
    root.lastY = point.y
    root.primed = true

    return didMove
  }
}
