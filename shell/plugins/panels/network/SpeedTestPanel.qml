import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Centered speed test card, same overlay pattern as WifiQrPanel: dimmed
// scrim, bordered surface, Esc or outside-click to dismiss. Inside sit two
// car-cluster style dials (download left, upload right) that sweep to full
// scale and back when the card opens, then track the live readings.
PanelWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  required property bool running
  required property string phase        // "down" | "up" | ""
  required property string downloadMbps
  required property string uploadMbps
  required property string error
  required property string connectionName
  property bool open: false

  signal closeRequested()
  signal runAgainRequested()

  readonly property real downloadValue: toMbps(downloadMbps)
  readonly property real uploadValue: toMbps(uploadMbps)
  readonly property bool failed: error !== ""
  readonly property bool finished: !running && !failed && (downloadValue > 0 || uploadValue > 0)

  function toMbps(raw) {
    var value = parseFloat(raw)
    return isFinite(value) && value > 0 ? value : 0
  }

  visible: open
  // The window is instantiated hidden, so re-acquire focus after mapping and
  // fire the ignition sweep once the surface is actually on screen.
  onOpenChanged: {
    if (open) Qt.callLater(function() {
      if (!root.open) return
      keyCatcher.forceActiveFocus()
      downDial.ignite()
      upDial.ignite()
    })
  }
  screen: anchorItem.QsWindow.window ? anchorItem.QsWindow.window.screen : null
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-network-speedtest"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.45)

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeRequested()
    }
  }

  BorderSurface {
    width: content.implicitWidth + Style.space(64)
    height: content.implicitHeight + Style.space(48)
    anchors.centerIn: parent
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.popups.border, Math.max(1, Style.space(2)))

    MouseArea { anchors.fill: parent; onClicked: {} }

    Item {
      id: keyCatcher
      anchors.fill: parent
      anchors.margins: Style.space(24)
      focus: true

      Keys.onEscapePressed: root.closeRequested()
      Keys.onReturnPressed: if (!root.running) root.runAgainRequested()
      Keys.onEnterPressed: if (!root.running) root.runAgainRequested()

      ColumnLayout {
        id: content
        anchors.centerIn: parent
        spacing: Style.space(14)

        Text {
          text: "Speed Test"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          visible: root.connectionName !== ""
          text: root.connectionName.toUpperCase()
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
        }

        Row {
          spacing: Style.space(28)
          Layout.alignment: Qt.AlignHCenter
          Layout.topMargin: Style.space(6)

          SpeedDial {
            id: downDial
            label: "DOWNLOAD"
            value: root.downloadValue
            live: root.running && root.phase === "down"
          }

          SpeedDial {
            id: upDial
            label: "UPLOAD"
            value: root.uploadValue
            live: root.running && root.phase === "up"
          }
        }

        Text {
          text: {
            if (root.failed) return root.error
            if (root.running && root.phase === "down") return "Measuring download…"
            if (root.running && root.phase === "up") return "Measuring upload…"
            if (root.finished) return "Measured via fast.com"
            return ""
          }
          visible: text !== ""
          color: root.failed ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.3)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          Layout.fillWidth: true
          Layout.maximumWidth: Style.space(400)
          horizontalAlignment: Text.AlignHCenter
        }

        Button {
          visible: !root.running
          text: "Run Again"
          bordered: true
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(14)
          verticalPadding: Style.space(4)
          Layout.alignment: Qt.AlignHCenter
          onClicked: root.runAgainRequested()
        }
      }
    }
  }

  // One cluster dial: 270° scale opening at the bottom, fine tick ring, an
  // accent needle over a filled value arc, and a digital readout in the
  // middle -- the Tucson look. All writes to the needle funnel through
  // `shown` so the ignition sweep and live readings share one animation.
  component SpeedDial: Item {
    id: dial

    required property string label
    required property real value
    required property bool live

    readonly property real diameter: Style.space(190)
    // 0° = 3 o'clock, increasing clockwise (PathAngleArc's convention).
    readonly property real dialStart: 135
    readonly property real dialSweep: 270
    readonly property int tickCount: 46
    readonly property real arcWidth: Style.space(5)
    readonly property real arcRadius: diameter / 2 - arcWidth
    readonly property color trackColor: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.16)
    readonly property color tickColor: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.35)
    // The dial that isn't measuring yet sits dimmed until it gets a figure.
    readonly property bool engaged: live || value > 0

    property real shown: 0
    // The digital readout stays on the real figure while the ignition sweep
    // drives the needle -- a cluster sweeps its gauges, not its numerals.
    readonly property real reading: ignition.running ? value : shown
    property real fullScale: 100
    readonly property var scaleStops: [100, 250, 500, 1000, 2500, 5000, 10000]
    readonly property real fraction: fullScale > 0 ? Math.max(0, Math.min(1, shown / fullScale)) : 0

    width: diameter
    height: diameter
    opacity: engaged ? 1 : 0.5

    Behavior on opacity {
      NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    // Live readings land once a second; glide between them rather than snap.
    Behavior on shown {
      enabled: !ignition.running
      NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
    }

    Behavior on fullScale {
      enabled: !ignition.running
      NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
    }

    onValueChanged: {
      // Latch the scale upward to the next stop when a reading approaches the
      // rim. Never shrink mid-run; a fresh run just re-sweeps from zero.
      for (var i = 0; i < scaleStops.length; i++) {
        if (value <= scaleStops[i] * 0.92) {
          if (scaleStops[i] > fullScale) fullScale = scaleStops[i]
          break
        }
        if (i === scaleStops.length - 1) fullScale = scaleStops[i]
      }
      if (!ignition.running) shown = value
    }

    function ignite() {
      ignition.restart()
    }

    // Car-cluster power-on: needle sweeps to full scale and falls back before
    // the live figures take over.
    SequentialAnimation {
      id: ignition
      NumberAnimation { target: dial; property: "shown"; to: dial.fullScale; duration: 550; easing.type: Easing.InOutCubic }
      NumberAnimation { target: dial; property: "shown"; to: 0; duration: 650; easing.type: Easing.OutCubic }
      onFinished: dial.shown = dial.value
    }

    // Soft accent halo behind the arc while this direction is measuring.
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: "transparent"
      border.width: Math.max(2, Style.space(3))
      border.color: Color.accent
      opacity: 0

      SequentialAnimation on opacity {
        running: dial.live
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.08; duration: 700; easing.type: Easing.InOutQuad }
      }
    }

    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer

      // Track: the full scale, always visible, dim.
      ShapePath {
        strokeWidth: dial.arcWidth
        strokeColor: dial.trackColor
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap

        PathAngleArc {
          centerX: dial.width / 2
          centerY: dial.height / 2
          radiusX: dial.arcRadius
          radiusY: dial.arcRadius
          startAngle: dial.dialStart
          sweepAngle: dial.dialSweep
        }
      }

      // Value: fills behind the needle. Transparent at rest, or the round cap
      // would leave a stray accent dot at the foot of the scale.
      ShapePath {
        strokeWidth: dial.arcWidth
        strokeColor: dial.fraction > 0.004 ? Color.accent : "transparent"
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap

        PathAngleArc {
          centerX: dial.width / 2
          centerY: dial.height / 2
          radiusX: dial.arcRadius
          radiusY: dial.arcRadius
          startAngle: dial.dialStart
          sweepAngle: dial.dialSweep * dial.fraction
        }
      }
    }

    // Tick ring just inside the arc; every fifth tick is a major.
    Repeater {
      model: dial.tickCount

      Item {
        required property int index
        readonly property bool major: index % 5 === 0

        anchors.fill: parent
        rotation: dial.dialStart + (index / (dial.tickCount - 1)) * dial.dialSweep - 270

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          y: dial.arcWidth * 2 + (parent.major ? 0 : Style.space(2))
          width: parent.major ? Math.max(2, Style.space(2)) : 1
          height: parent.major ? Style.space(10) : Style.space(6)
          radius: width / 2
          color: parent.major ? dial.tickColor : dial.trackColor
        }
      }
    }

    // Needle: pivots on the dial centre, tip riding just inside the ticks.
    Item {
      anchors.fill: parent
      rotation: dial.dialStart + dial.fraction * dial.dialSweep - 270

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: dial.arcWidth * 2 + Style.space(12)
        width: Math.max(2, Style.space(3))
        height: dial.diameter * 0.26
        radius: width / 2
        color: Color.accent
      }
    }

    Rectangle {
      anchors.centerIn: parent
      width: Style.space(12)
      height: width
      radius: width / 2
      color: Color.menu.background
      border.width: Math.max(1, Style.space(2))
      border.color: Color.accent
    }

    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.verticalCenter
      anchors.topMargin: Style.space(14)
      spacing: 0

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: dial.reading < 10 ? dial.reading.toFixed(1) : Math.round(dial.reading).toString()
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Mbps"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // The 90° gap at the bottom of the scale is where a cluster prints its
    // unit; here it names the direction.
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      text: dial.label
      color: Qt.darker(root.bar.foreground, 1.3)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.5
    }
  }
}
