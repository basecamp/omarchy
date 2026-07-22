import QtQuick

// Filters synthetic hover churn from moving delegates under a stationary
// pointer. Call reset() after keyboard/list mutations, then moved() from a
// row MouseArea's onPositionChanged before changing cursor selection. A
// transition known to originate from the pointer can call allowInitialSample()
// so the item under the stationary pointer remains selected.
QtObject {
  id: root

  property Item referenceItem: null
  property real threshold: 1
  property bool primed: false
  property bool initialSampleAllowed: false
  property real lastX: 0
  property real lastY: 0

  function reset() {
    root.primed = false
    root.initialSampleAllowed = false
    root.lastX = 0
    root.lastY = 0
  }

  function allowInitialSample() {
    root.reset()
    root.initialSampleAllowed = true
  }

  function moved(item, mouse) {
    if (!item || !mouse) {
      root.reset()
      return false
    }

    var target = root.referenceItem || item
    var point = item.mapToItem(target, mouse.x, mouse.y)
    var firstSample = !root.primed
    var didMove = !firstSample
      ? Math.abs(point.x - root.lastX) > root.threshold || Math.abs(point.y - root.lastY) > root.threshold
      : root.initialSampleAllowed

    // Keep the previous accepted position while filtering jitter so slow,
    // sub-threshold steps accumulate into deliberate pointer movement.
    if (firstSample || didMove) {
      root.lastX = point.x
      root.lastY = point.y
    }
    root.primed = true
    root.initialSampleAllowed = false

    return didMove
  }
}
