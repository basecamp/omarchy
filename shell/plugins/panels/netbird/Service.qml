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

  // Optimistic toggle state: -1 follows the real state, 0/1 while a toggle is
  // still catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  property string backendState: "Unknown"
  property string statusText: "Checking…"
  property string selfName: ""
  property string selfFqdn: ""
  property string selfIp: ""
  property string managementUrl: ""
  property bool managementConnected: false
  property string managementError: ""
  property string signalUrl: ""
  property bool signalConnected: false
  property string signalError: ""
  property int relaysAvailable: 0
  property int relaysTotal: 0
  property string wireguardMode: ""
  property int wireguardPort: 0
  property string sessionExpiresAt: ""
  property int connectedPeers: 0
  property int totalPeers: 0
  property string authUrl: ""
  property var peers: []
  property var routes: []
  property var profiles: []
  property string selectedProfileName: ""
  property string selectedProfileLabel: ""
  property string switchingProfileKey: ""
  property string settingRouteId: ""
  property bool daemonInactive: false
  property bool permissionDenied: false
  property var nameserverGroups: []
  property bool managedDns: false
  property string systemDnsProvider: ""
  property bool fixingDns: false
  property string actionStatus: ""
  property string lastError: ""

  // Non-empty when NetBird is serving DNS for its own domains and the system
  // DNS provider overrides it; the value is the provider doing the overriding.
  readonly property string dnsOverride: Model.dnsOverrideWarning(managedDns, systemDnsProvider)

  // Relative labels ("3h ago", "in 38m") need recomputing as time passes, not
  // only on poll.
  property double nowMs: Date.now()
  readonly property var sessionExpiry: Model.sessionExpiry(sessionExpiresAt, nowMs)

  readonly property var healthRows: Model.healthRows({
    managementUrl: managementUrl,
    managementConnected: managementConnected,
    managementError: managementError,
    signalUrl: signalUrl,
    signalConnected: signalConnected,
    signalError: signalError,
    relaysAvailable: relaysAvailable,
    relaysTotal: relaysTotal,
    wireguardMode: wireguardMode,
    wireguardPort: wireguardPort
  })

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property bool busy: whichProcess.running || statusProcess.running || routesProcess.running || profilesProcess.running || actionProcess.running || loginProcess.running || profileProcess.running || routeProcess.running || daemonProcess.running || dnsProcess.running || dnsFixProcess.running

  // Older CLIs answer `routes list`, newer ones `networks list`. Walk the
  // candidates once, latch onto whichever lands, stop asking if none do.
  readonly property var routeCommands: [
    ["netbird", "routes", "list", "--json"],
    ["netbird", "routes", "list"],
    ["netbird", "networks", "list"]
  ]
  property int routeCommandIndex: 0
  property bool routesSupported: true
  readonly property string routeVerb: routeCommandIndex >= 2 ? "networks" : "routes"

  // Profiles are newer than some installed CLIs, and no release ships
  // `profile list --json` — walk to the table form before deciding the CLI has
  // no profiles at all.
  // --show-id before the bare table: names may be duplicated, and NetBird
  // refuses to select an ambiguous name — only the ID is unique.
  readonly property var profileCommands: [
    ["netbird", "profile", "list", "--json"],
    ["netbird", "profile", "list", "--show-id"],
    ["netbird", "profile", "list"]
  ]
  property int profileCommandIndex: 0
  property bool profilesSupported: true

  property string _statusOutput: ""
  property string _statusError: ""
  property string _routesOutput: ""
  property string _routesError: ""
  property string _profilesOutput: ""
  property string _profilesError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _loginOutput: ""
  property string _loginError: ""
  property bool _loginInProgress: false
  property bool _loginUrlOpened: false
  property string _preLoginAuthUrl: ""
  property double _lastProfilesRefreshMs: 0
  property string _profileOutput: ""
  property string _profileError: ""
  property string _routeOutput: ""
  property string _routeError: ""
  property string _daemonOutput: ""
  property string _daemonError: ""
  property string _dnsOutput: ""
  property string _dnsError: ""
  property string _dnsFixOutput: ""
  property string _dnsFixError: ""

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

  function osIcon(os) {
    return Model.osIcon(os)
  }

  function connectionLabel(peer) {
    return Model.connectionLabel(peer)
  }

  function peerActivity(peer) {
    return Model.peerActivity(peer, nowMs)
  }

  function profileLabel(profile) {
    return Model.profileLabel(profile)
  }

  function copyToClipboard(value, label) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
  }

  function copyPeerIp(peer) {
    if (!peer) return
    copyToClipboard(peer.IP, String(peer.DisplayName || "") + " IP")
  }

  function copyPeerName(peer) {
    if (!peer) return
    copyToClipboard(peer.DisplayName, String(peer.DisplayName || "") + " name")
  }

  function copyPeerFqdn(peer) {
    if (!peer) return
    copyToClipboard(peer.Fqdn, String(peer.DisplayName || "") + " domain name")
  }

  function refresh(forceProfiles) {
    if (installed) {
      refreshStatusAndRoutes(forceProfiles === true)
      return
    }
    if (!whichProcess.running) {
      whichProcess.command = ["which", "netbird"]
      whichProcess.running = true
    }
  }

  function refreshStatusAndRoutes(forceProfiles) {
    if (!installed) return
    var launched = false
    if (!statusProcess.running) {
      _statusOutput = ""
      _statusError = ""
      statusProcess.command = ["netbird", "status", "--json"]
      statusProcess.running = true
      launched = true
    }
    if (routesSupported && !routesProcess.running) {
      _routesOutput = ""
      _routesError = ""
      routesProcess.command = routeCommands[routeCommandIndex]
      routesProcess.running = true
      launched = true
    }
    // Read the provider once, then only while NetBird serves DNS — the only
    // time it can warn; managedDns turning true re-arms this.
    if (!dnsProcess.running && (systemDnsProvider === "" || managedDns)) {
      _dnsOutput = ""
      _dnsError = ""
      dnsProcess.command = ["omarchy-dns"]
      dnsProcess.running = true
      launched = true
    }
    var now = Date.now()
    var shouldRefreshProfiles = profilesSupported && (forceProfiles === true || profiles.length === 0 || now - _lastProfilesRefreshMs > 60000)
    if (shouldRefreshProfiles && !profilesProcess.running) {
      _profilesOutput = ""
      _profilesError = ""
      _lastProfilesRefreshMs = now
      profilesProcess.command = profileCommands[profileCommandIndex]
      profilesProcess.running = true
      launched = true
    }
    // Arm once and leave it: restarting every refresh would push the deadline
    // ahead of a hung process forever when the interval is under the timeout.
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
    backendState = "Unavailable"
    statusText = message
    // Failure paths re-set the applicable flag right after; anything else
    // arriving here must not keep a stale daemon/socket notice alive.
    daemonInactive = false
    permissionDenied = false
    lastError = ""
    selfName = ""
    selfFqdn = ""
    selfIp = ""
    managementUrl = ""
    managementConnected = false
    managementError = ""
    signalUrl = ""
    signalConnected = false
    signalError = ""
    relaysAvailable = 0
    relaysTotal = 0
    wireguardMode = ""
    wireguardPort = 0
    sessionExpiresAt = ""
    connectedPeers = 0
    totalPeers = 0
    authUrl = ""
    peers = []
    routes = []
    nameserverGroups = []
    managedDns = false
    profiles = []
    selectedProfileName = ""
    selectedProfileLabel = ""
    switchingProfileKey = ""
    settingRouteId = ""
  }

  // Returns false only when the payload would not parse, so the caller can
  // hand the raw output to the failure classifier instead.
  function parseStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      resetUnavailable(parsed.message || "Status error")
      lastError = parsed.error || "Failed to parse netbird status"
      console.warn("netbird", lastError)
      return false
    }
    if (parsed.unavailable) {
      resetUnavailable(parsed.message || "Disconnected")
      return true
    }

    daemonInactive = false
    permissionDenied = false
    backendState = parsed.backendState
    running = parsed.running
    // Reality caught up to the pending toggle — stop overriding.
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    needsLogin = parsed.needsLogin
    selfName = parsed.selfName
    selfFqdn = parsed.selfFqdn
    selfIp = parsed.selfIp
    managementUrl = parsed.managementUrl
    managementConnected = parsed.managementConnected
    managementError = parsed.managementError
    signalUrl = parsed.signalUrl
    signalConnected = parsed.signalConnected
    signalError = parsed.signalError
    relaysAvailable = parsed.relaysAvailable
    relaysTotal = parsed.relaysTotal
    wireguardMode = parsed.wireguardMode
    wireguardPort = parsed.wireguardPort
    sessionExpiresAt = parsed.sessionExpiresAt
    connectedPeers = parsed.connectedPeers
    totalPeers = parsed.totalPeers
    peers = parsed.running ? parsed.peers : []
    nameserverGroups = parsed.running ? parsed.nameserverGroups : []
    managedDns = parsed.running && parsed.managedDns
    if (!parsed.running) routes = []

    if (needsLogin) statusText = backendState === "LoginFailed" ? "Login failed" : "Needs login"
    else if (running) {
      statusText = "Connected"
      _loginInProgress = false
      _loginUrlOpened = false
      _preLoginAuthUrl = ""
      loginTimeoutTimer.stop()
    } else if (backendState === "Connecting") {
      statusText = "Connecting…"
    } else {
      statusText = "Disconnected"
    }
    lastError = ""
    return true
  }

  function parseRoutes(raw) {
    routes = running ? Model.sortRoutes(Model.parseRoutes(raw)) : []
  }

  function parseProfiles(raw) {
    var parsed = Model.parseProfiles(raw)
    profiles = parsed.profiles
    selectedProfileName = parsed.selectedProfileName
    selectedProfileLabel = parsed.selectedProfileLabel
  }

  function toggleNetbird() {
    if (!installed) return
    if (active) down()
    else loginOrUp()
  }

  function down() {
    // The greyed icon already conveys the optimistic off; only surface failures.
    _desired = 0
    runAction(["netbird", "down"])
  }

  function loginOrUp() {
    if (!installed || loginProcess.running) return
    _desired = -1
    var plan = Model.loginPlan(needsLogin, authUrl)
    if (plan.authUrl !== "") {
      _loginUrlOpened = false
      openAuthUrlFrom(plan.authUrl, true)
      return
    }
    _loginOutput = ""
    _loginError = ""
    if (needsLogin) actionStatus = "Starting NetBird login…"
    else _desired = 1
    _loginInProgress = needsLogin
    _loginUrlOpened = false
    _preLoginAuthUrl = authUrl
    loginProcess.command = plan.command
    loginProcess.running = true
    if (needsLogin) loginTimeoutTimer.restart()
  }

  function profileKey(profile) {
    if (!profile) return ""
    return String(profile.id || "") !== "" ? String(profile.id) : String(profile.name || "")
  }

  function switchProfile(profile) {
    var key = profileKey(profile)
    if (!installed || key === "" || (profile && profile.selected === true) || profileProcess.running) return
    _profileOutput = ""
    _profileError = ""
    switchingProfileKey = key
    profileProcess.command = ["netbird", "profile", "select", key]
    profileProcess.running = true
  }

  function toggleRoute(route) {
    if (!installed || !running || !route || routeProcess.running) return
    var id = String(route.id || "")
    if (id === "") return
    _routeOutput = ""
    _routeError = ""
    settingRouteId = id
    // Bare `select` replaces the whole selection; toggling one row must not
    // turn the others off.
    routeProcess.command = route.Selected === true
      ? ["netbird", routeVerb, "deselect", id]
      : ["netbird", routeVerb, "select", "--append", id]
    routeProcess.running = true
  }

  function startDaemon() {
    if (daemonProcess.running) return
    _daemonOutput = ""
    _daemonError = ""
    actionStatus = "Starting the NetBird daemon..."
    daemonProcess.command = ["pkexec", "systemctl", "start", "netbird.service"]
    daemonProcess.running = true
  }

  // omarchy-dns escalates on its own; the polkit prompt comes from there.
  function useDhcpDns() {
    if (dnsFixProcess.running) return
    _dnsFixOutput = ""
    _dnsFixError = ""
    fixingDns = true
    actionStatus = "Handing DNS back to DHCP..."
    dnsFixProcess.command = ["omarchy-dns", "DHCP"]
    dnsFixProcess.running = true
  }

  readonly property string adminConsoleUrl: Model.adminConsoleUrl(managementUrl)

  function openAdminConsole() {
    Quickshell.execDetached(["omarchy-launch-browser", adminConsoleUrl])
  }

  function runAction(command, label) {
    if (actionProcess.running) return
    _actionOutput = ""
    _actionError = ""
    actionStatus = label || ""
    actionProcess.command = command
    actionProcess.running = true
  }

  function openAuthUrlFrom(text, allowFallback) {
    if (_loginUrlOpened) return true
    var match = String(text || "").match(/https?:\/\/\S+/)
    var url = match && match[0] ? match[0] : (allowFallback === true ? authUrl : "")
    if (url !== "") {
      // Turning on ended up needing browser auth — stop pretending we're up.
      _desired = -1
      _loginUrlOpened = true
      _loginInProgress = false
      authUrl = url
      loginTimeoutTimer.stop()
      Quickshell.execDetached(["omarchy-launch-browser", url])
      return true
    }
    return false
  }

  function handleLoginOutput(data, isError) {
    var text = String(data || "")
    if (isError) _loginError += text + "\n"
    else _loginOutput += text + "\n"
    if (_loginInProgress && !_loginUrlOpened) openAuthUrlFrom(text, false)
  }

  // A daemon that is not running and a socket this user may not touch both
  // stop the panel dead, but only one of them has a button that fixes it.
  function noteStatusFailure(stderr) {
    var text = String(stderr || "")
    if (text.trim() === "") {
      // Nothing to classify, but an empty lastError would show nothing at all.
      daemonInactive = false
      permissionDenied = false
      lastError = "NetBird status failed"
      return
    }
    if (/permission denied/i.test(text)) {
      permissionDenied = true
      daemonInactive = false
      lastError = "This user cannot reach the NetBird daemon socket"
      return
    }
    if (Model.isPermissionError(text)) {
      daemonInactive = true
      permissionDenied = false
      lastError = "The NetBird daemon is not running"
      return
    }
    daemonInactive = false
    permissionDenied = false
    lastError = elideStatus(text)
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
    // The first poll after boot usually beats the daemon connecting; poll
    // quickly until it shows up, give up after ~30 seconds.
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
    // A process cannot be restarted from its own exit handler; step out
    // through the event loop.
    id: routesRetry
    interval: 50
    repeat: false
    onTriggered: {
      if (!root.installed || !root.routesSupported || routesProcess.running) return
      root._routesOutput = ""
      root._routesError = ""
      routesProcess.command = root.routeCommands[root.routeCommandIndex]
      routesProcess.running = true
    }
  }

  Timer {
    // Same reason as routesRetry: step out of the exit handler before relaunching.
    id: profilesRetry
    interval: 50
    repeat: false
    onTriggered: {
      if (!root.installed || !root.profilesSupported || profilesProcess.running) return
      root._profilesOutput = ""
      root._profilesError = ""
      root._lastProfilesRefreshMs = Date.now()
      profilesProcess.command = root.profileCommands[root.profileCommandIndex]
      profilesProcess.running = true
    }
  }

  Timer {
    // Polls are skipped while their process still runs, so one that never
    // exits stops refreshes for good. Reap stragglers inside the interval.
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
      if (routesProcess.running) routesProcess.running = false
      if (profilesProcess.running) profilesProcess.running = false
      if (dnsProcess.running) dnsProcess.running = false
    }
  }

  Timer {
    id: clockTimer
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
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
      if (!root._loginInProgress || root._loginUrlOpened) return
      if (!root.openAuthUrlFrom(root.authUrl, true)) {
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
      if (root.installed) root.refreshStatusAndRoutes()
      else root.resetUnavailable("Not installed")
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      // A logged-out daemon returns usable JSON with a non-zero exit, so read
      // the payload first. gRPC retry noise can land on stdout — unparseable
      // output still needs classifying, or the daemon notice never shows.
      if (stdout.trim() !== "") {
        if (!root.parseStatus(stdout) && exitCode !== 0) {
          root.noteStatusFailure(stderr.trim() !== "" ? stderr : stdout)
        }
        return
      }
      if (exitCode === 0) root.parseStatus(stdout)
      else {
        root.resetUnavailable("Disconnected")
        root.noteStatusFailure(stderr.trim() !== "" ? stderr : stdout)
      }
    }
  }

  Process {
    id: routesProcess
    running: false
    command: []
    stdout: StdioCollector { id: routesStdout; waitForEnd: true; onStreamFinished: root._routesOutput = text }
    stderr: StdioCollector { id: routesStderr; waitForEnd: true; onStreamFinished: root._routesError = text }
    onExited: function(exitCode) {
      var stdout = String(routesStdout.text || root._routesOutput || "")
      var stderr = String(routesStderr.text || root._routesError || "")
      if (exitCode === 0) {
        root.parseRoutes(stdout)
        return
      }
      // Walk to the next spelling; go quiet once the list runs out.
      if (Model.isUnsupportedCommand(stderr) || Model.isUnsupportedCommand(stdout)) {
        if (root.routeCommandIndex + 1 < root.routeCommands.length) {
          root.routeCommandIndex += 1
          routesRetry.restart()
        } else {
          root.routesSupported = false
          root.routes = []
        }
        return
      }
      root.routes = []
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
      var stderr = String(profilesStderr.text || root._profilesError || "")
      if (exitCode === 0) {
        root.parseProfiles(stdout)
        return
      }
      root.parseProfiles("")
      // Walk to the table spelling before concluding the CLI has no profiles.
      if (Model.isUnsupportedCommand(stderr) || Model.isUnsupportedCommand(stdout)) {
        if (root.profileCommandIndex + 1 < root.profileCommands.length) {
          root.profileCommandIndex += 1
          profilesRetry.restart()
        } else {
          root.profilesSupported = false
        }
      }
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
      var opened = root.openAuthUrlFrom(combined, true)
      if (exitCode !== 0 && !opened) {
        root._desired = -1
        root._loginInProgress = false
        root.lastError = elideStatus(combined || "netbird up failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else if (!opened) {
        root.lastError = ""
        root.actionStatus = ""
      } else {
        // The exit of `netbird up` says nothing about whether the browser
        // login finishes; hand off to a prompt that ages out.
        root.lastError = ""
        root.actionStatus = "Finish the NetBird login in your browser"
        actionStatusTimer.restart()
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: profileProcess
    running: false
    command: []
    stdout: StdioCollector { id: profileStdout; waitForEnd: true; onStreamFinished: root._profileOutput = text }
    stderr: StdioCollector { id: profileStderr; waitForEnd: true; onStreamFinished: root._profileError = text }
    onExited: function(exitCode) {
      var stdout = String(profileStdout.text || root._profileOutput || "")
      var stderr = String(profileStderr.text || root._profileError || "")
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Profile switch failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
        root._lastProfilesRefreshMs = 0
      }
      root.switchingProfileKey = ""
      delayedRefresh.restart()
    }
  }

  Process {
    id: routeProcess
    running: false
    command: []
    stdout: StdioCollector { id: routeStdout; waitForEnd: true; onStreamFinished: root._routeOutput = text }
    stderr: StdioCollector { id: routeStderr; waitForEnd: true; onStreamFinished: root._routeError = text }
    onExited: function(exitCode) {
      var stdout = String(routeStdout.text || root._routeOutput || "")
      var stderr = String(routeStderr.text || root._routeError || "")
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Route selection failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      root.settingRouteId = ""
      delayedRefresh.restart()
    }
  }

  Process {
    id: dnsProcess
    running: false
    command: []
    stdout: StdioCollector { id: dnsStdout; waitForEnd: true; onStreamFinished: root._dnsOutput = text }
    stderr: StdioCollector { id: dnsStderr; waitForEnd: true; onStreamFinished: root._dnsError = text }
    onExited: function(exitCode) {
      var stdout = String(dnsStdout.text || root._dnsOutput || "")
      // A failed read must not invent a DNS warning; keep the last known provider.
      if (exitCode === 0) root.systemDnsProvider = stdout.trim()
    }
  }

  Process {
    id: dnsFixProcess
    running: false
    command: []
    stdout: StdioCollector { id: dnsFixStdout; waitForEnd: true; onStreamFinished: root._dnsFixOutput = text }
    stderr: StdioCollector { id: dnsFixStderr; waitForEnd: true; onStreamFinished: root._dnsFixError = text }
    onExited: function(exitCode) {
      var stdout = String(dnsFixStdout.text || root._dnsFixOutput || "")
      var stderr = String(dnsFixStderr.text || root._dnsFixError || "")
      root.fixingDns = false
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Could not change the DNS provider")
        root.actionStatus = root.lastError
      } else {
        root.systemDnsProvider = "DHCP"
        root.lastError = ""
        root.actionStatus = "DNS handed back to DHCP"
      }
      actionStatusTimer.restart()
      delayedRefresh.restart()
    }
  }

  Process {
    id: daemonProcess
    running: false
    command: []
    stdout: StdioCollector { id: daemonStdout; waitForEnd: true; onStreamFinished: root._daemonOutput = text }
    stderr: StdioCollector { id: daemonStderr; waitForEnd: true; onStreamFinished: root._daemonError = text }
    onExited: function(exitCode) {
      var stdout = String(daemonStdout.text || root._daemonOutput || "")
      var stderr = String(daemonStderr.text || root._daemonError || "")
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Could not start the NetBird daemon")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.daemonInactive = false
        root.lastError = ""
        root.actionStatus = "NetBird daemon started"
        actionStatusTimer.restart()
      }
      delayedRefresh.restart()
    }
  }
}
