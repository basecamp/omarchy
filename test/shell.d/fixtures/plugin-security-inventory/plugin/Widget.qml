import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  property string userCommand: "status"
  property var model

  Process { command: ["bash", "-lc", userCommand] }
  FileView { path: Quickshell.env("HOME") + "/notes" }
  IpcHandler { target: "inventory" }
  Notification { summary: "Complete" }

  TapHandler {
    onTapped: Qt.openUrlExternally(model.url)
  }

  Component.onCompleted: console.log(PluginRegistry.installedPlugins)
  property string secretFixture: "B7_SECRET_MUST_NOT_LEAK"
}
