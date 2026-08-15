import QtQuick
import qs.Commons

// Collapsible bar container. Hides its content behind a chevron and reveals it
// with the same hover-to-expand motion the system tray drawer uses, so a group
// of bar widgets can be tucked away and slid back into view.
//
// The animation constants (600ms, OutCubic) are meant to be the shared source
// of truth for every collapsing bar surface: the tray drawer in
// `plugins/bar/widgets/Tray.qml` currently inlines the same values and is meant
// to migrate onto this component so the two never drift.
//
// This first cut is space-saving: collapsed the container is just the chevron,
// and it grows to fit its content as it opens. (The tray additionally reserves
// its full extent while collapsed; adding that mode here is the follow-up that
// lets the tray adopt this component.)
//
// Content is supplied as a Component rather than as default children so the
// chevron and clip declared below are not swallowed by a default-property alias,
// and so the instantiated item is available to measure for the drawer extent.
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
  // Chevron glyph (the same one the tray drawer uses). Escaped codepoint on
  // purpose: raw Nerd Font glyphs can be mangled by file tooling, so the default
  // stays stable this way.
  property string icon: "\uf053"
  property int animationDuration: 600

  // A hover reveals transiently; a chevron click pins the drawer open so it
  // survives the pointer leaving. collapsedByDefault seeds the pinned state.
  property bool pinnedOpen: !collapsedByDefault
  property bool hovered: false
  readonly property bool open: pinnedOpen || (expandOnHover && hovered)

  readonly property real drawerExtent: body ? (vertical ? body.implicitHeight : body.implicitWidth) : 0
  property real revealProgress: open ? 1 : 0
  readonly property real revealExtent: drawerExtent * revealProgress

  Behavior on revealProgress {
    NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
  }

  implicitWidth: vertical ? barSize : Math.round(chevron.implicitWidth + revealExtent)
  implicitHeight: vertical ? Math.round(chevron.implicitHeight + revealExtent) : barSize

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
    x: 0
    y: 0
    width: implicitWidth
    height: implicitHeight
    text: root.icon
    textRotation: root.vertical ? 90 : 0
    // Left-click pins/unpins; the reveal itself is handled by hover above.
    onPressed: function(button) {
      if (button === Qt.LeftButton) root.pinnedOpen = !root.pinnedOpen
    }
  }

  // The revealed slice. Clipped so the content is wiped in from the chevron as
  // the slice grows, and so a partially-open drawer never paints past its edge.
  Item {
    id: revealClip
    x: root.vertical ? 0 : chevron.implicitWidth
    y: root.vertical ? chevron.implicitHeight : 0
    width: root.vertical ? root.barSize : Math.round(root.revealExtent)
    height: root.vertical ? Math.round(root.revealExtent) : root.barSize
    clip: true

    // The content is laid out at its full extent regardless of how far the slice
    // has opened, so its widgets never reflow as the drawer animates.
    Loader {
      id: contentLoader
      x: 0
      y: 0
      width: root.vertical ? root.barSize : root.drawerExtent
      height: root.vertical ? root.drawerExtent : root.barSize
      sourceComponent: root.contentComponent
    }
  }
}
