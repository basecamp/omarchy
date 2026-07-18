import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var manifest: null

  property var packageState: Model.emptyPackageState()
  property var themeState: Model.emptyThemeState()
  property bool packageRefreshing: false
  property bool themeRefreshing: false
  property string packageError: ""
  property string themeError: ""
  property string actionName: ""
  property string actionKind: ""
  property string actionStatus: ""
  property string actionError: ""

  property string _packageOutput: ""
  property string _packageErrorOutput: ""
  property string _themeOutput: ""
  property string _themeErrorOutput: ""
  property string _actionOutput: ""
  property string _actionErrorOutput: ""
  property bool _packageTimedOut: false
  property bool _themeTimedOut: false
  property bool _actionTimedOut: false

  readonly property int packageCount: packageState ? Number(packageState.count || 0) : 0
  readonly property int themeCount: themeState ? Number(themeState.outdated || 0) : 0
  readonly property int totalUpdateCount: packageCount + themeCount
  readonly property bool hasUpdates: totalUpdateCount > 0
  readonly property bool needsAttention: packageError !== "" || themeError !== ""
    || packageState.state === "unavailable" || packageState.state === "invalid"
    || themeState.degraded === true || Number(themeState.review || 0) > 0
  readonly property bool busy: packageRefreshing || themeRefreshing || actionKind !== ""

  function elideError(text, fallback) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    if (value === "") value = fallback
    return value.length > 180 ? value.substring(0, 177) + "…" : value
  }

  function refreshPackages() {
    if (packageProcess.running) return
    _packageOutput = ""
    _packageErrorOutput = ""
    packageError = ""
    _packageTimedOut = false
    packageRefreshing = true
    packageWatchdog.restart()
    packageProcess.running = true
  }

  function refreshThemes() {
    if (themeProcess.running || actionProcess.running) return
    _themeOutput = ""
    _themeErrorOutput = ""
    themeError = ""
    _themeTimedOut = false
    themeRefreshing = true
    themeWatchdog.restart()
    themeProcess.running = true
  }

  function refreshAll() {
    refreshPackages()
    refreshThemes()
  }

  function clearPackages() {
    var cleared = Model.emptyPackageState()
    cleared.state = "current"
    cleared.checkedEpoch = Math.floor(Date.now() / 1000)
    packageState = cleared
    packageError = ""
  }

  function preferredTab() {
    return Model.preferredTab(
      packageCount,
      themeCount,
      Number(themeState.review || 0),
      themeState.degraded === true,
      themeError
    )
  }

  function launchPackageUpdate() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"])
  }

  function updateTheme(theme) {
    if (!theme || actionProcess.running || theme.state !== "update") return
    var name = String(theme.name || "")
    var target = String(theme.targetCommit || "")
    if (name === "" || target === "") return

    actionName = name
    actionKind = "update"
    actionStatus = "Updating " + name + "…"
    actionError = ""
    actionStatusTimer.stop()
    _actionTimedOut = false
    _actionOutput = ""
    _actionErrorOutput = ""
    actionWatchdog.restart()
    actionProcess.command = ["omarchy-theme-update", name, target]
    actionProcess.running = true
  }

  function removeTheme(name) {
    var themeName = String(name || "")
    if (themeName === "" || actionProcess.running) return

    actionName = themeName
    actionKind = "remove"
    actionStatus = "Removing " + themeName + "…"
    actionError = ""
    actionStatusTimer.stop()
    _actionTimedOut = false
    _actionOutput = ""
    _actionErrorOutput = ""
    actionWatchdog.restart()
    actionProcess.command = ["omarchy-theme-remove", themeName]
    actionProcess.running = true
  }

  IpcHandler {
    target: "omarchy.system-update"

    function refresh(): void {
      root.refreshPackages()
    }

    function clear(): void {
      root.clearPackages()
    }
  }

  Timer {
    interval: 6 * 60 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshAll()
  }

  Timer {
    id: actionRefreshTimer
    interval: 250
    repeat: false
    onTriggered: root.refreshThemes()
  }

  Timer {
    id: packageWatchdog
    interval: 95000
    repeat: false
    onTriggered: {
      root._packageTimedOut = true
      packageProcess.running = false
      root.packageRefreshing = false
      root.packageError = "Package check timed out"
    }
  }

  Timer {
    id: themeWatchdog
    interval: 190000
    repeat: false
    onTriggered: {
      root._themeTimedOut = true
      themeProcess.running = false
      root.themeRefreshing = false
      root.themeError = "Theme check timed out"
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 3500
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: actionWatchdog
    interval: 65000
    repeat: false
    onTriggered: {
      var completedName = root.actionName
      root._actionTimedOut = true
      actionProcess.running = false
      root.actionStatus = ""
      root.actionError = "Theme action timed out" + (completedName === "" ? "" : ": " + completedName)
      root.actionName = ""
      root.actionKind = ""
      actionStatusTimer.restart()
      actionRefreshTimer.restart()
    }
  }

  Process {
    id: packageProcess
    running: false
    command: ["omarchy-update-status"]
    stdout: StdioCollector {
      id: packageStdout
      waitForEnd: true
      onStreamFinished: root._packageOutput = text
    }
    stderr: StdioCollector {
      id: packageStderr
      waitForEnd: true
      onStreamFinished: root._packageErrorOutput = text
    }
    onExited: function(exitCode) {
      packageWatchdog.stop()
      root.packageRefreshing = false
      if (root._packageTimedOut) return
      if (exitCode !== 0) {
        root.packageError = root.elideError(packageStderr.text || root._packageErrorOutput, "Package check failed")
        return
      }
      root.packageState = Model.parsePackageStatus(packageStdout.text || root._packageOutput)
      root.packageError = root.packageState.state === "invalid" ? "Package checker returned invalid data" : ""
    }
  }

  Process {
    id: themeProcess
    running: false
    command: ["omarchy-theme-update-status"]
    stdout: StdioCollector {
      id: themeStdout
      waitForEnd: true
      onStreamFinished: root._themeOutput = text
    }
    stderr: StdioCollector {
      id: themeStderr
      waitForEnd: true
      onStreamFinished: root._themeErrorOutput = text
    }
    onExited: function(exitCode) {
      themeWatchdog.stop()
      root.themeRefreshing = false
      if (root._themeTimedOut) return
      if (exitCode !== 0) {
        root.themeError = root.elideError(themeStderr.text || root._themeErrorOutput, "Theme check failed")
        return
      }
      root.themeState = Model.parseThemeStatus(themeStdout.text || root._themeOutput)
      root.themeError = root.themeState.degraded && root.themeState.themes.length === 0
        ? "Theme check did not complete"
        : ""
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: actionStdout
      waitForEnd: true
      onStreamFinished: root._actionOutput = text
    }
    stderr: StdioCollector {
      id: actionStderr
      waitForEnd: true
      onStreamFinished: root._actionErrorOutput = text
    }
    onExited: function(exitCode) {
      actionWatchdog.stop()
      if (root._actionTimedOut) return
      var completedName = root.actionName
      var completedKind = root.actionKind
      if (exitCode === 0) {
        root.actionStatus = completedKind === "remove"
          ? "Removed " + completedName
          : "Updated " + completedName
        root.actionError = ""
      } else {
        root.actionStatus = ""
        root.actionError = root.elideError(actionStderr.text || root._actionErrorOutput || actionStdout.text || root._actionOutput, "Theme action failed")
      }
      root.actionName = ""
      root.actionKind = ""
      actionStatusTimer.restart()
      actionRefreshTimer.restart()
    }
  }
}
