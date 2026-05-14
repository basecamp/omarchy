pragma Singleton
import QtQuick

// Noctalia compat shim. Plugin bar widgets call into BarService for
// registration bookkeeping and to ask the host where their tooltip should
// pop. We track the bar reference (set by the host at startup) and expose
// the helpers plugins actually use.
QtObject {
  id: root

  // Wired by omarchy-shell's Bar.qml on construction so we can reach back
  // for things like position and the tooltip popup.
  property var bar: null

  // Plugins read this when computing their own layout-revision markers.
  property int widgetsRevision: 0

  // Bookkeeping for plugin widgets. Not consulted by Omarchy itself; some
  // plugins call lookupWidget() to coordinate across instances.
  property var registered: ({})

  function registerWidget(screen, section, widgetId, index, item) {
    var key = (screen && screen.name ? screen.name : "_") + ":" + section + ":" + widgetId + ":" + index
    var next = {}
    for (var k in registered) next[k] = registered[k]
    next[key] = { screen: screen, section: section, widgetId: widgetId, index: index, item: item }
    registered = next
    widgetsRevision++
  }

  function unregisterWidget(screen, section, widgetId, index) {
    var key = (screen && screen.name ? screen.name : "_") + ":" + section + ":" + widgetId + ":" + index
    if (!registered[key]) return
    var next = {}
    for (var k in registered) if (k !== key) next[k] = registered[k]
    registered = next
    widgetsRevision++
  }

  // Plugins occasionally search for a sibling widget by id. We do a linear
  // scan since the registry is small in practice.
  function lookupWidget(widgetId) {
    for (var k in registered) {
      if (registered[k].widgetId === widgetId) return registered[k]
    }
    return undefined
  }

  // Translate the bar's edge to a tooltip direction string. Noctalia expects
  // strings; the Omarchy bar drives its own tooltip popup off bar.position.
  function getTooltipDirection(screenName) {
    var pos = bar ? bar.position : "top"
    if (pos === "top") return "down"
    if (pos === "bottom") return "up"
    if (pos === "left") return "right"
    if (pos === "right") return "left"
    return "down"
  }

  function getPillDirection(item) {
    var pos = bar ? bar.position : "top"
    return pos === "left" || pos === "right" ? "horizontal" : "vertical"
  }

  // Forward into the omarchy-shell host. Most Noctalia widgets call this
  // from a right-click handler.
  function openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings) {
    if (bar && bar.shell && typeof bar.shell.summon === "function") {
      bar.shell.summon("omarchy.settings",
        JSON.stringify({ focusWidgetId: widgetId, section: section, index: sectionWidgetIndex }))
    }
  }

  function openPluginSettings(screen, manifest) {
    if (bar && bar.shell && typeof bar.shell.summon === "function") {
      bar.shell.summon("omarchy.settings",
        JSON.stringify({ focusPluginId: manifest ? manifest.id : "" }))
    }
  }
}
