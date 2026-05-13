pragma Singleton
import QtQuick

// Noctalia compat shim. Plugins use this for context menus and to reach
// the host's panels. We forward into the omarchy-shell host where there's
// a matching surface, and log a warning for anything we don't ship in v1.
QtObject {
  id: root

  property var bar: null
  property var shell: null

  // Plugins call this on right-click with a Menu component. The Noctalia
  // implementation parents the menu to the screen's overlay; we simply
  // call `open()` on whatever the plugin passes — most plugin context menus
  // are plain QtQuick `Menu` items that know how to show themselves.
  function showContextMenu(menu, item, screen) {
    if (!menu) return
    if (typeof menu.popup === "function") menu.popup()
    else if (typeof menu.open === "function") menu.open()
  }

  function closeContextMenu(screen) {
    // No-op; the Menu / PopupWindow closes itself on outside click.
  }

  function openLauncherWithSearch(screen, prefix) {
    console.warn("PanelService.openLauncherWithSearch is not supported in the Omarchy compat layer")
  }

  function getPanel(name, screen) {
    return null
  }
}
