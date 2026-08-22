import QtQuick
import qs.Commons

// Determinate progress bar for consequential operations (Rule 6: every
// operation shows state). Bind `value` 0..1; when `indeterminate`, a
// sweeping bar communicates "working" without lying about progress.
//
// `tone` picks the semantic state color so a failed update can turn the
// same bar into an error surface.
Rectangle {
  id: root

  property real value: 0
  property bool indeterminate: false

  // "accent" | "success" | "danger" | "warning" | "info"
  property string tone: "accent"

  readonly property color _tone: tone === "danger" ? Tokens.state.danger
    : tone === "success" ? Tokens.state.success
    : tone === "warning" ? Tokens.state.warning
    : tone === "info" ? Tokens.state.info
    : Tokens.accent.primary

  implicitWidth: 200
  implicitHeight: Math.max(4, Style.space(5))
  radius: height / 2
  color: Util.alpha(Tokens.text.primary, 0.12)
  clip: true

  Rectangle {
    radius: parent.radius
    color: root._tone
    anchors.verticalCenter: parent.verticalCenter
    height: parent.height

    width: root.indeterminate ? parent.width * 0.3 : Math.max(height, parent.width * Util.clampAlpha(root.value))
    x: root.indeterminate ? (parent.width + width) * sweep.phase - width
      : 0

    Behavior on width { NumberAnimation { duration: Tokens.motion.normal } }

    // Indeterminate sweep. Reduced-motion support arrives with the
    // accessibility phase; until then the sweep is the only animation here.
    SequentialAnimation {
      id: sweep
      property real phase: 0
      running: root.indeterminate && root.visible
      loops: Animation.Infinite
      NumberAnimation { target: sweep; property: "phase"; from: 0; to: 1; duration: 1400 }
    }
  }
}
