import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root
  visible: false

  property var settings: ({})

  property bool installed: false
  property bool running: false
  property bool needsLogin: false
  property bool refreshing: false
  property string backendState: "Unknown"
  property string statusText: "Checking…"
  property string selfName: ""
  property string selfDnsName: ""
  property string selfIp: ""
  property string authUrl: ""
  property var peers: []
  property var accounts: []
  property string selectedAccountId: ""
  property string selectedAccountLabel: ""
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property bool busy: whichProcess.running || statusProcess.running || accountsProcess.running || actionProcess.running || loginProcess.running || switchProcess.running

  property string _statusOutput: ""
  property string _statusError: ""
  property string _accountsOutput: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _loginOutput: ""
  property string _loginError: ""
  property bool _loginInProgress: false
  property bool _loginUrlOpened: false
  property string _preLoginAuthUrl: ""
  property double _lastAccountsRefreshMs: 0
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

  function filterIPv4(ips) {
    var result = []
    if (!ips || typeof ips.length !== "number") return result
    for (var i = 0; i < ips.length; i++) {
      var ip = String(ips[i] || "")
      if (/^100\./.test(ip)) result.push(ip)
    }
    return result
  }

  function cleanDnsName(name) {
    var value = String(name || "")
    return value.charAt(value.length - 1) === "." ? value.slice(0, -1) : value
  }

  function shortDnsName(name) {
    var clean = cleanDnsName(name)
    if (clean === "") return ""
    return clean.split(".")[0] || clean
  }

  function displayHostName(hostName, dnsName) {
    var host = String(hostName || "")
    if (host !== "" && host.toLowerCase() !== "localhost") return host
    return shortDnsName(dnsName) || host || "Unknown"
  }

  function osIcon(os) {
    var value = String(os || "").toLowerCase()
    if (value === "linux") return "󰌽"
    if (value === "macos" || value === "ios") return "󰀵"
    if (value === "windows") return "󰍲"
    if (value === "android") return "󰀲"
    return "󰟀"
  }

  function accountLabel(account) {
    if (!account) return "Unknown account"
    var parts = []
    if (account.nickname) parts.push(String(account.nickname))
    if (account.tailnet && String(account.tailnet) !== String(account.nickname || "")) parts.push(String(account.tailnet))
    if (account.account) parts.push(String(account.account))
    return parts.length > 0 ? parts.join(" · ") : String(account.id || "Unknown account")
  }

  function copyToClipboard(value, label) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
    actionStatus = elideStatus("Copied " + (label || text))
    actionStatusTimer.restart()
  }

  function copyPeerIp(peer) {
    if (!peer) return
    var ips = filterIPv4(peer.TailscaleIPs || [])
    copyToClipboard(ips.length > 0 ? ips[0] : "", displayHostName(peer.HostName, peer.DNSName) + " IP")
  }

  function copyPeerName(peer) {
    if (!peer) return
    copyToClipboard(displayHostName(peer.HostName, peer.DNSName), displayHostName(peer.HostName, peer.DNSName) + " name")
  }

  function copyPeerDnsName(peer) {
    if (!peer) return
    copyToClipboard(cleanDnsName(peer.DNSName), displayHostName(peer.HostName, peer.DNSName) + " DNS name")
  }

  function refresh(forceAccounts) {
    if (installed) {
      refreshStatusAndAccounts(forceAccounts === true)
      return
    }
    if (!whichProcess.running) {
      refreshing = true
      whichProcess.command = ["which", "tailscale"]
      whichProcess.running = true
    }
  }

  function refreshStatusAndAccounts(forceAccounts) {
    if (!installed) return
    if (!statusProcess.running) {
      _statusOutput = ""
      _statusError = ""
      refreshing = true
      statusProcess.command = ["tailscale", "status", "--json"]
      statusProcess.running = true
    }
    var now = Date.now()
    var shouldRefreshAccounts = forceAccounts === true || accounts.length === 0 || now - _lastAccountsRefreshMs > 60000
    if (shouldRefreshAccounts && !accountsProcess.running) {
      _accountsOutput = ""
      _lastAccountsRefreshMs = now
      accountsProcess.command = ["tailscale", "switch", "--list", "--json"]
      accountsProcess.running = true
    }
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function resetUnavailable(message) {
    running = false
    needsLogin = false
    backendState = "Unavailable"
    statusText = message
    selfName = ""
    selfDnsName = ""
    selfIp = ""
    authUrl = ""
    peers = []
    accounts = []
    selectedAccountId = ""
    selectedAccountLabel = ""
  }

  function parseStatus(raw) {
    var text = String(raw || "").trim()
    if (text === "") {
      resetUnavailable("Disconnected")
      return
    }

    try {
      var data = JSON.parse(text)
      backendState = String(data.BackendState || "Unknown")
      running = backendState === "Running"
      needsLogin = backendState === "NeedsLogin"
      authUrl = String(data.AuthURL || "")
      if (needsLogin && _loginInProgress && !_loginUrlOpened && authUrl !== "" && authUrl !== _preLoginAuthUrl) {
        openAuthUrlFrom(authUrl, false)
      }

      var self = data.Self || {}
      selfName = displayHostName(self.HostName, self.DNSName)
      selfDnsName = cleanDnsName(self.DNSName)
      var selfIps = filterIPv4(self.TailscaleIPs || data.TailscaleIPs || [])
      selfIp = selfIps.length > 0 ? selfIps[0] : ""

      var nextPeers = []
      var rawPeers = data.Peer || {}
      for (var id in rawPeers) {
        var peer = rawPeers[id] || {}
        var ipv4s = filterIPv4(peer.TailscaleIPs || [])
        nextPeers.push({
          id: id,
          HostName: displayHostName(peer.HostName, peer.DNSName),
          DNSName: cleanDnsName(peer.DNSName),
          TailscaleIPs: ipv4s,
          Online: peer.Online === true,
          OS: String(peer.OS || ""),
          Tags: peer.Tags || [],
          ExitNodeOption: peer.ExitNodeOption === true,
          ExitNode: peer.ExitNode === true
        })
      }
      nextPeers.sort(function(a, b) {
        if (a.Online !== b.Online) return a.Online ? -1 : 1
        return String(a.HostName).localeCompare(String(b.HostName))
      })
      peers = nextPeers

      if (needsLogin) statusText = "Needs login"
      else if (running) {
        statusText = "Connected"
        _loginInProgress = false
        _loginUrlOpened = false
        _preLoginAuthUrl = ""
        loginTimeoutTimer.stop()
      } else if (backendState === "Stopped") statusText = "Disconnected"
      else statusText = backendState
      lastError = ""
    } catch (e) {
      resetUnavailable("Status error")
      lastError = "Failed to parse tailscale status"
      console.warn("tailscale", lastError, e)
    }
  }

  function parseAccounts(raw) {
    var text = String(raw || "").trim()
    if (text === "") {
      accounts = []
      selectedAccountId = ""
      selectedAccountLabel = ""
      return
    }

    try {
      var parsed = JSON.parse(text)
      var next = []
      var selected = null
      if (parsed && typeof parsed.length === "number") {
        for (var i = 0; i < parsed.length; i++) {
          var raw = parsed[i] || {}
          var account = {
            id: String(raw.id || raw.ID || ""),
            nickname: String(raw.nickname || raw.Nickname || raw.name || raw.Name || ""),
            tailnet: String(raw.tailnet || raw.Tailnet || ""),
            account: String(raw.account || raw.Account || raw.loginName || raw.LoginName || raw.user || raw.User || ""),
            selected: raw.selected === true || raw.Selected === true
          }
          next.push(account)
          if (account.selected === true) selected = account
        }
      }
      accounts = next
      selectedAccountId = selected ? String(selected.id || "") : ""
      selectedAccountLabel = selected ? accountLabel(selected) : ""
    } catch (e) {
      accounts = []
      selectedAccountId = ""
      selectedAccountLabel = ""
      console.warn("tailscale", "Failed to parse account list", e)
    }
  }

  function toggleTailscale() {
    if (!installed) return
    if (running) {
      runAction(["tailscale", "down"], "Turning Tailscale off…")
    } else {
      loginOrUp()
    }
  }

  function loginOrUp() {
    if (!installed || loginProcess.running) return
    _loginOutput = ""
    _loginError = ""
    actionStatus = needsLogin ? "Starting Tailscale login…" : "Turning Tailscale on…"
    _loginInProgress = needsLogin
    _loginUrlOpened = false
    _preLoginAuthUrl = authUrl
    var command = ["tailscale", "up"]
    if (needsLogin) command.push("--force-reauth")
    loginProcess.command = command
    loginProcess.running = true
    if (needsLogin) loginTimeoutTimer.restart()
  }

  function switchAccount(id) {
    var accountId = String(id || "")
    if (!installed || accountId === "" || accountId === selectedAccountId || switchProcess.running) return
    _switchOutput = ""
    _switchError = ""
    actionStatus = "Switching Tailscale account…"
    switchProcess.command = ["tailscale", "switch", accountId]
    switchProcess.running = true
  }

  function runAction(command, label) {
    if (actionProcess.running) return
    _actionOutput = ""
    _actionError = ""
    actionStatus = label || "Working…"
    actionProcess.command = command
    actionProcess.running = true
  }

  function openAuthUrlFrom(text, allowFallback) {
    if (_loginUrlOpened) return true
    var match = String(text || "").match(/https?:\/\/\S+/)
    var url = match && match[0] ? match[0] : (allowFallback === true ? authUrl : "")
    if (url !== "") {
      _loginUrlOpened = true
      _loginInProgress = false
      loginTimeoutTimer.stop()
      Qt.openUrlExternally(url)
      actionStatus = "Opened login link"
      actionStatusTimer.restart()
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

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 600
    repeat: false
    onTriggered: root.refresh()
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
        root.actionStatus = "Tailscale login link not available yet"
      }
    }
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refreshStatusAndAccounts()
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
    id: accountsProcess
    running: false
    command: []
    stdout: StdioCollector { id: accountsStdout; waitForEnd: true; onStreamFinished: root._accountsOutput = text }
    onExited: function(exitCode) {
      var stdout = String(accountsStdout.text || root._accountsOutput || "")
      if (exitCode === 0) root.parseAccounts(stdout)
      else root.parseAccounts("")
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
        root.lastError = elideStatus(stderr || stdout || "Tailscale command failed")
        root.actionStatus = root.lastError
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
        root._loginInProgress = false
        root.lastError = elideStatus(combined || "tailscale up failed")
        root.actionStatus = root.lastError
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
        root.lastError = elideStatus(stderr || stdout || "Account switch failed")
        root.actionStatus = root.lastError
      } else {
        root.lastError = ""
        root.actionStatus = "Switched account"
        actionStatusTimer.restart()
        root._lastAccountsRefreshMs = 0
      }
      delayedRefresh.restart()
    }
  }

  IpcHandler {
    target: "omarchy.tailscale"
    function refresh(): string { root.refresh(); return "ok" }
    function toggle(): string { root.toggleTailscale(); return "ok" }
    function up(): string { root.loginOrUp(); return "ok" }
    function down(): string { root.runAction(["tailscale", "down"], "Turning Tailscale off…"); return "ok" }
    function status(): string { return root.statusText }
  }
}
