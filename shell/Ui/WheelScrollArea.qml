import QtQuick

// Configurable mouse wheel scroll speed for Qt Quick lists.
//
// A Qt Quick ListView/GridView (both Flickable) scroll by a small fixed amount
// per wheel tick, with no external way to configure it, which feels slow on
// long lists. This transparent MouseArea sits ON TOP of the list — after it in
// the stacking order — so it captures the wheel before the Flickable does, and
// scrolls the target manually at a configurable speed. Place it after the list,
// inside the same parent Item, e.g.:
//
//   WheelScrollArea { flickable: myList }
//
// speed is the divisor of the visible height used as the step: the larger it
// is, the slower each wheel click scrolls.
MouseArea {
  id: root

  required property Flickable flickable
  property real speed: 8

  anchors.fill: parent
  acceptedButtons: Qt.NoButton

  onWheel: function(wheel) {
    if (wheel.angleDelta.y === 0) return
    if (root.flickable.contentHeight <= root.flickable.height) return
    var step = root.flickable.height / root.speed
    root.flickable.contentY = Math.max(0, Math.min(
      root.flickable.contentY - wheel.angleDelta.y / 120.0 * step,
      root.flickable.contentHeight - root.flickable.height))
    wheel.accepted = true
  }
}