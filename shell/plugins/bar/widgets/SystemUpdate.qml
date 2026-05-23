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

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "omarchy.system-update"

    function refresh(): void {
      root.refresh()
    }
  }

  Process {
    id: updateProc
    command: ["bash", "-lc", "omarchy-update-available"]
    stdout: StdioCollector { waitForEnd: true }
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
    text: root.updateAvailable ? "\uf021" : ""
    fontSize: Style.font.caption
    tooltipText: root.updateAvailable ? "Omarchy update available" : ""
    onPressed: function() { root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-update") }
  }
}
