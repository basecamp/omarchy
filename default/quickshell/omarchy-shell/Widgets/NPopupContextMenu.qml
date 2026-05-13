import QtQuick
import QtQuick.Controls
import qs.Commons

// Noctalia compat shim. Plugins instantiate this with a model of action
// objects and expect `triggered(action)` when a row is picked.
Menu {
  id: root

  property var model: []
  signal triggered(string action)

  Instantiator {
    model: root.model
    delegate: MenuItem {
      required property var modelData
      text: modelData ? String(modelData.label || modelData.action || "") : ""
      onTriggered: root.triggered(modelData ? String(modelData.action || "") : "")
    }
    onObjectAdded: function(index, object) { root.insertItem(index, object) }
    onObjectRemoved: function(index, object) { root.removeItem(object) }
  }
}
