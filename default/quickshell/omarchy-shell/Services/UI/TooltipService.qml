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
    if (typeof bar.hideTooltip === "function") {
      bar.hideTooltip(item || null)
    }
  }
}
