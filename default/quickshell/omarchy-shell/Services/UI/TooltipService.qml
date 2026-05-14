pragma Singleton
import QtQuick

// Noctalia compat shim. Their plugins call TooltipService.show(item, text)
// on hover; we route that into the Omarchy bar's shared tooltip popup.
QtObject {
  id: root

  // Wired by Bar.qml on construction.
  property var bar: null

  function show(item, text, direction) {
    if (!bar || !item) return
    if (typeof bar.showTooltip === "function") {
      bar.showTooltip(item, text || "")
    }
  }

  function hide(item) {
    if (!bar) return
    if (item && typeof bar.hideTooltip === "function") {
      bar.hideTooltip(item)
    } else if (bar.tooltipTarget) {
      // Noctalia plugins often call TooltipService.hide() without the source
      // item on click. Native bar.hideTooltip(target) ignores null targets, so
      // clear the currently visible tooltip explicitly.
      bar.hideTooltip(bar.tooltipTarget)
    }
  }
}
