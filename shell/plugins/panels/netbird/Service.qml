import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool running: false
  property bool needsLogin: false

  // Optimistic off state so the UI reacts the instant you click, rather than
  // waiting for the next status refresh. _desired is -1 while we just follow
  // the real state, or 0/1 while a toggle is still catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  property bool refreshing: false
  property string daemonStatus: "Unknown"
  property string statusText: "Checking…"
  property string selfName: ""
  property string selfFqdn: ""
  property string selfIp: ""
  property string profileName: ""
  property bool managementConnected: false
  property var peers: []
  property var profiles: []
  property string selectedProfileId: ""
  property string selectedProfileLabel: ""
  property string switchingProfileId: ""
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property bool busy: whichProcess.running || statusProcess.running || profilesProcess.running || actionProcess.running || loginProcess.running || switchProcess.running

  property string _statusOutput: ""
  property string _statusError: ""
  property string _profilesOutput: ""
  property string _profilesError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _loginOutput: ""
  property string _loginError: ""
  property bool _loginInProgress: false
  property string _switchOutput: ""
  property string _switchError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function shortName(fqdn) {
    return Model.shortName(fqdn)
  }

  function osIcon(os) {
    return Model.osIcon(os)
  }

  function copyToClipboard(value, label) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
  }

  function copyPeerIp(peer) {
    if (!peer) return
    copyToClipboard(peer.NetbirdIP || "", (peer.HostName || "Peer") + " IP")
  }

  function copyPeerName(peer) {
    if (!peer) return
    copyToClipboard(peer.HostName || "", (peer.HostName || "Peer") + " name")
  }

  function copyPeerFqdn(peer) {
    if (!peer) return
    copyToClipboard(peer.DNSName || "", (peer.HostName || "Peer") + " FQDN")
  }

  function refresh() {
    if (installed) {
      refreshStatusAndProfiles()
      return
    }
    if (!whichProcess.running) {
      refreshing = true
      whichProcess.command = ["which", "netbird"]
      whichProcess.running = true
    }
  }

  function refreshStatusAndProfiles() {
    if (!installed) return
    var launched = false
    if (!statusProcess.running) {
      _statusOutput = ""
      _statusError = ""
      refreshing = true
      statusProcess.command = ["netbird", "status", "--json"]
      statusProcess.running = true
      launched = true
    }
    if (!profilesProcess.running && (profiles.length === 0)) {
      _profilesOutput = ""
      _profilesError = ""
      profilesProcess.command = ["netbird", "profile", "list"]
      profilesProcess.running = true
      launched = true
    }
    if (launched && !pollWatchdog.running) pollWatchdog.start()
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function resetUnavailable(message) {
    running = false
    needsLogin = false
    _desired = -1
    daemonStatus = "Unavailable"
    statusText = message
    selfName = ""
    selfFqdn = ""
    selfIp = ""
    profileName = ""
    managementConnected = false
    peers = []
    profiles = []
    selectedProfileId = ""
    selectedProfileLabel = ""
    switchingProfileId = ""
  }

  function parseStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      resetUnavailable(parsed.message || "Status error")
      lastError = parsed.error || "Failed to parse netbird status"
      console.warn("netbird", lastError)
      return
    }
    if (parsed.unavailable) {
      resetUnavailable(parsed.message || "Disconnected")
      return
    }

    daemonStatus = parsed.daemonStatus
    running = parsed.running
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    needsLogin = parsed.needsLogin
    selfName = parsed.selfName
    selfFqdn = parsed.selfFqdn
    selfIp = parsed.selfIp
    profileName = parsed.profileName
    managementConnected = parsed.managementConnected
    peers = parsed.running ? parsed.peers : []

    if (needsLogin) statusText = "Needs login"
    else if (running) {
      statusText = "Connected"
      _loginInProgress = false
      loginTimeoutTimer.stop()
    } else if (daemonStatus === "Disconnected") {
      statusText = "Disconnected"
    } else {
      statusText = daemonStatus
    }
    lastError = ""
  }

  function parseProfiles(raw) {
    var parsed = Model.parseProfiles(raw)
    profiles = parsed.profiles
    selectedProfileId = parsed.selectedProfileId
    selectedProfileLabel = parsed.selectedProfileLabel
  }

  function toggleNetbird() {
    if (!installed) return
    if (active) down()
    else loginOrUp()
  }

  function down() {
    _desired = 0
    runAction(["netbird", "down"])
  }

  function loginOrUp() {
    if (!installed || loginProcess.running) return
    _desired = -1
    _loginOutput = ""
    _loginError = ""
    if (needsLogin) actionStatus = "Starting NetBird login…"
    else _desired = 1
    _loginInProgress = needsLogin
    loginProcess.command = ["netbird", "up"]
    loginProcess.running = true
    if (needsLogin) loginTimeoutTimer.restart()
  }

  function switchProfile(id) {
    var profileId = String(id || "")
    if (!installed || profileId === "" || profileId === selectedProfileId || switchProcess.running) return
    _switchOutput = ""
    _switchError = ""
    switchingProfileId = profileId
    switchProcess.command = ["netbird", "profile", "select", profileId]
    switchProcess.running = true
  }

  function runAction(command, label) {
    if (actionProcess.running) return
    _actionOutput = ""
    _actionError = ""
    actionStatus = label || ""
    actionProcess.command = command
    actionProcess.running = true
  }

  function openAuthUrlFrom(text) {
    var match = String(text || "").match(/https?:\/\/\S+/)
    if (match && match[0]) {
      _loginInProgress = false
      loginTimeoutTimer.stop()
      Quickshell.execDetached(["omarchy-launch-browser", match[0]])
      return true
    }
    return false
  }

  function handleLoginOutput(data, isError) {
    var text = String(data || "")
    if (isError) _loginError += text + "\n"
    else _loginOutput += text + "\n"
    if (_loginInProgress) openAuthUrlFrom(text)
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    // After a fresh boot the startup poll usually lands before netbird has
    // connected, which left the icon stale until the next periodic refresh.
    // Poll quickly until the service shows up, or give up after ~30 seconds.
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      ticks += 1
      if (root.running || ticks >= 15) startupRamp.running = false
      else root.refresh()
    }
  }

  Timer {
    id: delayedRefresh
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
      if (profilesProcess.running) profilesProcess.running = false
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: loginTimeoutTimer
    interval: 10000
    repeat: false
    onTriggered: {
      if (!root._loginInProgress) return
      var combined = String(root._loginOutput || "") + "\n" + String(root._loginError || "")
      if (!root.openAuthUrlFrom(combined)) {
        root._loginInProgress = false
        root.actionStatus = "NetBird login link not available yet"
      }
    }
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refreshStatusAndProfiles()
      else {
        root.refreshing = false
        root.resetUnavailable("Not installed")
      }
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.parseStatus(stdout)
      else {
        root.resetUnavailable("Disconnected")
        root.lastError = stderr.trim()
      }
    }
  }

  Process {
    id: profilesProcess
    running: false
    command: []
    stdout: StdioCollector { id: profilesStdout; waitForEnd: true; onStreamFinished: root._profilesOutput = text }
    stderr: StdioCollector { id: profilesStderr; waitForEnd: true; onStreamFinished: root._profilesError = text }
    onExited: function(exitCode) {
      var stdout = String(profilesStdout.text || root._profilesOutput || "")
      if (exitCode === 0) root.parseProfiles(stdout)
      else root.parseProfiles("")
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || root._actionOutput || "")
      var stderr = String(actionStderr.text || root._actionError || "")
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = elideStatus(stderr || stdout || "NetBird command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: loginProcess
    running: false
    command: []
    stdout: SplitParser { onRead: function(data) { root.handleLoginOutput(data, false) } }
    stderr: SplitParser { onRead: function(data) { root.handleLoginOutput(data, true) } }
    onExited: function(exitCode) {
      var combined = String(root._loginOutput || "") + "\n" + String(root._loginError || "")
      var opened = root.openAuthUrlFrom(combined)
      if (exitCode !== 0 && !opened) {
        root._desired = -1
        root._loginInProgress = false
        root.lastError = elideStatus(combined || "netbird up failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else if (!opened) {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: switchProcess
    running: false
    command: []
    stdout: StdioCollector { id: switchStdout; waitForEnd: true; onStreamFinished: root._switchOutput = text }
    stderr: StdioCollector { id: switchStderr; waitForEnd: true; onStreamFinished: root._switchError = text }
    onExited: function(exitCode) {
      var stdout = String(switchStdout.text || root._switchOutput || "")
      var stderr = String(switchStderr.text || root._switchError || "")
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Profile switch failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
        // Force profile refresh after switch, but avoid clobbering an in-flight refresh.
        if (!profilesProcess.running) {
          _profilesOutput = ""
          _profilesError = ""
          profilesProcess.command = ["netbird", "profile", "list"]
          profilesProcess.running = true
        }
      }
      root.switchingProfileId = ""
      delayedRefresh.restart()
    }
  }
}