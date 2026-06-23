import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.system-update"

  property bool updateAvailable: false

  function refresh() {
    if (!updateProc.running) updateProc.running = true
  }

  function clear() { updateAvailable = false }

  function runUpdate() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-update")
  }

  visible: updateAvailable
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "omarchy.system-update"

    function refresh(): void {
      root.refresh()
    }

    function clear(): void {
      root.clear()
    }
  }

  Process {
    id: updateProc
    command: ["omarchy-update-available"]
    onExited: function(exitCode) {
      root.updateAvailable = exitCode === 0
    }
  }

  Timer {
    interval: 21600000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf021"
    fontSize: Style.font.caption
    tooltipText: ""
    onPressed: root.runUpdate()
  }
}
