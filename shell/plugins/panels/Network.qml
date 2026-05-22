import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "NetworkPanel"
  ipcTarget: "panels.network"

  // Centralized close so callers can't forget to drop the passphrase prompt.
  function close() {
    root.controller.hide()
    passwordSsid = ""
  }

  // Live connection details from `ip` / /sys / iw.
  property var info: ({})  // { iface, type, ip, prefix, gateway, speed, duplex, ssid, signal, freq, bitrate, rx_bytes, tx_bytes }

  // Throughput tracking. Rates are computed as deltas between successive
  // `omarchy-network-status --verbose` samples (~1.5s apart via detailsPoll).
  // We hold "prev" alongside a timestamp so the first sample after open or
  // after an interface switch doesn't manufacture a spike.
  property real prevRxBytes: 0
  property real prevTxBytes: 0
  property real prevSampleTime: 0
  property string prevIface: ""
  property real downloadRate: 0  // bytes/sec
  property real uploadRate: 0    // bytes/sec
  property int ethernetPhraseIndex: 0
  readonly property var ethernetPhrases: [
    "Wiring bits",
    "Handling packets",
    "Sorting frames",
    "Hauling bytes",
    "Routing crumbs",
    "Counting collisions",
    "Bending light",
  ]
  readonly property string ethernetPhrase: ethernetPhrases[ethernetPhraseIndex % ethernetPhrases.length]
  readonly property bool networkManagerAvailable: Networking.backend === NetworkBackendType.NetworkManager
  readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
  readonly property var wifiDevice: findDevice(DeviceType.Wifi)
  readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  readonly property var connectedWifiNetwork: findConnectedWifiNetwork()
  property var wifiNetworks: []
  property bool scanning: false
  property bool wifiStationAvailable: false
  property string dnsProvider: ""
  property string pendingDnsProvider: ""

  // Per-row in-flight state. `actionSsid` flips on for the row whose action
  // is currently running so it can render "Connecting…" / "Disconnecting…" /
  // "Forgetting…". `passwordSsid` is the row currently expanded into
  // password-entry mode; we keep it open across refresh cycles so a slow scan
  // doesn't collapse the input the user is typing into. Rows must gate
  // comparisons on the matching `*Kind`/`*Reason` being non-empty so a
  // hidden-SSID row (ssid == "") doesn't collide with the "" defaults.
  property string actionSsid: ""
  property string actionKind: ""  // "connect" | "disconnect" | "forget"
  property string failureSsid: ""
  property string failureReason: ""
  property string passwordSsid: ""
  property string passwordText: ""

  // True while any wifi action is mid-flight. Rows
  // disable themselves on this so clicks on the other rows don't silently
  // no-op against runNetworkAction's serialized guard.
  readonly property bool busy: actionKind !== ""

  // Index into `wifiNetworks` for keyboard navigation. -1 = no selection.
  property int selectedIndex: -1
  property bool cursorActive: false

  // Keyboard focus zone for the panel. j/k crosses row boundaries:
  // header actions ⇄ DNS row ⇄ Wi-Fi networks. h/l move within header
  // actions or DNS providers.
  property string focusSection: "dns"  // "header" | "dns" | "wifi"
  property int headerIndex: 0
  readonly property bool canDisconnect: !!connectedWifiNetwork
  // The disconnect button is suppressed on ethernet (see disconnectBtn.visible).
  // headerActionCount/nav must agree, so the keyboard cursor never lands on a
  // hidden button.
  readonly property bool headerHasDisconnect: canDisconnect && info.type !== "ethernet"
  readonly property int headerActionCount: headerHasDisconnect ? 1 : 0
  readonly property var dnsProviders: ["DHCP", "Cloudflare", "Google", "Custom"]
  property int dnsIndex: 0

  onHeaderActionCountChanged: clampHeaderIndex()

  function clampHeaderIndex() {
    var max = Math.max(0, headerActionCount - 1)
    if (headerIndex > max) headerIndex = max
    if (headerIndex < 0) headerIndex = 0
  }

  function selectHeaderByDelta(delta) {
    headerIndex = Math.max(0, Math.min(headerActionCount - 1, headerIndex + delta))
  }

  function activateHeader() {
    if (headerHasDisconnect && headerIndex === 0 && !busy) disconnect(connectedWifiNetwork)
  }

  function selectDnsByDelta(delta) {
    dnsIndex = Math.max(0, Math.min(dnsProviders.length - 1, dnsIndex + delta))
  }

  function activateDns() {
    if (dnsIndex < 0 || dnsIndex >= dnsProviders.length) return
    setDns(dnsProviders[dnsIndex])
  }

  // Single cursor model: exactly one highlighted spot across the whole
  // panel, located via `focusSection` + (`headerIndex` | `dnsIndex` |
  // `selectedIndex`). Mouse hover and keyboard nav both mutate this state
  // at the root; items never read containsMouse for visuals. See
  // CursorSurface for the shared chrome shared by rows and pills.
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  // The panel below is its own layer-shell with Exclusive keyboard focus,
  // so Hyprland grants focus when the surface is mapped (opened flips
  // to true). That's what makes the SUPER+CTRL+W keybind actually work
  // — OnDemand only grants focus on click/hover.
  onOpenedChanged: {
    if (opened) {
      refresh(true)
      selectedIndex = wifiNetworks.length > 0 ? 0 : -1
      focusSection = wifiNetworks.length > 0 ? "wifi" : "dns"
      var idx = dnsProviders.indexOf(dnsProvider)
      dnsIndex = idx >= 0 ? idx : 0
      cursorActive = false
    } else {
      // Reset throughput tracking so the next open doesn't compute a fake
      // rate from a sample taken minutes ago.
      prevSampleTime = 0
      downloadRate = 0
      uploadRate = 0
      if (wifiDevice) wifiDevice.scannerEnabled = false
    }
  }

  // When the passphrase prompt closes (Esc / Cancel / success) restore
  // focus to the keyCatcher so j/k/Enter resume working without a click.
  // The KeyboardPanel's focusTarget covers initial popup-open; this handles
  // the inline-editor case where focus was handed off to a child.
  onPasswordSsidChanged: {
    if (passwordSsid === "" && opened) {
      passwordText = ""
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }
  }

  // Keep selectedIndex valid as scans refresh the network list.
  // If the list empties (station gone, e.g. wifi off), bounce the cursor
  // back to the DNS row so the panel doesn't end up with no cursor at all.
  onWifiNetworksChanged: {
    if (wifiNetworks.length === 0) {
      selectedIndex = -1
      if (focusSection === "wifi") focusSection = "dns"
    } else if (passwordSsid !== "") {
      var passwordIndex = wifiIndexForSsid(passwordSsid)
      if (passwordIndex >= 0) {
        selectedIndex = passwordIndex
        focusSection = "wifi"
      }
    } else if (selectedIndex >= wifiNetworks.length) {
      selectedIndex = wifiNetworks.length - 1
    } else if (selectedIndex < 0 && opened) {
      selectedIndex = 0
    }
  }

  onWifiDeviceChanged: {
    if (wifiDevice) wifiDevice.scannerEnabled = opened
    syncWifiNetworks()
  }

  onWifiNetworkObjectsChanged: syncWifiNetworks()

  function selectByDelta(delta) {
    if (wifiNetworks.length === 0) { selectedIndex = -1; return }
    if (selectedIndex < 0) selectedIndex = delta > 0 ? 0 : wifiNetworks.length - 1
    else selectedIndex = Math.max(0, Math.min(wifiNetworks.length - 1, selectedIndex + delta))
  }

  // Enter/Space on the highlighted row. Mirrors row-click semantics:
  // connected → disconnect, protected-unknown → password prompt,
  // open/known → connect.
  function activateSelected() {
    if (busy || selectedIndex < 0 || selectedIndex >= wifiNetworks.length) return
    var net = wifiNetworks[selectedIndex]
    if (!net) return
    if (net.connected) { disconnect(net.network); return }
    if (isProtected(net.security) && !net.known) { openPasswordPrompt(net.ssid); return }
    connectKnown(net.ssid)
  }

  // 'x' on the highlighted row. Meaningful for saved/known networks
  // (and the currently-connected row, if one is ever present); forget is
  // hidden and a no-op otherwise.
  function forgetSelected() {
    if (busy || selectedIndex < 0 || selectedIndex >= wifiNetworks.length) return
    var net = wifiNetworks[selectedIndex]
    if (net && (net.connected || net.known)) forget(net)
  }

  // Bar pill state. Polled locally so this panel is self-contained;
  // populated by networkProc + networkTimer below.
  property string kind: "disconnected"
  property string label: ""
  property int signalStrength: -1
  property string frequency: ""

  function updateNetwork(raw) {
    var parts = String(raw || "disconnected\t\t\t").replace(/\r?\n+$/, "").split("\t")
    kind = parts[0] || "disconnected"
    label = parts[1] || ""
    signalStrength = parts[2] ? parseInt(parts[2], 10) : -1
    frequency = parts[3] || ""
  }

  function copyToClipboard(value) {
    if (!value || !root.bar) return
    Quickshell.execDetached(["bash", "-lc", "printf %s " + Util.shellQuote(value) + " | wl-copy"])
  }

  readonly property string icon: {
    if (kind === "wifi") {
      var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
      var index = Math.max(0, Math.min(4, Math.ceil(signalStrength / 20) - 1))
      return icons[index]
    }
    if (kind === "ethernet") return "󰈀"
    return "󰤮"
  }

  function refresh(scanWifi) {
    if (scanWifi === undefined) scanWifi = false
    if (!detailsProc.running) detailsProc.running = true
    if (!dnsProc.running) {
      dnsProc.command = ["bash", "-lc", root.dnsCommand("")]
      dnsProc.running = true
    }
    if (wifiDevice) {
      if (scanWifi) {
        scanning = true
        wifiDevice.scannerEnabled = false
        scanRestart.start()
      } else {
        wifiDevice.scannerEnabled = true
      }
    }
    syncWifiNetworks()
  }

  function formatSpeed(mbps) {
    var v = parseInt(mbps, 10)
    if (!v || v < 0) return ""
    if (v >= 1000) return (v / 1000).toFixed(v % 1000 === 0 ? 0 : 1) + " Gbps"
    return v + " Mbps"
  }

  function formatFreq(mhz) {
    var v = parseFloat(mhz)
    if (!v) return ""
    return (v / 1000).toFixed(1) + " GHz"
  }

  function updateDetails(raw) {
    var next = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (!line) continue
      var idx = line.indexOf("\t")
      if (idx === -1) continue
      next[line.substring(0, idx)] = line.substring(idx + 1).trim()
    }
    info = next
    updateThroughput(next)
  }

  function updateThroughput(next) {
    var iface = next.iface || ""
    var rx = parseFloat(next.rx_bytes || "0")
    var tx = parseFloat(next.tx_bytes || "0")
    var now = Date.now() / 1000

    // Interface changed (or first sample) — reseed without emitting a rate;
    // raw counters from two different NICs are meaningless to subtract.
    if (iface !== prevIface || prevSampleTime === 0) {
      prevIface = iface
      prevRxBytes = rx
      prevTxBytes = tx
      prevSampleTime = now
      downloadRate = 0
      uploadRate = 0
      return
    }

    var dt = now - prevSampleTime
    if (dt > 0) {
      // Math.max guards against counter wrap or reset to 0 (interface flap).
      downloadRate = Math.max(0, (rx - prevRxBytes) / dt)
      uploadRate = Math.max(0, (tx - prevTxBytes) / dt)
    }
    prevRxBytes = rx
    prevTxBytes = tx
    prevSampleTime = now
  }

  function formatBytes(bytes) {
    var n = Number(bytes)
    if (!isFinite(n) || n < 0) n = 0
    if (n < 1024) return Math.round(n) + " B"
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB"
    if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + " MB"
    return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB"
  }

  function formatRate(bytesPerSec) {
    return formatBytes(bytesPerSec) + "/s"
  }

  function findDevice(type) {
    var devices = networkDevices || []
    for (var i = 0; i < devices.length; i++) {
      if (devices[i] && devices[i].type === type) return devices[i]
    }
    return null
  }

  function findConnectedWifiNetwork() {
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].connected) return networks[i]
    }
    return null
  }

  function syncWifiNetworks() {
    var nets = []
    var networks = wifiNetworkObjects || []

    for (var i = 0; i < networks.length; i++) {
      var network = networks[i]
      if (!network) continue
      checkActionCompletion(network)
      var isConnected = network.connected
      var ssid = network.name || ""
      if (isConnected && ssid !== root.actionSsid) continue // Skip the connected network so it doesn't appear in the list, unless we are currently trying to connect to it
      nets.push({
        network: network,
        connected: isConnected,
        known: network.known,
        ssid: ssid,
        signal: Math.round((network.signalStrength || 0) * 100),
        security: network.security
      })
    }
    nets.sort(function(a, b) {
      return b.signal - a.signal
    })
    wifiNetworks = nets
    wifiStationAvailable = !!wifiDevice
    scanning = false
  }

  function wifiIconFor(strength) {
    var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    var index = Math.max(0, Math.min(4, Math.ceil(strength / 20) - 1))
    return icons[index]
  }

  function updateDns(raw) {
    var value = String(raw || "").trim()
    dnsProvider = value || "DHCP"
  }

  function dnsCommand(provider) {
    var command = root.bar ? Util.shellQuote(root.bar.omarchyPath + "/bin/omarchy-dns") : "omarchy-dns"
    if (provider) command += " " + Util.shellQuote(provider)
    return command
  }

  function setDns(provider) {
    if (!root.bar || !provider || actionProc.running) return

    if (provider === "Custom") {
      var launcher = Util.shellQuote(root.bar.omarchyPath + "/bin/omarchy-launch-floating-terminal-with-presentation")
      root.bar.run(launcher + " " + Util.shellQuote(root.dnsCommand(provider)))
      root.close()
      return
    }

    root.pendingDnsProvider = provider
    actionProc.command = ["bash", "-lc", root.dnsCommand(provider)]
    actionProc.running = true
    root.close()
  }

  function isProtected(security) {
    return security !== WifiSecurityType.Open
  }

  function openPasswordPrompt(ssid) {
    if (passwordSsid !== ssid) passwordText = ""
    passwordSsid = ssid
  }

  function networkForSsid(ssid) {
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].name === ssid) return networks[i]
    }
    return null
  }

  function wifiIndexForSsid(ssid) {
    for (var i = 0; i < wifiNetworks.length; i++) {
      if (wifiNetworks[i] && wifiNetworks[i].ssid === ssid) return i
    }
    return -1
  }

  function runNetworkAction(kind, network, callback) {
    if (actionKind !== "" || !network) return
    var ssid = network.name || ""
    actionSsid = ssid
    actionKind = kind
    failureSsid = ""
    failureReason = ""
    callback(network)
    // Safety net: if onExited never fires (process death, signal handler
    // throws, etc.), clear the busy state so the row doesn't get stuck on
    // "Connecting…" / "Disconnecting…" forever.
    actionTimeout.restart()
  }

  function clearNetworkAction() {
    actionTimeout.stop()
    if (actionKind === "connect") passwordSsid = ""
    failureSsid = ""
    failureReason = ""
    actionSsid = ""
    actionKind = ""
    refresh()
  }

  function failNetworkAction(network, reason) {
    if (!network || actionKind === "" || actionSsid !== (network.name || "")) return
    actionTimeout.stop()
    failureSsid = actionSsid
    failureReason = networkFailureReason(reason)
    actionSsid = ""
    actionKind = ""
    refresh()
  }

  function networkFailureReason(reason) {
    if (reason === ConnectionFailReason.NoSecrets) return "Passphrase required"
    if (reason === ConnectionFailReason.WifiAuthTimeout) return "Wrong password"
    if (reason === ConnectionFailReason.WifiNetworkLost) return "Network lost"
    if (reason === ConnectionFailReason.WifiClientDisconnected) return "Disconnected"
    if (reason === ConnectionFailReason.WifiClientFailed) return "Connection failed"
    return "Failed to connect"
  }

  function checkActionCompletion(network) {
    if (!network || actionKind === "" || actionSsid !== (network.name || "")) return
    if (actionKind === "connect" && network.connected) clearNetworkAction()
    else if (actionKind === "disconnect" && !network.connected && !network.stateChanging) clearNetworkAction()
    else if (actionKind === "forget" && !network.known && !network.stateChanging) clearNetworkAction()
  }

  function connectKnown(ssid) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) { network.connect() })
  }

  function connectWithPassphrase(ssid, passphrase) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) { network.connectWithPsk(passphrase) })
  }

  function disconnect(network) {
    runNetworkAction("disconnect", network || connectedWifiNetwork, function(net) { net.disconnect() })
  }

  function forget(net) {
    runNetworkAction("forget", net ? net.network : null, function(network) { network.forget() })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  // Pulls everything we want about the active route's interface in one shot.
  Process {
    id: detailsProc
    command: [root.bar ? root.bar.omarchyPath + "/bin/omarchy-network-status" : "omarchy-network-status", "--verbose"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateDetails(text)
    }
  }

  Timer {
    id: scanRestart
    interval: 100
    repeat: false
    onTriggered: {
      if (root.wifiDevice) root.wifiDevice.scannerEnabled = true
      scanDone.start()
    }
  }

  Timer {
    id: scanDone
    interval: 1500
    repeat: false
    onTriggered: root.syncWifiNetworks()
  }

  Process {
    id: dnsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateDns(text)
    }
  }

  // Action runner for DNS provider changes. Wi-Fi actions use the
  // Quickshell.Networking NetworkManager backend directly.
  Process {
    id: actionProc
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (root.pendingDnsProvider !== "") {
        if (exitCode === 0) root.dnsProvider = root.pendingDnsProvider
        root.pendingDnsProvider = ""
      }
    }
  }

  // Poll details while the panel is open so the IP/route header catches up
  // as soon as NetworkManager finishes activating a connection.
  Timer {
    id: detailsPoll
    interval: 1500
    repeat: true
    running: root.opened
    onTriggered: if (!detailsProc.running) detailsProc.running = true
  }

  Timer {
    id: ethernetPhraseTimer
    interval: 2800
    running: root.opened && root.info.type === "ethernet"
    repeat: true
    onTriggered: ethernetPhraseSwap.restart()
  }

  SequentialAnimation {
    id: ethernetPhraseSwap
    PropertyAnimation {
      target: heroMeta; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.ethernetPhraseIndex = (root.ethernetPhraseIndex + 1) % root.ethernetPhrases.length
    }
    PropertyAnimation {
      target: heroMeta; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  Connections {
    target: root
    function onInfoChanged() {
      if (root.info.type !== "ethernet") {
        ethernetPhraseSwap.stop()
        heroMeta.opacity = 1.0
      }
    }
  }

  Timer {
    id: actionTimeout
    interval: 15000
    repeat: false
    onTriggered: {
      if (!root.actionKind) return
      var reason
      if (root.actionKind === "connect") reason = "Timed out connecting"
      else if (root.actionKind === "disconnect") reason = "Timed out disconnecting"
      else reason = "Timed out forgetting"
      root.failureSsid = root.actionSsid
      root.failureReason = reason
      root.actionSsid = ""
      root.actionKind = ""
      root.refresh()
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    horizontalMargin: 8.5
    rightExtraMargin: 2

    onPressed: function(b) {
      if (root.opened) root.close()
      else { root.open(); root.refresh() }
    }
  }

  // Keyboard-driven popup anchored to the bar widget icon. The shared
  // KeyboardPanel handles the layer-shell PanelWindow scaffolding
  // (Exclusive focus on map, screen binding, anchored-to-icon positioning,
  // outside-click via an overlay MouseArea + Region mask that lets the bar
  // remain clickable, fade animation, popout coordination). What stays
  // here is the wifi-specific UI inside.
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    // Catches all unhandled keys for keyboard navigation. AfterItem priority
    // lets the passphrase TextField (a child via focus chain) get its keys
    // first; only events the focused subtree ignores bubble back here.
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Freeze the cursor model while the inline password prompt is open;
      // the TextField inside owns input until Esc/Enter/Cancel.
      blocked: root.passwordSsid !== ""

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          if (dy >= 0) return
        }
        if (dy !== 0) {
          if (root.focusSection === "header") {
            if (dy > 0) root.focusSection = "dns"
          } else if (root.focusSection === "dns") {
            // k from DNS moves up into the disconnect button when there is
            // one; otherwise stays put. j drops into the wifi list if there's
            // anywhere to land.
            if (dy < 0) {
              if (root.headerHasDisconnect) {
                root.focusSection = "header"
                root.headerIndex = 0
              }
            } else if (root.wifiNetworks.length > 0) {
              root.focusSection = "wifi"
              if (root.selectedIndex < 0) root.selectedIndex = 0
            }
          } else {  // wifi
            // k from the top row escapes back up into the DNS row rather
            // than wrapping around to the bottom of the list.
            if (dy < 0 && root.selectedIndex <= 0) root.focusSection = "dns"
            else root.selectByDelta(dy)
          }
        }
        if (dx !== 0) {
          if (root.focusSection === "header") root.selectHeaderByDelta(dx)
          else if (root.focusSection === "dns") root.selectDnsByDelta(dx)
        }
      }
      onActivateRequested: {
        if (root.cursorActive) {
          if (root.focusSection === "header") root.activateHeader()
          else if (root.focusSection === "dns") root.activateDns()
          else root.activateSelected()
        }
      }
      onCloseRequested: root.close()
      onDeleteRequested: {
        if (root.cursorActive && root.focusSection === "wifi") root.forgetSelected()
      }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
      }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(12)

      // ---------- Hero: network icon · SSID + state · actions ----------
      Item {
        width: parent.width
        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, headerActions.implicitHeight)

        Text {
          id: heroIcon
          text: root.icon
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.display
          opacity: root.networkManagerAvailable ? 1.0 : 0.5
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter

          MouseArea {
            id: heroIconMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: root.networkManagerAvailable
            onClicked: {
              Networking.wifiEnabled = !Networking.wifiEnabled
              Qt.callLater(function() { root.refresh(true) })
            }
          }

          PanelToolTip {
            visible: heroIconMouse.containsMouse
            text: root.info.type === "ethernet" ? "Toggle network" : "Toggle Wi-Fi"
            fontFamily: root.bar.fontFamily
          }
        }

        Column {
          id: heroLabels
          anchors.left: heroIcon.right
          anchors.leftMargin: Style.space(14)
          anchors.right: headerActions.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            id: heroSsid
            width: parent.width
            text: {
              if (root.info.type === "wifi") return root.info.ssid || "Wi-Fi"
              if (root.info.type === "ethernet") return "Ethernet"
              return root.info.iface || (root.kind === "disconnected" ? "Disconnected" : "No connection")
            }
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            id: heroMeta
            width: parent.width
            text: {
              if (root.info.type === "wifi") {
                if (root.canDisconnect) return "CONNECTED"
                if (root.kind === "disconnected") return "NOT CONNECTED"
                return ""
              }
              if (root.info.type === "ethernet") return root.ethernetPhrase.toUpperCase()
              if (root.kind === "disconnected") return "NOT CONNECTED"
              return ""
            }
            visible: text !== ""
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            elide: Text.ElideRight
          }
        }

        Row {
          id: headerActions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          PanelActionButton {
            id: disconnectBtn
            // Hide on ethernet — the panel can't disconnect a wired link, and
            // a wifi-off glyph next to the ethernet hero icon reads as a state
            // contradiction.
            visible: root.canDisconnect && root.info.type !== "ethernet"
            enabled: !root.busy
            hasCursor: root.cursorActive && root.focusSection === "header" && root.headerIndex === 0
            iconText: "󰖪"
            fontSize: Style.font.heading
            size: Style.space(30)
            tooltipText: "Disconnect"
            foreground: root.bar.foreground
            hoverColor: root.bar.urgent
            fontFamily: root.bar.fontFamily
            anchors.verticalCenter: parent.verticalCenter
            onHovered: function(h) {
              if (!h) return
              root.cursorActive = true
              root.focusSection = "header"
              root.headerIndex = 0
            }
            onClicked: root.disconnect(root.connectedWifiNetwork)
          }

        }
      }

      // Connection details: IP, gateway, link speed, etc. Two equal-width
      // columns spanning the panel — matches the Power panel's stats grid.
      Row {
        visible: !!root.info.iface
        width: parent.width
        spacing: Style.space(20)

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.spacing.labelGap
          InfoPair {
            visible: !!root.info.ip
            label: "IP"
            value: root.info.ip || ""
            copyable: true
            tooltipText: "Copy IP"
          }
          InfoPair {
            visible: !!root.info.gateway
            label: "Gateway"
            value: root.info.gateway || ""
            copyable: true
            tooltipText: "Copy gateway"
          }
        }

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.spacing.labelGap

          // Ethernet details
          InfoPair {
            visible: root.info.type === "ethernet" && !!root.info.speed
            label: "Link"
            value: root.formatSpeed(root.info.speed || "")
          }

          // Wi-Fi details
          InfoPair {
            visible: root.info.type === "wifi" && !!root.info.freq
            label: "Band"
            value: root.formatFreq(root.info.freq || "")
          }
          InfoPair {
            visible: root.info.type === "wifi" && !!root.info.bitrate
            label: "Link"
            value: root.info.bitrate || ""
          }
        }
      }

      PanelSeparator {
        visible: !!root.info.iface && root.info.rx_bytes !== undefined
        foreground: root.bar.foreground
      }

      // Throughput: instantaneous rate (from sample-to-sample delta) plus
      // cumulative bytes since the interface came up.
      Row {
        visible: !!root.info.iface && root.info.rx_bytes !== undefined
        width: parent.width
        spacing: Style.space(20)

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.spacing.labelGap
          InfoPair { label: "Receiving"; value: root.formatRate(root.downloadRate) }
          InfoPair { label: "Downloaded"; value: root.formatBytes(parseFloat(root.info.rx_bytes || "0")) }
        }

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.spacing.labelGap
          InfoPair { label: "Sending"; value: root.formatRate(root.uploadRate) }
          InfoPair { label: "Uploaded"; value: root.formatBytes(parseFloat(root.info.tx_bytes || "0")) }
        }
      }

      // DNS provider selection.
      PanelSeparator {
        foreground: root.bar.foreground
      }

      Column {
        width: parent.width
        spacing: Style.space(10)

        PanelSectionHeader {
          text: "DNS PROVIDER"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Row {
          id: dnsRow
          width: parent.width
          spacing: Style.space(6)

          readonly property int count: 4
          readonly property real cellWidth: (width - spacing * (count - 1)) / count

          DnsProviderPill {
            provider: "DHCP"
            index: 0
            tooltipText: "Use DNS from DHCP"
            width: dnsRow.cellWidth
            onClicked: root.setDns(provider)
          }

          DnsProviderPill {
            provider: "Cloudflare"
            index: 1
            tooltipText: "Set DNS to Cloudflare"
            width: dnsRow.cellWidth
            onClicked: root.setDns(provider)
          }

          DnsProviderPill {
            provider: "Google"
            index: 2
            tooltipText: "Set DNS to Google"
            width: dnsRow.cellWidth
            onClicked: root.setDns(provider)
          }

          DnsProviderPill {
            provider: "Custom"
            index: 3
            tooltipText: "Set custom DNS servers"
            width: dnsRow.cellWidth
            onClicked: root.setDns(provider)
          }
        }
      }

      // Wi-Fi networks (only if a Wi-Fi station is available).
      PanelSeparator {
        visible: root.wifiStationAvailable
        foreground: root.bar.foreground
      }

      PanelSectionHeader {
        visible: root.wifiStationAvailable
        text: root.scanning ? "SCANNING WI-FI…" : "WI-FI NETWORKS"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }

      // Scrollable network list — cap the height so a busy neighbourhood
      // doesn't push the popup off-screen. ListView (vs Repeater+Column)
      // gives us positionViewAtIndex for free, which is what keeps the
      // keyboard-selected row scrolled into view as j/k walk past the
      // visible window.
      ListView {
        id: networkList
        visible: root.wifiStationAvailable
        width: parent.width
        height: Math.min(contentHeight, Style.space(240))
        spacing: Style.space(4)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        model: root.wifiStationAvailable ? root.wifiNetworks : []
        currentIndex: root.selectedIndex
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

        // Wrapper takes the required props from ListView's delegate context
        // (which doesn't bind into nested `component` declarations like
        // NetworkRow) and passes them down explicitly.
        delegate: Item {
          required property var modelData
          required property int index
          width: ListView.view.width
          height: row.implicitHeight
          NetworkRow {
            id: row
            width: parent.width
            net: parent.modelData
            index: parent.index
          }
        }
      }
    }
    }
  }

  // One DNS provider pill. The cursor + current visuals come entirely from
  // CursorSurface; this component just binds them to the panel's cursor
  // state and renders the label/tooltip/click target.
  component DnsProviderPill: Button {
    id: pill
    required property string provider
    required property int index

    text: provider
    fontSize: Style.font.bodySmall
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
    bordered: true

    // Map the panel's domain semantics onto Button's structural props:
    // `current DNS` is the pill's `active` fill; the keyboard cursor lights
    // up `hasCursor`.
    active: root.dnsProvider === provider
    hasCursor: root.cursorActive && root.focusSection === "dns" && root.dnsIndex === index

    onHovered: function(isHovered) {
      if (!isHovered) return
      root.cursorActive = true
      root.focusSection = "dns"
      root.dnsIndex = pill.index
    }
  }

  // A single Wi-Fi network entry. Collapses to a one-line pill normally;
  // expands inline to a passphrase prompt when the user picks a protected
  // network we don't have credentials for. Clicking a connected row
  // disconnects; the X button on any saved/connected row forgets it.
  component NetworkRow: CursorSurface {
    id: row
    required property var net
    required property int index

    readonly property bool isConnected: net && net.connected
    readonly property bool isKnown: !!(net && net.known)
    readonly property bool isProtected: net ? root.isProtected(net.security) : false
    readonly property bool canForget: isConnected || isKnown
    readonly property bool isSelected: root.focusSection === "wifi" && root.selectedIndex === index

    hasCursor: root.cursorActive && isSelected
    current: isConnected
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    // Gate on the matching *Kind/*Reason being non-empty so a hidden-SSID
    // row (ssid == "") doesn't match the "" defaults of actionSsid etc.
    readonly property bool isBusy: root.actionKind !== "" && root.actionSsid === (net ? net.ssid : "")
    readonly property bool isFailed: root.failureReason !== "" && root.failureSsid === (net ? net.ssid : "")
    readonly property bool isPasswordOpen: root.passwordSsid !== "" && root.passwordSsid === (net ? net.ssid : "")

    Connections {
      target: row.net ? row.net.network : null
      function onConnectionFailed(reason) {
        root.failNetworkAction(row.net.network, reason)
        if (reason === ConnectionFailReason.NoSecrets) root.openPasswordPrompt(row.net.ssid)
      }
      function onConnectedChanged() {
        if (row.net) root.checkActionCompletion(row.net.network)
      }
      function onKnownChanged() {
        if (row.net) root.checkActionCompletion(row.net.network)
      }
      function onStateChangingChanged() {
        if (row.net) root.checkActionCompletion(row.net.network)
      }
    }

    readonly property string statusText: {
      if (!net) return ""
      if (isPasswordOpen) return ""
      if (isBusy && root.actionKind === "connect") return "Connecting…"
      if (isBusy && root.actionKind === "disconnect") return "Disconnecting…"
      if (isBusy && root.actionKind === "forget") return "Forgetting…"
      if (isFailed) return root.failureReason || "Failed"
      if (isConnected) return "Connected"
      return ""
    }

    readonly property color statusColor: {
      if (isFailed) return root.bar.urgent
      if (isBusy) return root.bar.foreground
      if (isConnected) return root.bar.foreground
      return Qt.darker(root.bar.foreground, 1.5)
    }

    implicitHeight: rowBody.implicitHeight + (isPasswordOpen ? passwordPanel.implicitHeight + Style.spacing.md : 0)

    MouseArea {
      id: rowMouse
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: rowBody.implicitHeight
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      enabled: !root.busy

      // Move the cursor here when the mouse enters; mouse leaving doesn't
      // clear it (so the cursor stays where the mouse last was and
      // subsequent j/k pick up from this row).
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.focusSection = "wifi"; root.selectedIndex = row.index }

      onClicked: {
        if (!row.net) return
        // Resync cursor in case keyboard nav moved it away while the mouse
        // stayed parked on this row — the click target is unambiguously here.
        root.cursorActive = true
        root.focusSection = "wifi"
        root.selectedIndex = row.index
        if (row.isConnected) {
          root.disconnect(row.net.network)
          return
        }
        if (row.isProtected && !row.isKnown) {
          root.openPasswordPrompt(row.net.ssid)
          return
        }
        root.connectKnown(row.net.ssid)
      }
    }

    Item {
      id: rowBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(networkIcon.implicitHeight, networkInfo.implicitHeight, forgetBtn.implicitHeight) + Style.spacing.rowPaddingX

      Text {
        id: networkIcon
        text: row.net ? root.wifiIconFor(row.net.signal) : ""
        color: row.statusColor
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      PanelActionButton {
        id: forgetBtn
        anchors.right: lockIndicator.visible ? lockIndicator.left : parent.right
        anchors.rightMargin: lockIndicator.visible ? Style.space(4) : 0
        anchors.verticalCenter: parent.verticalCenter
        visible: row.canForget
        enabled: !root.busy
        iconText: "󰅙"
        tooltipText: "Forget network"
        foreground: root.bar.foreground
        hoverColor: root.bar.urgent
        fontFamily: root.bar.fontFamily
        onClicked: if (row.net) root.forget(row.net)
      }

      // Shows a lock glyph for protected disconnected networks at the far
      // right, with the forget X to its left when the network is saved.
      Text {
        id: lockIndicator
        visible: row.isProtected && !row.isConnected
        width: Style.space(22)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: "󰌾"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.subtitle
      }

      Column {
        id: networkInfo
        spacing: Style.space(1)
        anchors.left: networkIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: forgetBtn.visible ? forgetBtn.left
                      : lockIndicator.visible ? lockIndicator.left
                      : parent.right
        anchors.rightMargin: (forgetBtn.visible || lockIndicator.visible) ? Style.space(8) : 0
        anchors.verticalCenter: parent.verticalCenter

        Text {
          text: row.net ? (row.net.ssid || "Hidden") : ""
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          // Signal strength is conveyed by the wifi-bars icon and the
          // right-edge glyph/buttons carry protection or forget affordances,
          // so the second line only carries action status (Connecting…,
          // Connected, Failed, etc.). Collapses to zero height when empty
          // so rows without status keep a tight one-line look.
          text: row.statusText
          visible: row.statusText !== ""
          height: visible ? implicitHeight : 0
          color: row.statusColor
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }
    }

    Timer {
      id: failureTimer
      interval: 2000
      running: row.isFailed && row.isPasswordOpen
      onTriggered: {
        root.failureSsid = ""
        root.failureReason = ""
        pwField.forceActiveFocus()
      }
    }

    // Inline passphrase prompt — only shown when we hit a protected network
    // we don't have saved credentials for. Submitting (Enter or the check
    // button) fires connect; Esc cancels back to the row.
    Item {
      id: passwordPanel
      visible: row.isPasswordOpen
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: rowMouse.bottom
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      anchors.topMargin: Style.space(4)
      implicitHeight: pwField.implicitHeight + Style.spacing.rowGap
      height: implicitHeight

      TextField {
        id: pwField
        visible: !row.isBusy && !row.isFailed
        anchors.left: parent.left
        anchors.right: connectPwBtn.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Style.space(6)
        password: true
        placeholderText: "Passphrase"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        foreground: root.bar.foreground
        horizontalPadding: Style.spacing.controlGap
        verticalPadding: Style.spacing.controlPaddingY
        enabled: !row.isBusy
        text: row.isPasswordOpen ? root.passwordText : ""

        onAccepted: {
          if (!root.busy && row.net && text.length > 0) root.connectWithPassphrase(row.net.ssid, text)
        }
        onTextChanged: if (row.isPasswordOpen && text !== root.passwordText) root.passwordText = text
        Keys.onEscapePressed: { root.passwordSsid = ""; root.passwordText = "" }

        onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
        Component.onCompleted: if (visible) Qt.callLater(forceActiveFocus)
      }

      Rectangle {
        id: statusMsgWrapper
        visible: row.isBusy || row.isFailed
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Style.spacing.controlHeight
        color: Style.normalFillFor(root.bar.foreground)
        border.color: Style.normalBorderFor(root.bar.foreground)
        border.width: Style.normalBorderWidth
        radius: Style.cornerRadius

        Text {
          anchors.fill: parent
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: row.isFailed ? "Wrong password" : "Connecting..."
          color: row.isFailed ? root.bar.urgent : root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      // 22×22 right-anchored to line up with forgetBtn and lockIndicator
      // above. Esc closes the prompt (handled by pwField.Keys.onEscapePressed)
      // so there's no separate cancel button.
      PanelActionButton {
        id: connectPwBtn
        visible: !row.isBusy && !row.isFailed
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        enabled: row.net && pwField.text.length > 0
        iconText: "󰄬"
        tooltipText: "Connect"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onClicked: if (row.net) root.connectWithPassphrase(row.net.ssid, root.passwordText)
      }
    }
  }

  // Poll the wifi/ethernet pill state every 3s. Local to this panel so
  // Bar.qml does not need to mirror network state.
  Process {
    id: networkProc
    command: [root.bar ? root.bar.omarchyPath + "/bin/omarchy-network-status" : "omarchy-network-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateNetwork(text)
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!networkProc.running) networkProc.running = true
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""
    property bool copyable: false
    property string tooltipText: "Copy to clipboard"

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - valueText.implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue {
      id: valueText
      text: value

      MouseArea {
        id: valueMouse
        anchors.fill: parent
        enabled: copyable && valueText.text !== ""
        hoverEnabled: enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.copyToClipboard(valueText.text)
      }

      PanelToolTip {
        visible: valueMouse.enabled && valueMouse.containsMouse
        text: tooltipText
        fontFamily: root.bar.fontFamily
      }
    }
  }

  component InfoLabel: Text {
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
