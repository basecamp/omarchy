import QtQuick
import Quickshell
import Quickshell.Io
import "MenuUsage.js" as MenuUsage

Item {
  id: root

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy"
  readonly property string statePath: stateDir + "/launcher-usage.json"
  property var records: ({})
  property bool directoryReady: false
  property bool loaded: false

  function load(rawText) {
    root.records = MenuUsage.parse(rawText)
    root.loaded = true
  }

  function count(itemId) {
    return MenuUsage.count(root.records, itemId)
  }

  function lastUsedAt(itemId) {
    return MenuUsage.lastUsedAt(root.records, itemId)
  }

  function record(itemId) {
    if (!root.loaded || !itemId) return
    var next = MenuUsage.record(root.records, itemId, Date.now())
    root.records = next
    stateFile.setText(JSON.stringify({ version: 1, records: next }, null, 2) + "\n")
  }

  Process {
    id: initDir
    command: ["install", "-d", "-m", "0700", root.stateDir]
    onExited: root.directoryReady = true
  }

  FileView {
    id: stateFile
    path: root.directoryReady ? root.statePath : ""
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: if (root.directoryReady) root.load("{}")
  }

  Component.onCompleted: initDir.running = true
}
