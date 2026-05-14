import QtQuick
import QtQuick.Controls
import qs.Commons

// Noctalia compat shim. Plugins instantiate this with a model of action
// objects and expect `triggered(action)` when a row is picked.
Menu {
  id: root

  property var model: []
  // Noctalia passes the owning ShellScreen through here. Qt Quick Controls
  // Menu doesn't need it, but accepting the property keeps plugin QML from
  // failing at load time.
  property var screen: null
  signal triggered(var action, var item)

  Instantiator {
    model: root.model
    delegate: MenuItem {
      required property var modelData
      text: modelData ? String(modelData.label || modelData.action || "") : ""
      onTriggered: root.triggered(modelData ? String(modelData.action || "") : "", modelData)
    }
    onObjectAdded: function(index, object) { root.insertItem(index, object) }
    onObjectRemoved: function(index, object) { root.removeItem(object) }
  }
}
