import QtQuick
import QtQuick.Window
import qs.Commons

// Rectangle-compatible surface with Omarchy border specs. Flat/uniform
// borders draw with a cheap nested Rectangle stroke and gradients or
// per-side widths with BorderOverlay. Both are inset a device pixel so
// strokes flush against an ancestor's clip edge survive fractionally
// scaled outputs; setting border.* on this item directly draws an
// extra un-inset stroke alongside the spec-driven one.
Rectangle {
  id: root

  property var borderSpec: Border.none()
  property real padding: 0
  property real topPadding: padding
  property real rightPadding: padding
  property real bottomPadding: padding
  property real leftPadding: padding

  readonly property real borderTop: Border.top(borderSpec)
  readonly property real borderRight: Border.right(borderSpec)
  readonly property real borderBottom: Border.bottom(borderSpec)
  readonly property real borderLeft: Border.left(borderSpec)
  readonly property real contentTopInset: borderTop + topPadding + contentStrokeInset
  readonly property real contentRightInset: borderRight + rightPadding + contentStrokeInset
  readonly property real contentBottomInset: borderBottom + bottomPadding + contentStrokeInset
  readonly property real contentLeftInset: borderLeft + leftPadding + contentStrokeInset
  readonly property bool usesOverlayBorder: Border.needsOverlay(borderSpec)
  readonly property bool usesNativeBorder: Border.canUseNative(borderSpec)

  readonly property real strokeInset: 1 / (Screen.devicePixelRatio || 1)
  readonly property real insetRadius: Math.max(0, radius - strokeInset)
  readonly property real contentStrokeInset: usesNativeBorder || usesOverlayBorder ? strokeInset : 0

  Rectangle {
    anchors.fill: parent
    anchors.margins: root.strokeInset
    radius: root.insetRadius
    color: "transparent"
    visible: root.usesNativeBorder
    border.color: Border.color(root.borderSpec)
    border.width: Border.uniformWidth(root.borderSpec)
  }

  Loader {
    anchors.fill: parent
    anchors.margins: root.strokeInset
    active: root.usesOverlayBorder

    sourceComponent: BorderOverlay {
      anchors.fill: parent
      radius: root.insetRadius
      borderSpec: root.borderSpec
    }
  }
}
