import QtQuick 2.15
import QtQuick.Window 2.15
import Omarchy.PluginHost 1.0

Window {
  width: 620
  height: 260
  visible: true
  color: "#151a20"
  title: "Omarchy Plugin Security Proof"

  PluginHostInfo {
    id: pluginHost
  }

  Component.onCompleted: {
    if (!pluginHost.runtimeVersion || pluginHost.available)
      Qt.exit(2)
  }

  Column {
    anchors.centerIn: parent
    spacing: 16

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      color: "#9ece6a"
      font.pixelSize: 28
      font.bold: true
      text: "SECURE PLUGIN BRIDGE"
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      color: "#c0caf5"
      font.pixelSize: 18
      text: "Native QML module " + pluginHost.runtimeVersion
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      color: "#a9b1d6"
      font.pixelSize: 15
      text: "Reference module installed; ACTIVATION FEATURE-GATED"
    }
  }
}
