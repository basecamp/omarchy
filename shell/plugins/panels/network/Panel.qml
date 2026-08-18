import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.network"
  ipcTarget: "omarchy.network"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the toggleNetwork method below.
  manageIpc: false

  // Centralized close so callers can't forget to drop the passphrase prompt.
  function close() {
    root.controller.hide()
    cancelPasswordPrompt()
  }

  function cancelPasswordPrompt() {
    passwordSsid = ""
    passwordText = ""
    identityText = ""
  }

  // Live connection details from `ip` / /sys / iw.
  property var info: ({})  // { iface, type, ip, prefix, gateway, speed, duplex, ssid, signal, freq, bitrate, rx_bytes, tx_bytes, router_ping_ms, internet_ping_ms }

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
  property string pingIface: ""
  property var routerPingSamples: []
  property var internetPingSamples: []
  property real routerPingLatency: -1
  property real internetPingLatency: -1
  property int internetPingPacketLoss: 0
  readonly property int pingHistoryWindow: 24
  readonly property int pingAverageWindow: 5
  readonly property bool hasInternetPing: internetPingSamples.length > 0
  // Every stat row stays mounted whether or not there is data behind it, so a
  // sample arriving late never reflows the grid. This says whether the numbers
  // are real yet or the row should read "--".
  readonly property bool hasTransferStats: info.rx_bytes !== undefined
  property int connectionPhraseIndex: 0
  readonly property var connectionPhrases: [
    "Wiring bits",
    "Handling packets",
    "Sorting frames",
    "Hauling bytes",
    "Routing crumbs",
    "Counting collisions",
    "Bending light",
  ]
  readonly property string connectionPhrase: connectionPhrases[connectionPhraseIndex % connectionPhrases.length]
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
  // Wi-Fi band state from `omarchy-network-band`. `bandCurrent` is the band
  // the radio is actually on; `bandSelected` is the pinned choice ("auto" when
  // nothing is pinned), and the two differ whenever Auto is in effect.
  property string bandCurrent: ""
  property string bandSelected: "auto"
  property var bandAvailable: []
  property string pendingBand: ""

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
  property string identityText: ""

  // ConnectionFailReason values as a plain object, so Model.js helpers stay
  // pure JS and Node-testable.
  readonly property var connectionFailReasons: ({
    NoSecrets: ConnectionFailReason.NoSecrets,
    WifiAuthTimeout: ConnectionFailReason.WifiAuthTimeout,
    WifiNetworkLost: ConnectionFailReason.WifiNetworkLost,
    WifiClientDisconnected: ConnectionFailReason.WifiClientDisconnected,
    WifiClientFailed: ConnectionFailReason.WifiClientFailed
  })

  // True while any wifi action is mid-flight. Rows
  // disable themselves on this so clicks on the other rows don't silently
  // no-op against runNetworkAction's serialized guard.
  readonly property bool busy: actionKind !== ""

  // Index into `wifiNetworks` for keyboard navigation. -1 = no selection.
  property int selectedIndex: -1
  property bool wifiActionFocused: false
  property bool cursorActive: false

  // Keyboard focus zone for the panel. j/k crosses row boundaries:
  // header actions ⇄ band ⇄ DNS row ⇄ Wi-Fi networks. h/l move
  // within header actions, band pills, or DNS providers.
  property string focusSection: "dns"  // "header" | "band" | "dns" | "wifi"
  property int headerIndex: 0
  readonly property bool canDisconnect: !!connectedWifiNetwork
  readonly property bool headerHasDisconnect: false
  readonly property bool canShareWifi: info.type === "wifi" && canShareNetwork(connectedWifiNetwork)
  // The hero switch is the Wi-Fi radio, so it only exists when there is a
  // radio to switch. On a wired box it would otherwise sit there reading
  // "off" beside a perfectly live Ethernet connection.
  readonly property bool canToggleWifi: networkManagerAvailable && wifiStationAvailable
  readonly property int qrHeaderIndex: canShareWifi ? 0 : -1
  readonly property int speedHeaderIndex: canRunSpeedTest ? (canShareWifi ? 1 : 0) : -1
  readonly property int toggleHeaderIndex: canToggleWifi ? (canShareWifi ? 1 : 0) + (canRunSpeedTest ? 1 : 0) : -1
  readonly property int headerActionCount: (canShareWifi ? 1 : 0) + (canRunSpeedTest ? 1 : 0) + (canToggleWifi ? 1 : 0)
  readonly property bool qrHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === qrHeaderIndex
  readonly property bool speedHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === speedHeaderIndex
  readonly property bool toggleHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === toggleHeaderIndex
  readonly property string toggleHint: Networking.wifiEnabled ? "Turn Wi-Fi off" : "Turn Wi-Fi on"
  readonly property var dnsProviders: ["DHCP", "Cloudflare", "Google", "Custom"]
  property int dnsIndex: 0
  // ["2.4", "5", ...], or empty when there is nothing to choose between.
  // Wi-Fi only: on Ethernet the band of a secondary radio is not what the
  // panel is describing.
  // `bandBusy` keeps the section mounted across the reconnect a band change
  // causes: `kind` stops being "wifi" for a second or two in the middle of it,
  // and without this the whole segment would vanish and rebuild itself.
  // Worth showing when there is a real choice, or when a pin is in force even
  // though only one band answers right now -- otherwise the Automatic switch
  // vanishes and the pin becomes unclearable from the panel.
  readonly property bool canSelectBand: (kind === "wifi" || bandBusy)
    && (bandAvailable.length > 1 || bandPinned)
  // While a change is in flight, show the state that was asked for rather than
  // the one still in force, so the row answers the click immediately instead of
  // after the reconnect. actionProc puts it back if the change failed.
  readonly property string bandEffective: pendingBand !== "" ? pendingBand : bandSelected
  readonly property bool bandPinned: bandEffective !== "auto"
  // Under Automatic there is nothing to pick, so the pills collapse away and
  // the header states the live band instead.
  readonly property bool bandPillsVisible: canSelectBand && bandPinned
  readonly property string bandSectionTitle: Model.bandSectionTitle(bandEffective, bandCurrent)
  readonly property bool bandBusy: pendingBand !== ""
  // The speed test needs an interface to test, so its hero action only
  // appears once there is one.
  readonly property bool canRunSpeedTest: !!info.iface
  property int bandIndex: 0
  // The band section has up to two cursor rows: the Automatic switch on the
  // header line, then the pills. Same shape as wifiActionFocused.
  property bool bandAutoFocused: true

  onHeaderActionCountChanged: clampHeaderIndex()

  // Availability shifts as scans land, so the option list can shrink out from
  // under the cursor. Clamp the index and evacuate the section before it
  // disappears, or the panel is left highlighting nothing.
  onBandAvailableChanged: {
    if (bandIndex > bandAvailable.length - 1) bandIndex = Math.max(0, bandAvailable.length - 1)
  }

  onCanSelectBandChanged: {
    if (!canSelectBand && focusSection === "band") {
      focusSection = "dns"
      bandAutoFocused = true
    }
  }

  // Collapsing the pills out from under the cursor would leave it pointing at
  // nothing, so send it up to the switch that is still on screen.
  onBandPillsVisibleChanged: {
    if (!bandPillsVisible) bandAutoFocused = true
  }

  function clampHeaderIndex() {
    var max = Math.max(0, headerActionCount - 1)
    if (headerIndex > max) headerIndex = max
    if (headerIndex < 0) headerIndex = 0
  }

  function selectHeaderByDelta(delta) {
    headerIndex = Math.max(0, Math.min(headerActionCount - 1, headerIndex + delta))
  }

  function toggleNetwork() {
    if (!networkManagerAvailable) return
    Networking.wifiEnabled = !Networking.wifiEnabled
    Qt.callLater(function() { root.refresh(true) })
  }

  IpcHandler {
    target: "omarchy.network"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function toggleNetwork() { root.toggleNetwork() }
    // Compat routes for configs that summon the centered cards through the
    // network target; both cards are their own plugins now.
    function showQr() { root.summonWifiQr(true) }
    function speedTest() { root.summonSpeedTest() }
  }

  function activateHeader() {
    if (headerIndex === qrHeaderIndex) summonWifiQr()
    else if (headerIndex === speedHeaderIndex) summonSpeedTest()
    else if (headerIndex === toggleHeaderIndex) toggleNetwork()
  }

  function setHeaderCursor(index) {
    cursorActive = true
    focusSection = "header"
    headerIndex = index
  }

  function selectDnsByDelta(delta) {
    dnsIndex = Math.max(0, Math.min(dnsProviders.length - 1, dnsIndex + delta))
  }

  function activateDns() {
    if (dnsIndex < 0 || dnsIndex >= dnsProviders.length) return
    setDns(dnsProviders[dnsIndex])
  }

  function selectBandByDelta(delta) {
    bandIndex = Math.max(0, Math.min(bandAvailable.length - 1, bandIndex + delta))
  }

  function activateBand() {
    if (bandAutoFocused) {
      toggleBandAuto()
      return
    }
    if (bandIndex < 0 || bandIndex >= bandAvailable.length) return
    setBand(bandAvailable[bandIndex])
  }

  // Switching Automatic off has to commit to something, so it pins whatever
  // band the radio already landed on -- the reading the pills are showing.
  function toggleBandAuto() {
    if (bandSelected !== "auto") {
      setBand("auto")
      return
    }
    if (bandCurrent === "") return
    setBand(bandCurrent)
  }

  // Park the cursor on the pinned band, so opening the panel highlights the
  // pill the user would expect. Under Automatic there are no pills, so the
  // cursor belongs on the switch.
  function syncBandIndex() {
    var idx = bandAvailable.indexOf(bandSelected)
    bandIndex = idx >= 0 ? idx : 0
    bandAutoFocused = !bandPillsVisible
  }

  function bandLabel(band) {
    return Model.bandLabel(band)
  }

  function bandTooltip(band) {
    return Model.bandTooltip(band)
  }

  // Single cursor model: exactly one highlighted spot across the whole
  // panel, located via `focusSection` + (`headerIndex` | `dnsIndex` |
  // `selectedIndex`). Mouse hover and keyboard nav both mutate this state
  // at the root; items never read containsMouse for visuals. See
  // CursorSurface for the shared chrome shared by rows and pills.
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  // scannerEnabled lives on the shared WifiDevice, which has no reference
  // counting, and a bar widget is instantiated once per monitor. Tracking the
  // device this instance turned scanning on for keeps the release correct when
  // the panel closes, the device is replaced, or the widget is destroyed —
  // without a closed instance ever claiming the scanner.
  property var scannerDevice: null

  function setScannerEnabled(enabled) {
    var nextDevice = opened ? wifiDevice : null

    if (scannerDevice && scannerDevice !== nextDevice)
      scannerDevice.scannerEnabled = false

    scannerDevice = nextDevice

    if (scannerDevice)
      scannerDevice.scannerEnabled = enabled
  }

  Component.onDestruction: {
    if (scannerDevice) scannerDevice.scannerEnabled = false
  }

  // KeyboardPanel primes layer-shell focus whenever the panel opens. That's
  // what makes the SUPER+CTRL+W keybind land here with navigation ready.
  onOpenedChanged: {
    if (opened) {
      refresh(true)
      selectedIndex = wifiNetworks.length > 0 ? 0 : -1
      wifiActionFocused = false
      focusSection = wifiNetworks.length > 0 ? "wifi" : "dns"
      var idx = dnsProviders.indexOf(dnsProvider)
      dnsIndex = idx >= 0 ? idx : 0
      syncBandIndex()
      cursorActive = false
    } else {
      // Drop a restart armed by this open: without it a close/reopen inside
      // the 100ms window reuses the running timer and re-enables the scanner
      // almost immediately, undoing the deferral #6605 restored.
      scanRestart.stop()
      // Reset throughput tracking so the next open doesn't compute a fake
      // rate from a sample taken minutes ago.
      prevSampleTime = 0
      downloadRate = 0
      uploadRate = 0
      pingIface = ""
      routerPingSamples = []
      internetPingSamples = []
      routerPingLatency = -1
      internetPingLatency = -1
      internetPingPacketLoss = 0
      setScannerEnabled(false)
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
      wifiActionFocused = false
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

    if (selectedIndex < 0 || selectedIndex >= wifiNetworks.length || !canForgetNetwork(wifiNetworks[selectedIndex])) {
      wifiActionFocused = false
    }
  }

  onWifiDeviceChanged: {
    setScannerEnabled(true)
    syncWifiNetworks()
  }

  onWifiNetworkObjectsChanged: syncWifiNetworks()

  function selectByDelta(delta) {
    if (wifiNetworks.length === 0) { selectedIndex = -1; return }
    if (selectedIndex < 0) selectedIndex = delta > 0 ? 0 : wifiNetworks.length - 1
    else selectedIndex = Math.max(0, Math.min(wifiNetworks.length - 1, selectedIndex + delta))
    wifiActionFocused = false
  }

  function canForgetNetwork(net) {
    return Model.canForgetNetwork(net)
  }

  function canShareNetwork(net) {
    if (!net || !net.connected) return false
    return net.security !== WifiSecurityType.Wpa2Eap && net.security !== WifiSecurityType.WpaEap
  }

  function selectWifiActionByDelta(delta) {
    if (selectedIndex < 0 || selectedIndex >= wifiNetworks.length) return
    if (!canForgetNetwork(wifiNetworks[selectedIndex])) {
      wifiActionFocused = false
      return
    }
    if (delta > 0) wifiActionFocused = true
    else if (delta < 0) wifiActionFocused = false
  }

  // Enter/Space on the highlighted row. Mirrors row-click semantics:
  // connected → disconnect, credentials-required/unknown → prompt,
  // passwordless/known → connect.
  function activateSelected() {
    if (busy || selectedIndex < 0 || selectedIndex >= wifiNetworks.length) return
    var net = wifiNetworks[selectedIndex]
    if (!net) return
    if (wifiActionFocused && canForgetNetwork(net)) { forget(net); return }
    // Only act on a row that still resolves. disconnect() falls back to
    // connectedWifiNetwork when handed null, so a row left stale by scan churn
    // would otherwise tear down whatever is connected now instead.
    if (net.connected) { disconnectRow(net.ssid); return }
    if (requiresCredentials(net.security) && !net.known) { openPasswordPrompt(net.ssid); return }
    connectDirectly(net.ssid)
  }

  // Bar pill state, derived from the native NetworkManager service so the
  // icon reflects connection changes without polling. Wired is preferred
  // when both are up, matching the default-route device.
  readonly property var wiredDevice: findDevice(DeviceType.Wired)
  readonly property string kind: {
    if (wiredDevice && wiredDevice.connected) return "ethernet"
    if (connectedWifiNetwork) return "wifi"
    return "disconnected"
  }
  readonly property int signalStrength: connectedWifiNetwork
    ? Math.round((connectedWifiNetwork.signalStrength || 0) * 100)
    : -1

  function copyToClipboard(value) {
    if (!value || !root.bar) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(value) + " | wl-copy"])
  }

  readonly property string icon: Model.connectionIcon(kind, signalStrength)

  // The share card is its own panel plugin (omarchy.wifiqr) so a replacement
  // design can take it over; summon() routes to whichever implementation is
  // enabled. The panel's own button pins the interface it is showing. The
  // IPC route forces self-detection instead: details polling stops while the
  // panel is closed, so its cached interface can be stale.
  function summonWifiQr(forceDetect) {
    controller.hide()
    cancelPasswordPrompt()
    var payload = {}
    if (!forceDetect && info.type === "wifi" && info.iface) {
      payload.iface = info.iface
      if (info.ssid) payload.ssid = info.ssid
    }
    bar.shell.summon("omarchy.wifiqr", JSON.stringify(payload))
  }

  function refresh(scanWifi) {
    if (scanWifi === undefined) scanWifi = false
    if (!detailsProc.running) detailsProc.running = true
    if (!dnsProc.running) {
      dnsProc.command = ["bash", "-c", root.dnsCommand("")]
      dnsProc.running = true
    }
    if (!bandProc.running) {
      bandProc.command = ["omarchy-network-band"]
      bandProc.running = true
    }
    // A closed panel has no nearby-network list to fill, and bare refresh()
    // reaches here from action completion, timeouts and construction.
    if (opened && wifiDevice) {
      if (scanWifi) {
        scanning = true
        setScannerEnabled(false)
        scanRestart.start()
      } else {
        setScannerEnabled(true)
      }
    }
    syncWifiNetworks()
  }

  function formatHeaderSpeed(mbps) {
    return Model.formatHeaderSpeed(mbps)
  }

  function formatHeaderFreq(mhz) {
    return Model.formatHeaderFreq(mhz)
  }

  function headerDetail() {
    return Model.headerDetail(info)
  }

  function updateDetails(raw) {
    var next = Model.parseKeyValue(raw)

    // A band change tears the link down and brings it back, and the status
    // command reports nothing at all while there is no route. Publishing that
    // would blank every stat and unmount the whole section mid-toggle, so the
    // last good sample stands until the reconnect settles. A real disconnect is
    // still reported, because nothing is in flight then.
    if (bandBusy && !next.iface) return

    info = next
    updateThroughput(next)
    updatePingLatency(next)
  }

  function updateThroughput(next) {
    var state = Model.throughputState({
      prevIface: prevIface,
      prevRxBytes: prevRxBytes,
      prevTxBytes: prevTxBytes,
      prevSampleTime: prevSampleTime,
      downloadRate: downloadRate,
      uploadRate: uploadRate
    }, next, Date.now() / 1000)

    prevIface = state.prevIface
    prevRxBytes = state.prevRxBytes
    prevTxBytes = state.prevTxBytes
    prevSampleTime = state.prevSampleTime
    downloadRate = state.downloadRate
    uploadRate = state.uploadRate
  }

  function updatePingLatency(next) {
    var state = Model.pingLatencyState({
      pingIface: pingIface,
      routerPingSamples: routerPingSamples,
      internetPingSamples: internetPingSamples
    }, next, pingHistoryWindow, pingAverageWindow)

    pingIface = state.pingIface
    routerPingSamples = state.routerPingSamples
    internetPingSamples = state.internetPingSamples
    routerPingLatency = state.routerPingLatency
    internetPingLatency = state.internetPingLatency
    internetPingPacketLoss = state.internetPingPacketLoss
  }

  function formatBytes(bytes) {
    return Model.formatBytes(bytes)
  }

  function formatRate(bytesPerSec) {
    return Model.formatRate(bytesPerSec)
  }

  function formatPingLatency(ms) {
    return Model.formatPingLatency(ms, hasInternetPing)
  }

  function formatPacketLoss(percent) {
    return Model.formatPacketLoss(percent, hasInternetPing)
  }

  // Prefer a connected device: a machine can expose several NICs of the
  // same type (e.g. an idle onboard port alongside the active adapter),
  // and the first-enumerated one may be carrierless.
  function findDevice(type) {
    var devices = networkDevices || []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (!device || device.type !== type) continue
      if (device.connected) return device
      if (!fallback) fallback = device
    }
    return fallback
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
      var row = Model.wifiRow(network)
      if (row) nets.push(row)
    }
    wifiNetworks = Model.sortWifiRows(nets)
    wifiStationAvailable = !!wifiDevice
    scanning = false
  }

  function wifiSectionTitle(index) {
    return Model.wifiSectionTitle(wifiNetworks, index)
  }

  function wifiIconFor(strength) {
    return Model.wifiIconFor(strength)
  }

  function updateDns(raw) {
    var value = String(raw || "").trim()
    dnsProvider = value || "DHCP"
  }

  function updateBand(raw) {
    var status = Model.parseBandStatus(raw)

    // Mid-reconnect there is no connected station, so the command reports
    // nothing. Publishing that would empty the option list and unmount the
    // section on every toggle -- same guard as updateDetails.
    if (bandBusy && status.available.length === 0) return

    bandCurrent = status.band
    bandSelected = status.selected
    bandAvailable = status.available
  }

  // Pinning a band reassociates, but the panel deliberately stays open: the
  // reconnect is the thing you want to watch, and the details rows above
  // report it as it happens.
  function setBand(band) {
    if (!band || actionProc.running) return

    root.pendingBand = band
    actionProc.command = ["omarchy-network-band", band]
    actionProc.running = true
  }

  // The speed test is its own panel plugin (omarchy.speedtest) so a
  // replacement design can take it over; summon() routes to whichever
  // implementation is enabled. The payload names the connection when this
  // panel knows it; the plugin looks it up itself otherwise.
  function summonSpeedTest() {
    controller.hide()
    cancelPasswordPrompt()
    var connection = ""
    if (info.type === "wifi") connection = info.ssid || "Wi-Fi"
    else if (info.type === "ethernet") connection = "Ethernet"
    bar.shell.summon("omarchy.speedtest", connection ? JSON.stringify({ connection: connection }) : "{}")
  }

  function dnsCommand(provider) {
    var command = "omarchy-dns"
    if (provider) command += " " + Util.shellQuote(provider)
    return command
  }

  function setDns(provider) {
    if (!root.bar || !provider || actionProc.running) return

    if (provider === "Custom") {
      var launcher = "omarchy-launch-floating-terminal-with-presentation"
      root.bar.run(launcher + " " + Util.shellQuote(root.dnsCommand(provider)))
      root.close()
      return
    }

    root.pendingDnsProvider = provider
    actionProc.command = ["bash", "-c", root.dnsCommand(provider)]
    actionProc.running = true
    root.close()
  }

  function requiresCredentials(security) {
    return Model.requiresCredentials(security, WifiSecurityType.Open, WifiSecurityType.Owe)
  }

  function openPasswordPrompt(ssid) {
    if (passwordSsid !== ssid) {
      passwordText = ""
      identityText = ""
    }
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
    failureReason = networkFailureReason(reason, requiresCredentials(network.security))
    actionSsid = ""
    actionKind = ""
    refresh()
  }

  function networkFailureReason(reason, needsCredentials) {
    return Model.networkFailureReason(reason, needsCredentials, connectionFailReasons)
  }

  function shouldRepromptPassphrase(reason, needsCredentials) {
    return Model.shouldRepromptPassphrase(reason, needsCredentials, connectionFailReasons)
  }

  function checkActionCompletion(network) {
    if (!network || actionKind === "" || actionSsid !== (network.name || "")) return
    if (actionKind === "connect" && network.connected) clearNetworkAction()
    else if (actionKind === "disconnect" && !network.connected && !network.stateChanging) clearNetworkAction()
    else if (actionKind === "forget" && !network.known && !network.stateChanging) clearNetworkAction()
  }

  function connectDirectly(ssid) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) { network.connect() })
  }

  function connectWithPassphrase(ssid, passphrase) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) { network.connectWithPsk(passphrase) })
  }

  function connectEnterprise(ssid, identity, passphrase) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) {
      enterpriseConnect.secret = passphrase
      enterpriseConnect.command = ["bash", "-c", Model.enterpriseConnectScript, "nmcli-eap", ssid, identity]
      enterpriseConnect.running = true
    })
  }

  // Creates and activates the 802.1X profile (see Model.enterpriseConnectScript).
  // The password goes over stdin, never argv.
  Process {
    id: enterpriseConnect
    property string secret: ""
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
    }
  }

  function disconnect(network) {
    runNetworkAction("disconnect", network || connectedWifiNetwork, function(net) { net.disconnect() })
  }

  // Disconnect from a row's SSID. Rows are primitive snapshots that can outlive
  // their WifiNetwork, and disconnect()'s null fallback targets whatever is
  // connected now, so a stale row must do nothing rather than hit an unrelated
  // network. Callers that mean "drop the current connection" call disconnect().
  function disconnectRow(ssid) {
    var network = networkForSsid(ssid)
    if (network) disconnect(network)
  }

  function forget(net) {
    runNetworkAction("forget", net ? networkForSsid(net.ssid) : null, function(network) { network.forget() })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  // Pulls everything we want about the active route's interface in one shot.
  Process {
    id: detailsProc
    command: ["omarchy-network-status", "--verbose"]
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
      if (root.opened && root.wifiDevice) {
        root.setScannerEnabled(true)
        scanDone.start()
      }
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

  Process {
    id: bandProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateBand(text)
    }
  }

  // Slower than detailsPoll on purpose: this shells out to nmcli several times,
  // and band availability only moves when a scan turns up a new BSSID.
  Timer {
    id: bandPoll
    interval: 4000
    repeat: true
    running: root.opened
    onTriggered: {
      if (bandProc.running) return
      bandProc.command = ["omarchy-network-band"]
      bandProc.running = true
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
      if (root.pendingBand !== "") {
        // A refused or reverted pin leaves bandSelected alone, so the pills
        // keep showing what is actually in force rather than what was asked.
        if (exitCode === 0) root.bandSelected = root.pendingBand
        root.pendingBand = ""
        // The panel stayed open through the reconnect, so pull fresh state now
        // instead of leaving stale readings until the next poll tick.
        root.refresh()
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
    id: connectionPhraseTimer
    interval: 2800
    running: root.opened && (root.info.type === "ethernet" || (root.info.type === "wifi" && root.canDisconnect))
    repeat: true
    onTriggered: connectionPhraseSwap.restart()
  }

  SequentialAnimation {
    id: connectionPhraseSwap
    PropertyAnimation {
      target: heroMeta; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.connectionPhraseIndex = (root.connectionPhraseIndex + 1) % root.connectionPhrases.length
    }
    PropertyAnimation {
      target: heroMeta; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  Connections {
    target: root
    function onInfoChanged() {
      if (!(root.info.type === "ethernet" || (root.info.type === "wifi" && root.canDisconnect))) {
        connectionPhraseSwap.stop()
        heroMeta.opacity = 1.0
      }
    }
  }

  Timer {
    id: actionTimeout
    // Must outlast NetworkManager's 25s supplicant timeout: a wrong saved
    // PSK fails with WifiAuthTimeout at ~25s, and that failure has to land
    // while the action is still tracked to show "Wrong password" and reopen
    // the passphrase prompt.
    interval: 30000
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

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon

    onPressed: function(b) {
      if (root.opened) root.close()
      // open() is enough: onOpenedChanged runs refresh(true), which defers the
      // PHY scan past the first frame. The bare refresh() that used to follow
      // took the no-scan branch and set scannerEnabled synchronously, undoing
      // that deferral and stalling the open on NetworkManager's AP flood.
      else root.open()
    }
  }

  // Keyboard-driven popup anchored to the bar widget icon. The shared
  // KeyboardPanel handles the layer-shell PanelWindow scaffolding
  // (focus priming on open, screen binding, anchored-to-icon positioning,
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
          // Vertical order is header ⇄ band ⇄ DNS ⇄ wifi, with the band section
          // dropping out of the chain entirely when it isn't on screen.
          if (root.focusSection === "header") {
            if (dy > 0) {
              if (root.canSelectBand) {
                root.focusSection = "band"
                root.bandAutoFocused = true
              } else {
                root.focusSection = "dns"
              }
            }
          } else if (root.focusSection === "band") {
            // Automatic on the header line, then the pills -- which collapse
            // away under Automatic, leaving a single row to walk.
            if (dy < 0) {
              if (!root.bandAutoFocused) {
                root.bandAutoFocused = true
              } else if (root.headerActionCount > 0) {
                root.focusSection = "header"
                root.headerIndex = 0
              }
            } else if (root.bandAutoFocused && root.bandPillsVisible) {
              root.bandAutoFocused = false
            } else {
              root.focusSection = "dns"
            }
          } else if (root.focusSection === "dns") {
            // k from DNS moves up into the band section when it's on screen,
            // then the disconnect button; otherwise stays put. j drops into the
            // wifi list if there's anywhere to land.
            if (dy < 0) {
              if (root.canSelectBand) {
                root.focusSection = "band"
                root.bandAutoFocused = !root.bandPillsVisible
              } else if (root.headerActionCount > 0) {
                root.focusSection = "header"
                root.headerIndex = 0
              }
            } else if (root.wifiNetworks.length > 0) {
              root.focusSection = "wifi"
              if (root.selectedIndex < 0) root.selectedIndex = 0
            }
          } else {  // wifi
            // k from the top row escapes back up to the DNS row rather than
            // wrapping around to the bottom of the list.
            if (dy < 0 && root.selectedIndex <= 0) {
              root.focusSection = "dns"
              root.wifiActionFocused = false
            }
            else root.selectByDelta(dy)
          }
        }
        if (dx !== 0) {
          if (root.focusSection === "header") root.selectHeaderByDelta(dx)
          else if (root.focusSection === "band") { if (!root.bandAutoFocused) root.selectBandByDelta(dx) }
          else if (root.focusSection === "dns") root.selectDnsByDelta(dx)
          else if (root.focusSection === "wifi") root.selectWifiActionByDelta(dx)
        }
      }
      onActivateRequested: {
        if (root.cursorActive) {
          if (root.focusSection === "header") root.activateHeader()
          else if (root.focusSection === "band") root.activateBand()
          else if (root.focusSection === "dns") root.activateDns()
          else root.activateSelected()
        }
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "w" || t === "W") root.toggleNetwork()
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
        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroActions.implicitHeight)

        // Status only — the switch owns toggling, mouse and keyboard alike.
        Text {
          id: heroIcon
          text: root.icon
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.display
          opacity: root.networkManagerAvailable ? 1.0 : 0.5
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        // Sharing belongs to the connected-network hero rather than the scan
        // result row. The radio switch remains beside it as the other hero action.
        RowLayout {
          id: heroActions
          spacing: Style.space(8)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter

          Button {
            id: qrAction
            visible: root.canShareWifi
            iconText: "󰐲"
            tooltipText: "Show QR code"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconSize: Style.font.subtitle * 1.5
            horizontalPadding: Style.space(5)
            verticalPadding: Style.space(2)
            hasCursor: root.qrHeaderHasCursor
            Layout.alignment: Qt.AlignVCenter
            onHovered: function(on) { if (on) root.setHeaderCursor(root.qrHeaderIndex) }
            onClicked: root.summonWifiQr()
          }

          Button {
            id: speedAction
            visible: root.canRunSpeedTest
            iconText: "󰓅"
            tooltipText: "Run a speed test"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconSize: Style.font.subtitle * 1.5
            horizontalPadding: Style.space(5)
            verticalPadding: Style.space(2)
            hasCursor: root.speedHeaderHasCursor
            Layout.alignment: Qt.AlignVCenter
            onHovered: function(on) { if (on) root.setHeaderCursor(root.speedHeaderIndex) }
            onClicked: root.summonSpeedTest()
          }

          ToggleSwitch {
            id: powerSwitch
            visible: root.canToggleWifi
            checked: Networking.wifiEnabled
            hasCursor: root.toggleHeaderHasCursor
            foreground: root.bar.foreground
            Layout.alignment: Qt.AlignVCenter
            onHovered: function(on) { if (on) root.setHeaderCursor(root.toggleHeaderIndex) }
            onToggled: root.toggleNetwork()

            PanelToolTip {
              visible: powerSwitch.containsMouse
              text: root.toggleHint
              fontFamily: root.bar.fontFamily
            }
          }
        }

        Column {
          id: heroLabels
          anchors.left: heroIcon.right
          anchors.leftMargin: Style.space(14)
          anchors.right: parent.right
          anchors.rightMargin: heroActions.width > 0 ? heroActions.width + Style.space(12) : 0
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          // Link detail rides inline after the name — "Ethernet (2.5gbit)" —
          // rather than in a pill, which crowded the on/off switch.
          Text {
            id: heroSsid
            width: parent.width

            readonly property string title: {
              if (root.info.type === "wifi") return root.info.ssid || "Wi-Fi"
              if (root.info.type === "ethernet") return "Ethernet"
              return root.info.iface || (root.kind === "disconnected" ? "Disconnected" : "No connection")
            }
            readonly property string detail: root.headerDetail()

            text: heroSsid.detail !== "" ? heroSsid.title + " (" + heroSsid.detail + ")" : heroSsid.title
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
                if (root.canDisconnect) return root.connectionPhrase.toUpperCase()
                if (root.kind === "disconnected") return "NOT CONNECTED"
                return ""
              }
              if (root.info.type === "ethernet") return root.connectionPhrase.toUpperCase()
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

      }

      // Connection details: transfer metrics first, then IP/Gateway.
      Column {
        visible: !!root.info.iface
        width: parent.width
        spacing: Style.spacing.labelGap

        GridLayout {
          width: parent.width
          columns: 4
          columnSpacing: Style.space(20)
          rowSpacing: Style.spacing.labelGap

          // Always mounted: these two used to appear a beat after the panel
          // opened, once the first probe returned, shoving everything below
          // them down. They now hold their place and read "--" until there is
          // a sample.
          InfoLabel { text: "Ping" }
          DetailValue {
            text: root.formatPingLatency(root.internetPingLatency)
            color: root.internetPingPacketLoss > 0 ? root.bar.urgent : root.bar.foreground
          }
          InfoLabel { text: "Packet Loss" }
          DetailValue {
            text: root.formatPacketLoss(root.internetPingPacketLoss)
            color: root.internetPingPacketLoss > 0 ? root.bar.urgent : root.bar.foreground
          }

          InfoLabel { text: "Receiving" }
          DetailValue { text: root.hasTransferStats ? root.formatRate(root.downloadRate) : "--" }
          InfoLabel { text: "Sending" }
          DetailValue { text: root.hasTransferStats ? root.formatRate(root.uploadRate) : "--" }

          InfoLabel { text: "Downloaded" }
          DetailValue { text: root.hasTransferStats ? root.formatBytes(parseFloat(root.info.rx_bytes || "0")) : "--" }
          InfoLabel { text: "Uploaded" }
          DetailValue { text: root.hasTransferStats ? root.formatBytes(parseFloat(root.info.tx_bytes || "0")) : "--" }

          InfoLabel { text: "IP Address" }
          DetailValue {
            text: root.info.ip || "--"
            copyable: !!root.info.ip
            tooltipText: "Copy IP"
          }
          InfoLabel { text: "Gateway" }
          DetailValue {
            text: root.info.gateway || "--"
            copyable: !!root.info.gateway
            tooltipText: "Copy gateway"
          }
        }
      }

      // Wi-Fi band selection. Only on Wi-Fi, and only when the network answers
      // on more than one band -- a single-band AP has nothing to toggle.
      PanelSeparator {
        visible: root.canSelectBand
        foreground: root.bar.foreground
      }

      Column {
        visible: root.canSelectBand
        width: parent.width
        spacing: Style.space(10)

        // "Automatic" rides on the header line rather than under the pills: it
        // qualifies the whole row, and at header scale it reads as a modifier
        // instead of competing with the band choices for attention.
        Item {
          width: parent.width
          implicitHeight: Math.max(bandHeader.implicitHeight, bandAutoRow.implicitHeight)

          PanelSectionHeader {
            id: bandHeader
            text: root.bandSectionTitle
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Row {
            id: bandAutoRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            PanelSectionHeader {
              id: bandAutoLabel
              text: "AUTOMATIC"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.verticalCenter: parent.verticalCenter
            }

            // Sized off the label rather than the theme's control height so it
            // reads as part of the header, and centred on the label's *glyphs*:
            // PanelSectionHeader carries topPadding to protect Nerd Font
            // overshoot, which pushes its text below its own box centre, so a
            // plain verticalCenter would sit the switch visibly high.
            ToggleSwitch {
              id: bandAutoSwitch
              trackHeight: Math.round(bandAutoLabel.font.pixelSize * 1.2)
              cursorPad: Style.space(3)
              anchors.verticalCenter: bandAutoLabel.verticalCenter
              anchors.verticalCenterOffset: Math.round(bandAutoLabel.topPadding / 2)
              checked: !root.bandPinned
              busy: root.bandBusy
              hasCursor: root.cursorActive && root.focusSection === "band" && root.bandAutoFocused
              foreground: root.bar.foreground
              onToggled: root.toggleBandAuto()

              onHovered: function(isHovered) {
                if (!isHovered) return
                root.cursorActive = true
                root.focusSection = "band"
                root.bandAutoFocused = true
              }

              PanelToolTip {
                visible: bandAutoSwitch.containsMouse
                text: root.bandPinned
                  ? "Let Wi-Fi pick the band"
                  : "Stay on " + root.bandLabel(root.bandCurrent)
                fontFamily: root.bar.fontFamily
              }
            }
          }
        }

        // Collapsing container: the pills animate their height so toggling
        // Automatic slides the sections below into place instead of snapping.
        // `visible` only drops at a real zero, which keeps the row rendered for
        // the whole animation and takes it out of the Column's spacing once
        // it's actually gone.
        Item {
          id: bandPillsClip
          width: parent.width
          clip: true
          visible: height > 0
          height: root.bandPillsVisible ? bandRow.implicitHeight : 0
          opacity: root.bandPillsVisible ? 1 : 0

          Behavior on height {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }
          Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }

          Row {
            id: bandRow
            width: parent.width
            spacing: Style.space(6)

            readonly property int count: Math.max(1, root.bandAvailable.length)
            readonly property real cellWidth: (width - spacing * (count - 1)) / count

            // Wrapper takes modelData/index from the Repeater's delegate
            // context, which doesn't bind into nested `component` declarations,
            // and passes them down explicitly -- same shape as the network
            // list delegate.
            Repeater {
              model: root.bandAvailable

              delegate: Item {
                required property var modelData
                required property int index
                width: bandRow.cellWidth
                height: bandPill.implicitHeight

                BandPill {
                  id: bandPill
                  band: modelData
                  slot: index
                  width: parent.width
                }
              }
            }
          }
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
        visible: root.wifiStationAvailable && root.scanning
        text: "SCANNING WI-FI…"
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
          readonly property string sectionTitle: root.wifiSectionTitle(index)
          width: ListView.view.width
          height: delegateColumn.implicitHeight

          Column {
            id: delegateColumn
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              visible: sectionTitle !== ""
              text: sectionTitle
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              height: visible ? implicitHeight : 0
            }

            NetworkRow {
              id: row
              width: parent.width
              net: modelData
              index: parent.parent.index
            }
          }
        }
      }
    }
    }
  }

  // One Wi-Fi band pill. `active` (fill) is the band actually in use and
  // `selected` (bold) is the pinned choice; with Automatic on nothing is
  // pinned, so only the live band lights up and the two can no longer read as
  // a contradiction. They land on the same pill once a band is pinned.
  component BandPill: Button {
    id: pill
    required property string band
    required property int slot

    text: root.bandLabel(band)
    tooltipText: root.bandTooltip(band)
    fontSize: Style.font.bodySmall
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
    bordered: true

    active: root.bandCurrent === band
    selected: root.bandEffective === band
    hasCursor: root.cursorActive && root.focusSection === "band"
      && !root.bandAutoFocused && root.bandIndex === slot

    onClicked: root.setBand(band)

    onHovered: function(isHovered) {
      if (!isHovered) return
      root.cursorActive = true
      root.focusSection = "band"
      root.bandIndex = pill.slot
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
  // expands inline to a passphrase prompt when the user picks a network that
  // requires credentials we do not have. Clicking a connected row
  // disconnects.
  component NetworkRow: CursorSurface {
    id: row
    required property var net
    required property int index

    readonly property bool isConnected: net && net.connected
    readonly property bool isKnown: !!(net && net.known)
    readonly property bool requiresCredentials: net ? root.requiresCredentials(net.security) : false
    readonly property bool isEnterprise: net
      ? (net.security === WifiSecurityType.Wpa2Eap || net.security === WifiSecurityType.WpaEap)
      : false
    readonly property bool canForget: root.canForgetNetwork(net)
    readonly property bool isSelected: root.focusSection === "wifi" && root.selectedIndex === index
    property bool autoConnect: false
    property bool autoConnectLoaded: false
    property bool autoConnectBusy: false
    readonly property bool forgetFocused: isSelected && root.wifiActionFocused && canForget
    readonly property bool forgetVisible: canForget && (!requiresCredentials || forgetFocused || rightMouse.containsMouse)

    hasCursor: root.cursorActive && isSelected && !root.wifiActionFocused
    current: isConnected
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    // Gate on the matching *Kind/*Reason being non-empty so a hidden-SSID
    // row (ssid == "") doesn't match the "" defaults of actionSsid etc.
    readonly property bool isBusy: root.actionKind !== "" && root.actionSsid === (net ? net.ssid : "")
    readonly property bool isFailed: root.failureReason !== "" && root.failureSsid === (net ? net.ssid : "")
    readonly property bool isPasswordOpen: root.passwordSsid !== "" && root.passwordSsid === (net ? net.ssid : "")

    function submitCredentials() {
      if (!net || root.busy || root.passwordText.length === 0) return
      if (!isEnterprise) return root.connectWithPassphrase(net.ssid, root.passwordText)
      if (root.identityText.length > 0) root.connectEnterprise(net.ssid, root.identityText, root.passwordText)
    }

    Connections {
      target: row.net ? root.networkForSsid(row.net.ssid) : null
      function onConnectionFailed(reason) {
        // Background auto-connect retries fire this too; only reprompt for
        // the connect started from this panel. Checked before
        // failNetworkAction, which clears the action state.
        var ours = root.actionKind === "connect" && root.actionSsid === (row.net.ssid || "")
        root.failNetworkAction(root.networkForSsid(row.net.ssid), reason)
        if (ours && root.shouldRepromptPassphrase(reason, row.requiresCredentials)) root.openPasswordPrompt(row.net.ssid)
      }
      function onConnectedChanged() {
        if (row.net) root.checkActionCompletion(root.networkForSsid(row.net.ssid))
      }
      function onKnownChanged() {
        if (row.net) root.checkActionCompletion(root.networkForSsid(row.net.ssid))
      }
      function onStateChangingChanged() {
        if (row.net) root.checkActionCompletion(root.networkForSsid(row.net.ssid))
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
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.focusSection = "wifi"; root.selectedIndex = row.index; root.wifiActionFocused = false }

      onClicked: {
        if (!row.net) return
        // Resync cursor in case keyboard nav moved it away while the mouse
        // stayed parked on this row — the click target is unambiguously here.
        root.cursorActive = true
        root.focusSection = "wifi"
        root.selectedIndex = row.index
        root.wifiActionFocused = false
        if (row.isConnected) {
          root.disconnectRow(row.net.ssid)
          return
        }
        if (row.requiresCredentials && !row.isKnown) {
          root.openPasswordPrompt(row.net.ssid)
          return
        }
        root.connectDirectly(row.net.ssid)
      }
    }

    Item {
      id: rowBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(networkIcon.implicitHeight, networkInfo.implicitHeight, rightAction.implicitHeight) + Style.spacing.rowPaddingX

      Text {
        id: networkIcon
        text: row.net ? root.wifiIconFor(row.net.signal) : ""
        color: row.statusColor
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      // Saved visible networks expose NetworkManager's auto-connect state.
      // Turning it off changes only future automatic activation.
      Row {
        id: rightAction
        visible: row.isKnown || row.requiresCredentials
        spacing: Style.space(4)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        ToggleSwitch {
          visible: row.isKnown && row.autoConnectLoaded
          checked: row.autoConnect
          busy: row.autoConnectBusy
          cursorRing: false
          foreground: root.bar.foreground
          onToggled: row.setAutoConnect(!row.autoConnect)

          PanelToolTip {
            visible: parent.containsMouse
            text: row.autoConnect ? "Auto-connect enabled" : "Auto-connect disabled"
            fontFamily: root.bar.fontFamily
          }
        }

        Item {
          visible: row.requiresCredentials || row.canForget
          width: Style.space(22)
          height: lockIndicator.implicitHeight

          Text {
            id: lockIndicator
            visible: row.requiresCredentials || row.forgetVisible
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: row.forgetVisible ? "󰅙" : "󰌾"
            color: row.forgetVisible ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
          }

          BorderSurface {
            anchors.fill: parent
            visible: row.forgetFocused
            color: Style.hoverFillFor(root.bar.urgent, root.bar.urgent)
            borderSpec: Border.controlSpec("hover-cursor", root.bar.urgent, root.bar.urgent)
            radius: Style.cornerRadius
            z: -1
          }

          MouseArea {
            id: rightMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            enabled: row.canForget && !root.busy
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.focusSection = "wifi"; root.selectedIndex = row.index; root.wifiActionFocused = true }
            onClicked: if (row.net) root.forget(row.net)
          }

          PanelToolTip {
            visible: rightMouse.containsMouse || row.forgetFocused
            text: "Forget network"
            fontFamily: root.bar.fontFamily
          }
        }
      }

      Column {
        id: networkInfo
        spacing: Style.space(1)
        anchors.left: networkIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: rightAction.visible ? rightAction.left : parent.right
        anchors.rightMargin: rightAction.visible ? Style.space(8) : 0
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

    function refreshAutoConnect() {
      if (!row.isKnown || !row.net || autoConnectState.running) return
      autoConnectState.command = ["nmcli", "-g", "connection.autoconnect", "connection", "show", "id", row.net.ssid]
      autoConnectState.running = true
    }

    function setAutoConnect(enabled) {
      if (!row.net || row.autoConnectBusy) return
      row.autoConnectBusy = true
      autoConnectChange.desired = enabled
      autoConnectChange.command = ["nmcli", "connection", "modify", "id", row.net.ssid, "connection.autoconnect", enabled ? "yes" : "no"]
      autoConnectChange.running = true
    }

    Process {
      id: autoConnectState
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          row.autoConnect = text.trim().split("\n")[0] === "yes"
          row.autoConnectLoaded = true
        }
      }
    }

    Process {
      id: autoConnectChange
      property bool desired: false
      onExited: function(exitCode) {
        row.autoConnectBusy = false
        if (exitCode === 0) {
          row.autoConnect = desired
          row.autoConnectLoaded = true
        } else {
          row.refreshAutoConnect()
        }
      }
    }

    Component.onCompleted: refreshAutoConnect()

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

    // Inline passphrase prompt — shown when we hit a protected network we
    // don't have saved credentials for, or when a connect fails because the
    // saved passphrase is wrong. Submitting (Enter or the check button) fires
    // connect; Esc cancels back to the row.
    Item {
      id: passwordPanel
      visible: row.isPasswordOpen
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: rowMouse.bottom
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      anchors.topMargin: Style.space(4)
      implicitHeight: (idField.visible ? idField.implicitHeight + Style.space(4) : 0) + pwField.implicitHeight + Style.spacing.rowGap
      height: implicitHeight

      TextField {
        id: idField
        visible: row.isEnterprise && !row.isBusy && !row.isFailed
        anchors.left: parent.left
        anchors.right: connectPwBtn.left
        anchors.top: parent.top
        anchors.rightMargin: Style.space(6)
        placeholderText: "Identity (user@domain)"
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        foreground: root.bar.foreground
        horizontalPadding: Style.spacing.controlGap
        verticalPadding: Style.spacing.controlPaddingY
        enabled: !row.isBusy
        text: row.isPasswordOpen ? root.identityText : ""

        onAccepted: pwField.forceActiveFocus()
        onTextChanged: if (row.isPasswordOpen && text !== root.identityText) root.identityText = text
        Keys.onEscapePressed: root.cancelPasswordPrompt()

        onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
        Component.onCompleted: if (visible) Qt.callLater(forceActiveFocus)
      }

      TextField {
        id: pwField
        visible: !row.isBusy && !row.isFailed
        anchors.left: parent.left
        anchors.right: connectPwBtn.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.rowGap / 2
        anchors.rightMargin: Style.space(6)
        password: true
        placeholderText: "Passphrase"
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        foreground: root.bar.foreground
        horizontalPadding: Style.spacing.controlGap
        verticalPadding: Style.spacing.controlPaddingY
        enabled: !row.isBusy
        text: row.isPasswordOpen ? root.passwordText : ""

        onAccepted: row.submitCredentials()
        onTextChanged: if (row.isPasswordOpen && text !== root.passwordText) root.passwordText = text
        Keys.onEscapePressed: root.cancelPasswordPrompt()

        onVisibleChanged: if (visible && !row.isEnterprise) Qt.callLater(forceActiveFocus)
        Component.onCompleted: if (visible && !row.isEnterprise) Qt.callLater(forceActiveFocus)
      }

      BorderSurface {
        id: statusMsgWrapper
        visible: row.isBusy || row.isFailed
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Style.spacing.controlHeight
        color: Style.normalFillFor(root.bar.foreground)
        borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
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

      // 22×22 right-anchored to line up with lockIndicator above. Esc closes
      // the prompt (handled by pwField.Keys.onEscapePressed)
      // so there's no separate cancel button.
      PanelActionButton {
        id: connectPwBtn
        visible: !row.isBusy && !row.isFailed
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        enabled: row.net && pwField.text.length > 0 && (!row.isEnterprise || idField.text.length > 0)
        iconText: "󰄬"
        tooltipText: "Connect"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onClicked: row.submitCredentials()
      }
    }
  }


  component DetailValue: InfoValue {
    property bool copyable: false
    property string tooltipText: "Copy to clipboard"

    Layout.fillWidth: true
    horizontalAlignment: Text.AlignRight

    MouseArea {
      id: valueMouse
      anchors.fill: parent
      enabled: copyable && parent.text !== ""
      hoverEnabled: enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.copyToClipboard(parent.text)
    }

    PanelToolTip {
      visible: valueMouse.enabled && valueMouse.containsMouse
      text: tooltipText
      fontFamily: root.bar.fontFamily
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
