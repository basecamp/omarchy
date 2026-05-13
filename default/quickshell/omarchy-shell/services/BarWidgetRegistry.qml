import QtQuick

// Instance, not a singleton — instantiated once by shell.qml and injected into
// plugins that need to read or extend the widget catalogue. Relative-path
// singleton imports were creating per-importer instances which prevented the
// settings panel from seeing what the bar registered.
QtObject {
  id: registry

  // { widgetId: { component: Component, metadata: var } }
  property var widgets: ({})
  property int revision: 0

  signal changed()

  function register(id, component, metadata) {
    var key = String(id)
    if (!key) return
    var next = {}
    for (var k in widgets) next[k] = widgets[k]
    next[key] = { component: component, metadata: metadata || {} }
    widgets = next
    revision++
    changed()
  }

  function unregister(id) {
    var key = String(id)
    if (!widgets[key]) return
    var next = {}
    for (var k in widgets) if (k !== key) next[k] = widgets[k]
    widgets = next
    revision++
    changed()
  }

  function componentFor(id) {
    var entry = widgets[String(id)]
    return entry ? entry.component : null
  }

  function metadataFor(id) {
    var entry = widgets[String(id)]
    return entry ? entry.metadata : null
  }

  function availableIds() {
    return Object.keys(widgets)
  }

  function has(id) {
    return widgets[String(id)] !== undefined
  }
}
