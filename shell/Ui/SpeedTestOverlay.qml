import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Centered speed test overlay shared by the network and disk speed tests. No
// card: like the Tucson's floating cluster, the two dials sit directly on a
// darkened scrim -- open 270° arcs, faint tick rings, hubless gradient
// needles, and a digital readout in the middle. Esc, the scrim, or the corner
// dismiss close it; the needles sweep to full scale and back on open, then
// track the live readings. Callers name the dials, the unit, and the scale.
PanelWindow {
  id: root

  required property string fontFamily
  required property bool running
  required property string leftLabel
  required property string rightLabel
  property string unit: "Mbps"
  property string title: ""
  property string layerNamespace: "omarchy-speed-test"
  property string runAgainTooltip: "Measure again"
  property real leftValue: 0
  property real rightValue: 0
  property bool leftLive: false
  property bool rightLive: false
  property string error: ""
  property bool open: false
  // Full-scale latch points for the dials, smallest first. The first stop is
  // the base scale a fresh run starts from.
  property var scaleStops: [100, 250, 500, 1000, 2500, 5000, 10000]
  property real fullScale: scaleStops[0]

  signal closeRequested()
  signal runAgainRequested()

  readonly property bool failed: error !== ""

  function resetScale() {
    fullScale = scaleStops[0]
  }

  function expandScale(value) {
    // Either reading ranges the entire cluster upward. Keeping this latch on
    // the overlay ensures both dials always describe the same scale.
    for (var i = 0; i < scaleStops.length; i++) {
      if (value <= scaleStops[i] * 0.92) {
        if (scaleStops[i] > fullScale) fullScale = scaleStops[i]
        return
      }
    }
    fullScale = scaleStops[scaleStops.length - 1]
  }

  onRunningChanged: if (running) resetScale()
  onScaleStopsChanged: resetScale()
  onLeftValueChanged: expandScale(leftValue)
  onRightValueChanged: expandScale(rightValue)

  Behavior on fullScale {
    NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
  }

  // The scrim below is a fixed near-black regardless of theme, so text and
  // ticks on it need a fixed light palette, not the themed bar.foreground.
  readonly property color onScrim: "white"
  readonly property color onScrimDim: Qt.rgba(1, 1, 1, 0.55)
  readonly property color onScrimUrgent: "#ff6b6b"

  visible: open
  // The window is instantiated hidden, so re-acquire focus after mapping and
  // fire the ignition sweep once the surface is actually on screen.
  onOpenChanged: {
    if (open) Qt.callLater(function() {
      if (!root.open) return
      keyCatcher.forceActiveFocus()
      leftDial.ignite()
      rightDial.ignite()
    })
  }
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: root.layerNamespace
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  // Deep scrim: with no card behind them, the floating dials need the
  // backdrop to carry the contrast on any wallpaper, like the near-black
  // panel behind a real cluster.
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.78)

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeRequested()
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true

    Keys.onEscapePressed: root.closeRequested()
    Keys.onReturnPressed: if (!root.running) root.runAgainRequested()
    Keys.onEnterPressed: if (!root.running) root.runAgainRequested()

    Item {
      id: cluster
      anchors.centerIn: parent
      width: content.implicitWidth
      height: content.implicitHeight
      // Narrow or heavily scaled outputs: shrink the whole cluster rather
      // than clipping it at the screen edge.
      scale: Math.min(1,
        (keyCatcher.width - Style.space(32)) / Math.max(1, width),
        (keyCatcher.height - Style.space(32)) / Math.max(1, height))

      // Swallow clicks so only the scrim outside the cluster dismisses.
      MouseArea { anchors.fill: parent; onClicked: {} }

      ColumnLayout {
        id: content
        anchors.fill: parent
        spacing: Style.space(16)

        Text {
          textFormat: Text.PlainText
          visible: root.title !== ""
          text: root.title.toUpperCase()
          color: root.onScrimDim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 2
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
        }

        Row {
          spacing: Style.space(48)
          Layout.alignment: Qt.AlignHCenter

          SpeedDial {
            id: leftDial
            label: root.leftLabel
            value: root.leftValue
            live: root.leftLive
          }

          SpeedDial {
            id: rightDial
            label: root.rightLabel
            value: root.rightValue
            live: root.rightLive
          }
        }

        // Centered on the dial pair. Fades rather than unmounts while a run
        // is in flight, so the cluster never shifts.
        Button {
          text: "Run Again"
          tooltipText: root.runAgainTooltip
          bordered: true
          enabled: !root.running
          opacity: root.running ? 0 : 1
          foreground: root.onScrim
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(14)
          verticalPadding: Style.space(4)
          Layout.alignment: Qt.AlignHCenter
          onClicked: root.runAgainRequested()

          Behavior on opacity {
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.failed
          text: root.error
          color: root.onScrimUrgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          Layout.fillWidth: true
          Layout.maximumWidth: Style.space(440)
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  // One floating cluster dial: an open 270° scale with the gap at the
  // bottom, a faint tick ring, a glowing accent value arc, a hubless needle
  // that fades toward the pivot, and a digital readout in the middle. All
  // writes to the needle funnel through `shown` so the ignition sweep and
  // live readings share one animation.
  component SpeedDial: Item {
    id: dial

    required property string label
    required property real value
    required property bool live

    readonly property real diameter: Style.space(210)
    // 0° = 3 o'clock, increasing clockwise (PathAngleArc's convention).
    readonly property real dialStart: 135
    readonly property real dialSweep: 270
    readonly property int tickCount: 46
    readonly property real arcWidth: Style.space(4)
    readonly property real arcRadius: diameter / 2 - arcWidth
    readonly property color trackColor: Qt.rgba(1, 1, 1, 0.14)
    readonly property color minorTickColor: Qt.rgba(1, 1, 1, 0.12)
    readonly property color majorTickColor: Qt.rgba(1, 1, 1, 0.3)
    // The dial that isn't measuring yet sits dimmed until it gets a figure.
    readonly property bool engaged: live || value > 0

    property real shown: 0
    // The digital readout stays on the real figure while the ignition sweep
    // drives the needle -- a cluster sweeps its gauges, not its numerals.
    readonly property real reading: ignition.running ? value : shown
    readonly property real fullScale: root.fullScale
    readonly property real fraction: fullScale > 0 ? Math.max(0, Math.min(1, shown / fullScale)) : 0
    readonly property bool arcVisible: fraction > 0.004

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

    onValueChanged: {
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

      // Soft under-glow beneath the value arc, standing in for the backlit
      // ring of a real cluster. Both arcs go transparent at rest, or their
      // round caps would leave a stray dot at the foot of the scale.
      ShapePath {
        strokeWidth: dial.arcWidth * 3
        strokeColor: dial.arcVisible ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
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

      // Value: fills behind the needle.
      ShapePath {
        strokeWidth: dial.arcWidth
        strokeColor: dial.arcVisible ? Color.accent : "transparent"
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

    // Faint tick ring just inside the arc; every fifth tick is a major.
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
          color: parent.major ? dial.majorTickColor : dial.minorTickColor
        }
      }
    }

    // Hubless needle: a slender sliver that fades out toward the pivot, so
    // it reads as floating like the rest of the cluster.
    Item {
      anchors.fill: parent
      rotation: dial.dialStart + dial.fraction * dial.dialSweep - 270

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: dial.arcWidth * 2 + Style.space(10)
        width: Math.max(2, Style.space(3))
        height: dial.diameter * 0.32
        radius: width / 2

        gradient: Gradient {
          GradientStop { position: 0.0; color: Color.accent }
          GradientStop { position: 0.55; color: Color.accent }
          GradientStop { position: 1.0; color: "transparent" }
        }
      }
    }

    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.verticalCenter
      anchors.topMargin: Style.space(14)
      spacing: 0

      Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        // Both branches go through the locale: a reading is a measurement, so
        // its separators follow the system's number conventions rather than the
        // interface language. toFixed would have hardcoded a dot below 10 while
        // everything above it was already grouped for the locale.
        text: dial.reading < 10
          ? dial.reading.toLocaleString(Qt.locale(), 'f', 1)
          : Math.round(dial.reading).toLocaleString(Qt.locale(), 'f', 0)
        color: root.onScrim
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.unit
        color: root.onScrimDim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // The 90° gap at the bottom of the scale is where a cluster prints its
    // unit; here it names the direction.
    Text {
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      text: dial.label
      color: root.onScrimDim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.5
    }
  }
}
