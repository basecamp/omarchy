import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Item {
  id: root
  property var bar: null
  property string omarchyPath: bar && bar.omarchyPath ? bar.omarchyPath : ""

  implicitWidth: row.implicitWidth
  implicitHeight: parent ? parent.height : 40

  readonly property var clusterEntries: {
    var _rev = bar && bar.barWidgetRegistry ? bar.barWidgetRegistry.revision : 0
    var layout = bar && bar.barConfig && bar.barConfig.layout ? bar.barConfig.layout : {}
    var right = layout && Array.isArray(layout.right) ? layout.right : []
    var out = []
    var i
    for (i = 0; i < right.length; i++) {
      var id = ""
      if (typeof right[i] === "string") id = right[i]
      else if (right[i] && right[i].id) id = String(right[i].id)
      if (id) out.push({ id: id, settings: (right[i] && right[i]) || {} })
    }
    return out
  }

  Row {
    id: row
    anchors.fill: parent
    spacing: 0

    Repeater {
      model: root.clusterEntries
      delegate: Loader {
        id: widgetLoader
        required property var modelData
        height: row.height
        width: item ? Math.max(item.implicitWidth, 32) : 32
        readonly property var registryEntry: {
          var w = root.bar && root.bar.barWidgetRegistry ? root.bar.barWidgetRegistry.widgets : {}
          return w[modelData.id] || null
        }
        sourceComponent: registryEntry && registryEntry.component ? registryEntry.component : null
        onLoaded: {
          if (!item) return
          if ("bar" in item) item.bar = root.bar
          if ("shell" in item && root.bar && root.bar.shell) item.shell = root.bar.shell
          if ("moduleName" in item) item.moduleName = modelData.id
          if ("settings" in item && modelData.settings) item.settings = modelData.settings
          if (root.bar && typeof root.bar.registerSlot === "function")
            root.bar.registerSlot(modelData.id, item)
        }
      }
    }
  }
}
