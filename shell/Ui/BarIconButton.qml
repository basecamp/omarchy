import QtQuick
import qs.Commons

// A bar button that occupies the shared icon slot. Its content is sized by
// WidgetButton's optical normalization; this only fixes the slot and the icon
// font size the canvas is derived from.
WidgetButton {
  id: root

  property real slotSize: Style.bar.iconSlot

  fontSize: Style.bar.iconFont
  // A mark wide enough to take more than one square of the grid takes the
  // matching room in the bar, so its padding matches every other icon's.
  fixedWidth: vertical ? -1 : slotSize + slotGrowth
  fixedHeight: vertical ? slotSize + slotGrowth : -1
}
