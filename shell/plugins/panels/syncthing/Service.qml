import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property string omarchyPath: ""
  property var pluginRegistry: null
  property var shell: null

  property int refreshIntervalSec: 60
  property bool actionableNotifications: true
  property int disconnectGraceMinutes: 15
  property bool panelOpen: false

  property bool installed: false
  property bool serviceRunning: false
  property bool authenticated: false
  property string serviceState: "inactive"
  property string overall: "unavailable"
  property string reason: ""
  property string message: ""
  property string guiUrl: ""
  property string myID: ""
  property string myName: "Syncthing"
  property real syncPercent: 100
  property double totalNeedBytes: 0
  property int totalNeedItems: 0
  property var folders: []
  property var devices: []
  property var pendingDevices: []
  property var pendingFolders: []
  property var systemErrors: []

  property bool refreshing: false
  property string actionStatus: ""
  property string lastError: ""
  property int _desiredService: -1
  property int _eventSince: -1
  property bool _baselineReady: false
  property bool _healthBaselineReady: false
  property var _problemKeys: []
  property var _pendingKeys: []
  property var _connectionStates: ({})
  property var _disconnectedSince: ({})
  property var _disconnectNotified: ({})
  property string _foldersJson: "[]"
  property string _devicesJson: "[]"
  property string _pendingDevicesJson: "[]"
  property string _pendingFoldersJson: "[]"
  property string _systemErrorsJson: "[]"

  readonly property bool widgetEnabled: {
    if (!pluginRegistry) return false
    var revision = pluginRegistry.registryRevision
    return revision >= 0 && pluginRegistry.inBar("omarchy.syncthing")
  }
  readonly property bool active: _desiredService === -1 ? serviceRunning : _desiredService === 1
  readonly property bool syncing: overall === "syncing" || overall === "scanning"
  readonly property bool hasAttention: overall === "error" || overall === "attention"
  readonly property bool busy: refreshing || actionProcess.running || serviceProcess.running
  readonly property string statusText: Model.statusText({
    installed: installed,
    running: serviceRunning,
    authenticated: authenticated,
    serviceState: serviceState,
    reason: reason,
    overall: overall,
    syncPercent: syncPercent
  })
  readonly property string helperPath: (omarchyPath || "") + "/shell/plugins/panels/syncthing/syncthing.py"

  function setting(settings, name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(settings, name, fallback, min, max) {
    var number = parseInt(String(setting(settings, name, fallback)), 10)
    if (!isFinite(number)) number = fallback
    return Math.max(min, Math.min(max, number))
  }

  function configure(settings) {
    refreshIntervalSec = intSetting(settings, "refreshIntervalSec", 60, 15, 3600)
    actionableNotifications = setting(settings, "actionableNotifications", true) !== false
    disconnectGraceMinutes = intSetting(settings, "disconnectGraceMinutes", 15, 1, 1440)
  }

  function updateArray(name, jsonName, rows) {
    var values = Array.isArray(rows) ? rows : []
    var serialized = JSON.stringify(values)
    if (root[jsonName] === serialized) return
    root[jsonName] = serialized
    root[name] = values
  }

  function refresh() {
    if (!widgetEnabled || statusProcess.running || omarchyPath === "") return
    refreshing = true
    statusProcess.command = ["python3", helperPath, "status"]
    statusProcess.running = true
  }

  function applySnapshot(raw) {
    var previous = {
      running: serviceRunning,
      authenticated: authenticated,
      folders: folders,
      devices: devices,
      pendingDevices: pendingDevices,
      pendingFolders: pendingFolders
    }
    var data = Model.parseSnapshot(raw)
    if (!data.ok) {
      lastError = String(data.lastError || data.message || "Could not read Syncthing status")
      return
    }

    installed = data.installed === true
    serviceRunning = data.running === true
    authenticated = data.authenticated === true
    serviceState = String(data.serviceState || (serviceRunning ? "active" : "inactive"))
    reason = String(data.reason || "")
    message = String(data.message || "")
    overall = String(data.overall || (serviceRunning ? "unknown" : "stopped"))
    guiUrl = String(data.guiUrl || "")
    myID = String(data.myID || "")
    myName = String(data.myName || "Syncthing")
    syncPercent = Number(data.syncPercent === undefined ? 100 : data.syncPercent)
    totalNeedBytes = Number(data.totalNeedBytes || 0)
    totalNeedItems = Number(data.totalNeedItems || 0)
    updateArray("folders", "_foldersJson", data.folders)
    updateArray("devices", "_devicesJson", data.devices)
    updateArray("pendingDevices", "_pendingDevicesJson", data.pendingDevices)
    updateArray("pendingFolders", "_pendingFoldersJson", data.pendingFolders)
    updateArray("systemErrors", "_systemErrorsJson", data.systemErrors)

    lastError = ""

    var nextProblems = authenticated ? Model.problemKeys(data) : _problemKeys
    var nextPending = authenticated ? Model.pendingKeys(data) : _pendingKeys
    if (_baselineReady) notifyTransitions(previous, data, nextProblems, nextPending, _healthBaselineReady)
    if (_desiredService !== -1 && serviceRunning === (_desiredService === 1)) _desiredService = -1
    if (authenticated) {
      _problemKeys = nextProblems
      _pendingKeys = nextPending
      trackConnections(previous.devices, data.devices, !_healthBaselineReady)
      _healthBaselineReady = true
    }
    _baselineReady = true

    if (authenticated && serviceRunning) startEvents()
    else stopEvents()
  }

  function notifyTransitions(previous, current, nextProblems, nextPending, notifyHealth) {
    if (!actionableNotifications || !widgetEnabled) return
    var addedProblems = notifyHealth ? Model.addedKeys(_problemKeys, nextProblems) : []
    var addedPending = notifyHealth ? Model.addedKeys(_pendingKeys, nextPending) : []
    if (addedProblems.length > 0) {
      notify("Syncthing needs attention. Open the panel for details.")
    }
    if (addedPending.length > 0) {
      var deviceCount = current.pendingDevices.length
      var folderCount = current.pendingFolders.length
      var parts = []
      if (deviceCount > 0) parts.push(deviceCount + (deviceCount === 1 ? " device" : " devices"))
      if (folderCount > 0) parts.push(folderCount + (folderCount === 1 ? " folder" : " folders"))
      notify("Incoming sharing request: " + parts.join(" and ") + ".")
    }
    if (previous.authenticated && !current.authenticated && current.running) {
      notify("Omarchy can no longer authenticate with the local Syncthing API.")
    }
    if (previous.running && !current.running && _desiredService !== 0) {
      notify(current.serviceState === "failed" ? "The Syncthing user service failed." : "The Syncthing user service stopped unexpectedly.")
    }
  }

  function trackConnections(previousDevices, currentDevices, initializing) {
    var nextStates = ({})
    var nextSince = ({})
    var nextNotified = ({})
    var now = Date.now()
    var rows = Array.isArray(currentDevices) ? currentDevices : []
    for (var i = 0; i < rows.length; i++) {
      var device = rows[i] || ({})
      var id = String(device.id || "")
      if (!id || device.paused === true) continue
      var connected = device.connected === true
      nextStates[id] = connected
      if (connected) continue
      if (!initializing && _connectionStates[id] === true) nextSince[id] = now
      else if (_disconnectedSince[id] !== undefined) nextSince[id] = _disconnectedSince[id]
      if (_disconnectNotified[id] === true) nextNotified[id] = true
    }
    _connectionStates = nextStates
    _disconnectedSince = nextSince
    _disconnectNotified = nextNotified
  }

  function checkDisconnectedDevices() {
    if (!actionableNotifications || !widgetEnabled) return
    var now = Date.now()
    var threshold = disconnectGraceMinutes * 60000
    var notified = ({})
    for (var existing in _disconnectNotified) notified[existing] = _disconnectNotified[existing]
    for (var id in _disconnectedSince) {
      if (notified[id] === true || now - Number(_disconnectedSince[id]) < threshold) continue
      var device = Model.deviceById(devices, id)
      if (!device || device.connected === true || device.paused === true) continue
      notify(String(device.name || "A Syncthing device") + " has been disconnected for " + disconnectGraceMinutes + " minutes.")
      notified[id] = true
    }
    _disconnectNotified = notified
  }

  function notify(text) {
    Quickshell.execDetached([
      "omarchy-notification-send",
      "--exec", "omarchy-shell shell summon omarchy.syncthing",
      "--app-name", "syncthing",
      "-g", "󰑐",
      "Syncthing", String(text || "")
    ])
  }

  function startEvents() {
    if (!widgetEnabled || eventProcess.running || eventRestart.running) return
    eventProcess.command = ["python3", helperPath, "events", "--since", String(_eventSince), "--timeout", "25"]
    eventProcess.running = true
  }

  function stopEvents() {
    eventRestart.stop()
    if (eventProcess.running) eventProcess.running = false
    _eventSince = -1
  }

  function applyEvents(raw) {
    var data
    try { data = JSON.parse(String(raw || "")) }
    catch (error) { return false }
    if (!data || data.ok !== true) return false
    _eventSince = Number(data.lastId || 0)
    if (Array.isArray(data.events) && data.events.length > 0) delayedRefresh.restart()
    return true
  }

  function toggleService() {
    if (!installed || serviceProcess.running) return
    var starting = !active
    _desiredService = starting ? 1 : 0
    actionStatus = starting ? "Starting Syncthing…" : "Stopping Syncthing…"
    serviceProcess.command = ["systemctl", "--user", starting ? "start" : "stop", "syncthing.service"]
    serviceProcess.running = true
  }

  function scan(folderId) {
    var args = ["python3", helperPath, "scan"]
    if (folderId) args.push(String(folderId))
    runAction(args, folderId ? "Rescanning folder…" : "Rescanning all folders…")
  }

  function setFolderPaused(folderId, paused) {
    if (!folderId) return
    runAction(["python3", helperPath, "set-paused", String(folderId), paused ? "true" : "false"],
      paused ? "Pausing folder…" : "Resuming folder…")
  }

  function runAction(command, label) {
    if (!authenticated || actionProcess.running) return
    actionStatus = label
    actionProcess.command = command
    actionProcess.running = true
  }

  function openWebUi() {
    if (guiUrl) Quickshell.execDetached(["omarchy-launch-browser", guiUrl])
  }

  function openFolder(folder) {
    if (folder && folder.path) Quickshell.execDetached(["uwsm-app", "--", "xdg-open", String(folder.path)])
  }

  function copyDeviceId(device) {
    if (!device || !device.id) return
    Quickshell.execDetached(["wl-copy", "--", String(device.id)])
    actionStatus = "Copied " + String(device.name || "device") + " ID"
    actionStatusTimer.restart()
  }

  function reset() {
    stopEvents()
    if (statusProcess.running) statusProcess.running = false
    refreshing = false
    _baselineReady = false
    _healthBaselineReady = false
    _problemKeys = []
    _pendingKeys = []
    _connectionStates = ({})
    _disconnectedSince = ({})
    _disconnectNotified = ({})
  }

  onWidgetEnabledChanged: {
    if (widgetEnabled) refresh()
    else reset()
  }

  Timer {
    id: refreshTimer
    interval: root.panelOpen || root.syncing ? Math.min(5000, root.refreshIntervalSec * 1000) : root.refreshIntervalSec * 1000
    repeat: true
    running: root.widgetEnabled
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 500
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: eventRestart
    interval: 300
    repeat: false
    onTriggered: root.startEvents()
  }

  Timer {
    id: disconnectTimer
    interval: 60000
    repeat: true
    running: root.widgetEnabled
    onTriggered: root.checkDisconnectedDevices()
  }

  Timer {
    id: actionStatusTimer
    interval: 2400
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.refreshing = false
      var output = String(statusStdout.text || "")
      if (exitCode === 0 && output.trim() !== "") root.applySnapshot(output)
      else root.lastError = String(statusStderr.text || "Could not read Syncthing status").trim()
    }
  }

  Process {
    id: eventProcess
    running: false
    command: []
    stdout: StdioCollector { id: eventStdout; waitForEnd: true }
    onExited: function(exitCode) {
      var accepted = exitCode === 0 && root.applyEvents(eventStdout.text)
      if (root.widgetEnabled && root.authenticated && root.serviceRunning) {
        eventRestart.interval = accepted ? 300 : 5000
        eventRestart.restart()
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.lastError = ""
      else {
        var output = String(actionStderr.text || actionStdout.text || "Syncthing action failed").trim()
        try {
          var parsed = JSON.parse(String(actionStdout.text || ""))
          if (parsed && parsed.message) output = String(parsed.message)
        } catch (error) {}
        root.lastError = output
        root.actionStatus = ""
      }
      actionStatusTimer.restart()
      delayedRefresh.restart()
    }
  }

  Process {
    id: serviceProcess
    running: false
    command: []
    stderr: StdioCollector { id: serviceStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._desiredService = -1
        root.lastError = String(serviceStderr.text || "Could not control syncthing.service").trim()
      } else {
        root.lastError = ""
      }
      actionStatusTimer.restart()
      delayedRefresh.restart()
    }
  }
}
