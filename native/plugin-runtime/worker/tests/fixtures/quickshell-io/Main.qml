import QtQuick
import Quickshell.Io 1.0

Item {
  id: root
  objectName: "pending"
  FileView { id: view; preload: false }
  StdioCollector { id: collector; maximumBytes: 3 }

  Component.onCompleted: {
    collector.setText("abcdef")
    objectName = view.packagedPath("assets/data.json") === "assets/data.json"
      && view.packagedPath("file:///plugin/assets/data.json") === "assets/data.json"
      && view.packagedPath("/plugin/assets/data.json") === "assets/data.json"
      && view.packagedPath("../data.json") === ""
      && view.packagedPath("/etc/passwd") === ""
      && view.packagedPath("file:///home/plugin/.ssh/id") === ""
      && collector.text === "abc"
      ? "quickshell-io-loaded" : "unsafe-quickshell-io"
  }
}
