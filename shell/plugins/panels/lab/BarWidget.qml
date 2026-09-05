import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "omarchy.lab"

  property bool viewerActive: false
  property bool keepInBar: false
  readonly property string viewerCommand: "omarchy-lab-viewer"
  readonly property bool shown: viewerActive || keepInBar

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function summon() {
    if (bar && bar.shell) bar.shell.summon(root.moduleName, "{}")
  }

  visible: shown
  implicitWidth: shown ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  Process {
    id: statusProc
    command: [root.viewerCommand, "active", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const status = Model.parseBarStatus(text)
        root.viewerActive = status.viewerActive
        root.keepInBar = status.keepInBar
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.viewerActive = false
        root.keepInBar = false
      }
    }
  }

  Process {
    id: actionProc
  }

  Timer {
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰆧"
    active: root.viewerActive
    tooltipText: root.viewerActive ? "Lab controls · middle click fullscreen · right click screenshot" : "Lab controls · viewer closed"
    onPressed: function(buttonCode) {
      if (!root.viewerActive) {
        root.summon()
      } else if (buttonCode === Qt.MiddleButton) {
        actionProc.command = [root.viewerCommand, "fullscreen"]
        actionProc.running = true
      } else if (buttonCode === Qt.RightButton) {
        actionProc.command = [root.viewerCommand, "screenshot"]
        actionProc.running = true
      } else {
        root.summon()
      }
    }
  }
}
