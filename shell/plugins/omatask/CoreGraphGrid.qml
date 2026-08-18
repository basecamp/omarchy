import QtQuick
import qs.Commons
import "Model.js" as Model

// One history graph per logical core — the "logical processors" view. Cells lay
// out on a grid sized to the available width, and the whole grid scrolls, so a
// 16-thread laptop and a 256-thread workstation both render honestly instead of
// one of them being truncated or squeezed into slivers.
Flickable {
  id: root

  // Dimming has to know what it is dimming *against*. dim() only reads as
  // "less prominent" on a dark ground; on a light theme it makes secondary text
  // darker — and therefore louder — than the primary text it sits behind. This
  // moves toward the background either way.
  readonly property bool groundIsDark: Model.groundIsDark(root.ground)
  function dim(c, amount) { return Model.dim(root.ground, c, amount) }

  // The surface this sits on, so dim() knows which way to move.
  property color ground: Color.popups.background

  property var histories: []
  property var cores: []
  property int capacity: 60
  property color foreground: Color.foreground
  property color hotColor: Color.urgent
  property real hotThreshold: 85
  property string fontFamily: Style.font.family
  property real minCellWidth: Style.space(84)
  property real maxCellHeight: Style.space(52)
  property real minCellHeight: Style.space(26)
  property real gap: Style.space(6)

  readonly property int count: (cores || []).length
  readonly property int columns: {
    if (count === 0 || width <= 0) return 1
    var fits = Math.floor((width + gap) / (minCellWidth + gap))
    return Math.max(1, Math.min(count, fits))
  }
  readonly property real cellWidth: columns > 0 ? (width - gap * (columns - 1)) / columns : 0
  readonly property int rowCount: count > 0 ? Math.ceil(count / columns) : 0

  // Shrink the cells to fit every core in view before resorting to scrolling.
  // A core grid you have to scroll is a core grid that failed at its one job,
  // so height is only conceded once the cells hit their legibility floor.
  readonly property real cellHeight: {
    if (rowCount === 0 || height <= 0) return maxCellHeight
    var available = (height - gap * (rowCount - 1)) / rowCount
    return Math.max(minCellHeight, Math.min(maxCellHeight, available))
  }

  // Keyboard scrolling for the case where even the floor does not fit.
  readonly property bool scrollable: contentHeight > height + 1

  function scrollBy(delta) {
    if (!scrollable) return
    contentY = Math.max(0, Math.min(contentHeight - height, contentY + delta))
  }

  contentWidth: width
  contentHeight: grid.height
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.VerticalFlick

  Grid {
    id: grid
    width: root.width
    columns: root.columns
    columnSpacing: root.gap
    rowSpacing: root.gap

    Repeater {
      model: root.count

      Item {
        required property int index
        readonly property real usage: Number(root.cores[index]) || 0
        readonly property bool hot: usage >= root.hotThreshold

        width: root.cellWidth
        height: root.cellHeight

        Rectangle {
          anchors.fill: parent
          radius: Style.space(3)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
        }

        Sparkline {
          anchors.fill: parent
          anchors.margins: Style.space(3)
          // Each cell keeps its own ring, so switching into this view shows
          // history that was already being collected rather than starting flat.
          values: (root.histories || [])[index] || []
          capacity: root.capacity
          maxValue: 100
          stroke: parent.hot ? root.hotColor : root.foreground
          lineWidth: 1
          fillOpacity: 0.2
        }

        // Labels sit on top of the graph: at this cell size, giving them their
        // own row would leave the graph too short to read.
        Text {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.margins: Style.space(4)
          text: index
          color: dim(root.foreground, 1.7)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(4)
          text: Math.round(parent.usage) + "%"
          color: parent.hot ? root.hotColor : dim(root.foreground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: parent.hot
        }
      }
    }
  }
}
