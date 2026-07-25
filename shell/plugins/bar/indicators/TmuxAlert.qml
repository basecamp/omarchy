import QtQuick
import Quickshell
import qs.Ui

BarIndicator {
  id: root

  readonly property var tmuxService: bar?.shell?.firstPartyServiceFor("omarchy.tmux")

  active: tmuxService ? tmuxService.waiting : false
  activeText: "󰆍"
  inactiveText: "󰆍"
  activeTooltipText: tmuxService ? tmuxService.tooltip : ""
  inactiveTooltipText: "No Terminal Waiting"

  // The service owns the probe and its polling; the tmux hooks still reach it
  // through the indicator host's refresh broadcast, which coalesces into a
  // single run no matter how many bars relay it.
  function refresh() {
    if (root.tmuxService) root.tmuxService.refresh()
  }

  SequentialAnimation {
    running: root.active
    loops: Animation.Infinite

    PauseAnimation { duration: 2740 }
    NumberAnimation { target: root; property: "textRotation"; to: -10; duration: 50; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "textRotation"; to: 10; duration: 70; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "textRotation"; to: -7; duration: 55; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "textRotation"; to: 7; duration: 45; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "textRotation"; to: 0; duration: 40; easing.type: Easing.OutQuad }

    onStopped: root.textRotation = 0
  }

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  onPressed: function() {
    Quickshell.execDetached(["omarchy-tmux-alert", "focus"])
  }
}
