import QtQuick

// Detached widget-catalogue snapshot for third-party full-bar implementations.
// Plugins can render the referenced components, but mutating this local view
// cannot replace a registration in the host registry.
QtObject {
  id: api

  property var widgets: ({})
  property int revision: 0

  function metadataFor(id) {
    var entry = widgets[String(id || "")]
    return entry ? entry.metadata : null
  }

  function availableIds() {
    return Object.keys(widgets)
  }

  function has(id) {
    return widgets[String(id || "")] !== undefined
  }
}
