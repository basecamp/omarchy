import QtQuick
import Quickshell.Io
import "NightlightModel.js" as NightlightModel

Item {
  id: root

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  // Keep in sync with bin/omarchy-toggle-nightlight, which sets the same
  // temperatures for callers outside the shell (keybindings, menu, ssh).
  readonly property int nightTemperature: 4000
  readonly property int dayTemperature: 6500

  property bool stateLoaded: false
  property var temperature: null
  readonly property bool enabled: stateLoaded && NightlightModel.isNightlight(temperature)

  property bool hasPendingTemperature: false
  property int pendingTemperature: 0

  function refresh() {
    if (!statusProbe.running) statusProbe.running = true
  }

  function setNightlight(value) {
    applyTemperature(value ? nightTemperature : dayTemperature)
  }

  function toggle() {
    setNightlight(!enabled)
  }

  function applyTemperature(temp) {
    root.temperature = temp
    root.stateLoaded = true

    if (applyProcess.running) {
      root.pendingTemperature = temp
      root.hasPendingTemperature = true
      return
    }

    runApply(temp)
  }

  function runApply(temp) {
    applyProcess.command = ["bash", "-lc",
      "pgrep -x hyprsunset >/dev/null || { setsid uwsm-app -- hyprsunset >/dev/null 2>&1 & sleep 1; }; " +
      "hyprctl hyprsunset temperature " + Number(temp)]
    applyProcess.running = true
  }

  Process {
    id: statusProbe
    command: ["hyprctl", "hyprsunset", "temperature"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.temperature = NightlightModel.temperatureFromOutput(text)
        root.stateLoaded = true
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.temperature = null
        root.stateLoaded = true
      }
    }
  }

  Process {
    id: applyProcess
    onExited: function() {
      if (root.hasPendingTemperature) {
        root.hasPendingTemperature = false
        root.runApply(root.pendingTemperature)
        return
      }

      root.refresh()
    }
  }

  Component.onCompleted: refresh()

  IpcHandler {
    target: "nightlight"

    function status(): string {
      return JSON.stringify({ enabled: root.enabled, temperature: root.temperature })
    }

    function refresh(): void {
      root.refresh()
    }

    function enable(): string {
      root.setNightlight(true)
      return "enabled"
    }

    function disable(): string {
      root.setNightlight(false)
      return "disabled"
    }

    function toggle(): string {
      var enabling = !root.enabled
      root.setNightlight(enabling)
      return enabling ? "enabled" : "disabled"
    }
  }
}
