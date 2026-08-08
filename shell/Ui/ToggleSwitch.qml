import QtQuick
import qs.Commons

// Bare on/off switch: a track with a sliding knob and no label. This is the
// switch `Toggle` parks at the end of its labeled row, factored out so panel
// headers and other compact controls render the identical thing.
//
// The caller owns the value: bind `checked` to real state and flip it in
// response to `toggled()`. Services that already track a desired state
// optimistically (see the Tailscale service's `_desired`) get an instant knob
// throw for free, because `checked` is already the optimistic value.
//
// `busy` marks an operation in flight and swallows further clicks, but leaves
// hover, cursor, and tooltips alone so the control does not flicker every time
// a background refresh runs.
//
// The cursor is a ring drawn outside the track rather than a state on the
// track itself: themes give normal chrome a stronger border than hover-cursor
// (0.4 vs 0.25 by default), which is right for controls that are borderless at
// rest but would make a bordered track go *fainter* under the cursor. On the
// panel background the ring reads immediately. `cursorRing` follows
// `interactive` — a switch whose surrounding row owns the click owns the
// cursor too.
//
// `rounded` auto-detects from Style.cornerRadius so the switch follows the
// theme: pill shape when Hyprland corners are rounded, square on sharp.
Item {
  id: root

  property bool checked: false
  property bool busy: false

  // Off when the surrounding row owns the click, as in `Toggle`.
  property bool interactive: true

  // Panel-cursor flag. Same role as Button.hasCursor: panels with their own
  // keyboard cursor bind this to drive the highlight separately from hover.
  property bool hasCursor: false

  property bool cursorRing: interactive
  property int cursorPad: Style.space(6)
  property bool rounded: Style.cornerRadius > 0
  property color foreground: Color.foreground
  property color accent: Color.accent

  signal toggled()
  signal hovered(bool isHovered)

  readonly property alias containsMouse: mouse.containsMouse
  readonly property bool hot: hasCursor || mouse.containsMouse

  // `trackHeight` is settable so a compact placement — a switch riding a panel
  // section header, say — can ask for a genuinely smaller control instead of
  // scaling a big one down, which lands the track and knob on fractional pixels
  // and blurs their edges. The derived sizes only carry floors low enough to
  // stay out of an override's way; at the default track height each one is
  // already above its floor, so nothing about the normal switch changes.
  property int trackHeight: Math.max(22, Math.round(Style.spacing.controlHeight * 0.55))
  property int trackWidth: Math.round(trackHeight * 1.9)
  property int knobSize: Math.max(6, Math.round(trackHeight * 0.72))
  property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))

  readonly property int _pad: cursorRing ? cursorPad : 0

  implicitWidth: trackWidth + _pad * 2
  implicitHeight: trackHeight + _pad * 2

  BorderSurface {
    anchors.fill: parent
    visible: root.cursorRing && root.hot
    color: "transparent"
    radius: Style.cornerRadius
    borderSpec: Border.controlSpec("hover-cursor", root.foreground, root.accent)
  }

  BorderSurface {
    id: track
    width: root.trackWidth
    height: root.trackHeight
    anchors.centerIn: parent
    radius: root.rounded ? height / 2 : 0
    color: root.checked
      ? Style.selectedFillFor(root.foreground, root.accent)
      : Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Border.controlSpec(root.checked ? "selected" : "normal", root.foreground, root.accent)

    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
      width: root.knobSize
      height: root.knobSize
      radius: root.rounded ? height / 2 : 0
      x: root.checked ? track.width - width - root.knobInset : root.knobInset
      anchors.verticalCenter: parent.verticalCenter
      color: root.checked ? Style.selectedStateColor(root.foreground, root.accent) : Qt.darker(root.foreground, 1.25)

      Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: 120 } }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: if (!root.busy) root.toggled()
  }
}
