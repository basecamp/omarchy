import QtQuick
import qs.Commons

// Collapsible bar container. Hides its content behind a chevron and reveals it
// with a hover-to-expand slide. This is the single source of the collapse/expand
// motion for the bar: the system tray drawer and the widget group both use it,
// so the two never drift.
//
// Two layout modes:
//   reserveSpace: false (default, widget groups) — space-saving: collapsed the
//     container is just the chevron and it grows to fit its content as it opens.
//   reserveSpace: true (system tray) — the full extent is always reserved; the
//     chevron migrates and the content slides in and out beneath it, and the
//     empty reserved area is masked so it does not steal hover or clicks.
//
// Content is supplied as a Component (not default children) so the chevron and
// clip below are not swallowed by a default-property alias, and so the loaded
// item is available to measure for the drawer extent.
Item {
  id: root

  // Host bar, injected by the caller. Supplies vertical / barSize / theming for
  // the chevron. Left null the component still lays out with Style fallbacks.
  property var bar: null
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  // The content to reveal. Its implicit size along the bar axis is the extent
  // the drawer opens to.
  property Component contentComponent: null
  readonly property Item body: contentLoader.item

  property bool collapsedByDefault: true
  property bool expandOnHover: true
  // Reserve the full extent while collapsed (tray drawer) instead of shrinking
  // to just the chevron (widget group).
  property bool reserveSpace: false
  // Left-click the chevron to pin the drawer open. The tray drives reveal by
  // hover alone and uses the chevron's right button for its manage popup, so it
  // turns this off and listens to chevronPressed instead.
  property bool pinOnClick: true
  // Chevron glyph (the same one the tray drawer uses). Escaped codepoint on
  // purpose: raw Nerd Font glyphs can be mangled by file tooling, so the default
  // stays stable this way.
  property string icon: "\uf053"
  property int animationDuration: 600

  signal chevronPressed(int button)

  // A hover reveals transiently; a chevron click pins the drawer open so it
  // survives the pointer leaving. pinnedOpen follows collapsedByDefault until the
  // first chevron click breaks the binding and hands control to the user. It must
  // stay a live binding: BarGroup sets the group's entry — and thus
  // collapsedByDefault — right after load, so freezing on completion would lock in
  // the pre-entry default and ignore a configured collapsed: false.
  property bool pinnedOpen: !collapsedByDefault
  property bool hovered: false
  readonly property bool open: pinnedOpen || (expandOnHover && hovered)

  readonly property real drawerExtent: body ? (vertical ? body.implicitHeight : body.implicitWidth) : 0
  property real revealProgress: open ? 1 : 0
  readonly property real revealExtent: drawerExtent * revealProgress

  // Extent occupied beyond the chevron: the full drawer when space is reserved,
  // otherwise only the slice revealed so far.
  readonly property real reservedExtent: reserveSpace ? drawerExtent : revealExtent
  // In reserve mode the chevron migrates as the drawer opens and the content
  // slides under it; in space-saving mode the chevron is fixed and the content
  // is wiped in from it.
  readonly property real chevronOffset: reserveSpace ? (drawerExtent - revealExtent) : 0
  readonly property real clipExtent: reserveSpace ? drawerExtent : revealExtent
  readonly property real contentOffset: reserveSpace ? (drawerExtent - revealExtent) : 0

  Behavior on revealProgress {
    NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
  }

  implicitWidth: vertical ? barSize : Math.round(chevron.implicitWidth + reservedExtent)
  implicitHeight: vertical ? Math.round(chevron.implicitHeight + reservedExtent) : barSize

  // Reserved-but-empty space must not react to the pointer, or hovering the gap
  // beside a collapsed drawer would expand it and clicks would be swallowed.
  // Only the chevron and the revealed content are live. Nothing to mask in
  // space-saving mode, where the block shrinks to the chevron.
  containmentMask: root.reserveSpace ? reserveMask : null
  QtObject {
    id: reserveMask
    function contains(point: point): bool {
      if (root.vertical) {
        if (point.x < 0 || point.x > root.width) return false
        return point.y >= root.chevronOffset && point.y <= root.height
      }
      if (point.y < 0 || point.y > root.height) return false
      return point.x >= root.chevronOffset && point.x <= root.width
    }
  }

  // Whole-container hover drives the transient reveal. A HoverHandler on the
  // root sees the chevron and the revealed content as one region, so sliding
  // from the chevron onto the content does not collapse it mid-motion.
  HoverHandler {
    enabled: root.expandOnHover
    onHoveredChanged: root.hovered = hovered
  }

  BarIconButton {
    id: chevron
    bar: root.bar
    x: root.vertical ? 0 : root.chevronOffset
    y: root.vertical ? root.chevronOffset : 0
    width: implicitWidth
    height: implicitHeight
    text: root.icon
    textRotation: root.vertical ? 90 : 0
    onPressed: function(button) {
      root.chevronPressed(button)
      if (root.pinOnClick && button === Qt.LeftButton) root.pinnedOpen = !root.pinnedOpen
    }
  }

  // The revealed slice. Clipped so the content is wiped/slid in from the chevron
  // as the slice grows, and so a partially-open drawer never paints past its edge.
  Item {
    id: revealClip
    x: root.vertical ? 0 : chevron.implicitWidth
    y: root.vertical ? chevron.implicitHeight : 0
    width: root.vertical ? root.barSize : Math.round(root.clipExtent)
    height: root.vertical ? Math.round(root.clipExtent) : root.barSize
    clip: true

    // The content is laid out at its full extent regardless of how far the
    // drawer has opened, so its widgets never reflow as it animates. On the
    // cross axis it is sized to the content and centered, so content shorter
    // than the bar (e.g. tray icons) sits centered like the pinned items rather
    // than top/left-aligned — matching the tray drawer's original centering.
    Loader {
      id: contentLoader
      sourceComponent: root.contentComponent
      x: root.vertical ? Math.round((root.barSize - implicitWidth) / 2) : Math.round(root.contentOffset)
      y: root.vertical ? Math.round(root.contentOffset) : Math.round((root.barSize - implicitHeight) / 2)
      width: root.vertical ? implicitWidth : root.drawerExtent
      height: root.vertical ? root.drawerExtent : implicitHeight
    }
  }
}
