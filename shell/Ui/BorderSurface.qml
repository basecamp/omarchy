import QtQuick
import qs.Commons

// Rectangle-compatible surface with Omarchy border specs. Uses native
// Rectangle.border for cheap flat/uniform borders and BorderOverlay for
// gradients or per-side widths.
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
  readonly property real contentTopInset: borderTop + topPadding
  readonly property real contentRightInset: borderRight + rightPadding
  readonly property real contentBottomInset: borderBottom + bottomPadding
  readonly property real contentLeftInset: borderLeft + leftPadding
  readonly property bool usesOverlayBorder: Border.needsOverlay(borderSpec)

  border.color: Border.canUseNative(borderSpec) ? Border.color(borderSpec) : "transparent"
  border.width: Border.canUseNative(borderSpec) ? Border.uniformWidth(borderSpec) : 0

  Loader {
    anchors.fill: parent
    active: root.usesOverlayBorder

    sourceComponent: BorderOverlay {
      anchors.fill: parent
      radius: root.radius
      borderSpec: root.borderSpec
    }
  }
}
