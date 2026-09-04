import QtQuick
import qs.Commons
import "Model.js" as Model

// One vertical fill bar per logical core. Wraps into as many rows as it takes
// to keep each bar wide enough to read — a 32-thread desktop gets two rows of
// sixteen rather than thirty-two two-pixel slivers.
Item {
  id: root

  // Dimming has to know what it is dimming *against*. dim() only reads as
  // "less prominent" on a dark ground; on a light theme it makes secondary text
  // darker — and therefore louder — than the primary text it sits behind. This
  // moves toward the background either way.
  readonly property bool groundIsDark: Model.groundIsDark(root.ground)
  function dim(c, amount) { return Model.dim(root.ground, c, amount) }

  // The surface this sits on, so dim() knows which way to move.
  property color ground: Color.popups.background

  property var cores: []
  property color foreground: Color.foreground
  property color fill: foreground
  // Cores at or above this are tinted urgent, so a pegged thread is findable
  // at a glance without reading any number.
  property real hotThreshold: 85
  property color hotColor: Color.urgent
  property real minBarWidth: Style.space(7)
  property real gap: Style.space(2)
  property real rowHeight: Style.space(26)

  readonly property int count: (cores || []).length
  readonly property int columns: {
    if (count === 0 || width <= 0) return 1
    var fits = Math.floor((width + gap) / (minBarWidth + gap))
    return Math.max(1, Math.min(count, fits))
  }
  readonly property int rows: count > 0 ? Math.ceil(count / columns) : 0

  implicitHeight: rows > 0 ? rows * rowHeight + (rows - 1) * gap : 0

  Column {
    anchors.fill: parent
    spacing: root.gap

    Repeater {
      model: root.rows

      Row {
        id: coreRow
        required property int index
        width: parent.width
        height: root.rowHeight
        spacing: root.gap

        readonly property int firstCore: index * root.columns
        readonly property real barWidth: root.columns > 0
          ? (width - root.gap * (root.columns - 1)) / root.columns
          : 0

        Repeater {
          model: root.columns

          Item {
            required property int index
            readonly property int coreIndex: coreRow.firstCore + index
            readonly property real usage: coreIndex < root.count
              ? Math.min(100, Math.max(0, Number(root.cores[coreIndex]) || 0))
              : -1

            width: coreRow.barWidth
            height: coreRow.height
            // The last row is usually short; empty slots keep the remaining
            // bars aligned under the row above instead of stretching.
            visible: usage >= 0

            // Faint enough that a mostly-idle machine reads as a row of quiet
            // marks rather than a row of empty tanks demanding to be filled.
            Rectangle {
              anchors.fill: parent
              radius: Style.space(2)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              radius: Style.space(2)
              height: Math.max(Style.space(2), parent.height * (parent.usage / 100))
              color: parent.usage >= root.hotThreshold ? root.hotColor : root.fill

              Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
              Behavior on color { ColorAnimation { duration: 200 } }
            }
          }
        }
      }
    }
  }
}
