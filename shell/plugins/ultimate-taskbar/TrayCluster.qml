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

  function widgetUrl(rel) {
    return Util.fileUrl(root.omarchyPath + "/shell/plugins/" + rel)
  }

  Row {
    id: row
    anchors.fill: parent
    spacing: 0

    Repeater {
      model: [
        { id: "omarchy.audio", path: "panels/audio/Panel.qml" },
        { id: "omarchy.bluetooth", path: "panels/bluetooth/Panel.qml" },
        { id: "omarchy.network", path: "panels/network/Panel.qml" },
        { id: "omarchy.monitor", path: "panels/monitor/Panel.qml" },
        { id: "omarchy.power", path: "panels/power/Panel.qml" }
      ]
      delegate: Loader {
        id: panelLoader
        height: row.height
        width: item ? Math.max(item.implicitWidth, 32) : 32
        source: root.omarchyPath ? root.widgetUrl(modelData.path) : ""
        onLoaded: {
          if (!item) return
          if ("bar" in item) item.bar = root.bar
          if ("moduleName" in item) item.moduleName = modelData.id
          if (root.bar && typeof root.bar.registerSlot === "function")
            root.bar.registerSlot(modelData.id, item)
        }
      }
    }

    Loader {
      id: trayLoader
      height: row.height
      width: item ? Math.max(item.implicitWidth, 24) : 24
      source: root.omarchyPath ? root.widgetUrl("bar/widgets/Tray.qml") : ""
      onLoaded: {
        if (!item) return
        if ("bar" in item) item.bar = root.bar
        if ("moduleName" in item) item.moduleName = "omarchy.tray"
        if (root.bar && typeof root.bar.registerSlot === "function")
          root.bar.registerSlot("omarchy.tray", item)
      }
    }

    Loader {
      id: clockLoader
      height: row.height
      width: item ? Math.max(item.implicitWidth, 72) : 72
      source: root.omarchyPath ? root.widgetUrl("panels/clock/BarWidget.qml") : ""
      onLoaded: {
        if (!item) return
        if ("bar" in item) item.bar = root.bar
        if ("moduleName" in item) item.moduleName = "omarchy.clock"
        if (root.bar && typeof root.bar.registerSlot === "function")
          root.bar.registerSlot("omarchy.clock", item)
      }
    }
  }
}
