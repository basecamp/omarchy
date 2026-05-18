import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "networkPanel"
  property var settings: ({})

  property bool popupOpen: false
  // Centralized close so callers can't forget to drop the passphrase prompt.
  function closePopout() {
    popupOpen = false
    passwordSsid = ""
  }

  // Live connection details from `ip` / /sys / iw.
  property var info: ({})  // { iface, type, ip, prefix, gateway, speed, duplex, ssid, signal, freq, bitrate }
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

  // True while any wifi action or known-network probe is mid-flight. Rows
  // disable themselves on this so clicks on the other rows don't silently
  // no-op against runAction's serialized guard.
  readonly property bool busy: actionProc.running || knownCheck.running

  // Index into `wifiNetworks` for keyboard navigation. -1 = no selection.
  property int selectedIndex: -1

  // Keyboard focus zone for the panel. j/k crosses the boundary: from the
  // top of the wifi list a k goes back up to the DNS row, j from DNS drops
  // into the wifi list. h/l only mean something while focused on DNS.
  property string focusSection: "dns"  // "dns" | "wifi"
  readonly property var dnsProviders: ["DHCP", "Cloudflare", "Google", "Custom"]
  property int dnsIndex: 0

  function selectDnsByDelta(delta) {
    dnsIndex = Math.max(0, Math.min(dnsProviders.length - 1, dnsIndex + delta))
  }

  function activateDns() {
    if (dnsIndex < 0 || dnsIndex >= dnsProviders.length) return
    setDns(dnsProviders[dnsIndex])
  }

  // Single cursor model: exactly one highlighted spot across the whole
  // panel, located via `focusSection` + (`selectedIndex` | `dnsIndex`).
  // Mouse hover and keyboard nav both mutate this state at the root; items
  // never read containsMouse for visuals. See CursorSurface for the
  // shared chrome (fill / border) shared by NetworkRow and DnsProviderPill.
  readonly property color hoverFill: bar ? Qt.rgba(bar.foreground.r, bar.foreground.g, bar.foreground.b, 0.08) : "transparent"
  readonly property color selectedFill: bar ? Qt.rgba(bar.foreground.r, bar.foreground.g, bar.foreground.b, 0.18) : "transparent"

  // The panel below is its own layer-shell with Exclusive keyboard focus,
  // so Hyprland grants focus when the surface is mapped (popupOpen flips
  // to true). That's what makes the SUPER+CTRL+W keybind actually work
  // — OnDemand only grants focus on click/hover.
  onPopupOpenChanged: {
    if (popupOpen) {
      refresh()
      selectedIndex = wifiNetworks.length > 0 ? 0 : -1
      focusSection = "dns"
      var idx = dnsProviders.indexOf(dnsProvider)
      dnsIndex = idx >= 0 ? idx : 0
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }
  }

  // When the passphrase prompt closes (Esc / Cancel / success) restore
  // focus to the keyCatcher so j/k/Enter resume working without a click.
  onPasswordSsidChanged: {
    if (passwordSsid === "" && popupOpen) {
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
    } else if (selectedIndex >= wifiNetworks.length) {
      selectedIndex = wifiNetworks.length - 1
    } else if (selectedIndex < 0 && popupOpen) {
      selectedIndex = 0
    }
  }

  function selectByDelta(delta) {
    if (wifiNetworks.length === 0) { selectedIndex = -1; return }
    if (selectedIndex < 0) selectedIndex = delta > 0 ? 0 : wifiNetworks.length - 1
    else selectedIndex = (selectedIndex + delta + wifiNetworks.length) % wifiNetworks.length
  }

  // Enter/Space on the highlighted row. Mirrors row-click semantics:
  // connected → disconnect, protected-unknown → password prompt (via
  // known-network probe), open/known → connect.
  function activateSelected() {
    if (busy || selectedIndex < 0 || selectedIndex >= wifiNetworks.length) return
    var net = wifiNetworks[selectedIndex]
    if (!net) return
    if (net.connected) { disconnect(net.ssid); return }
    if (isProtected(net.security)) {
      var quotedSsid = bar.shellQuote(net.ssid)
      knownCheck.targetSsid = net.ssid
      knownCheck.command = ["bash", "-c", `
iwctl known-networks list 2>/dev/null \\
  | sed -e 's/\\x1b\\[[0-9;]*m//g' \\
  | awk -v s=${quotedSsid} 'NR > 3 {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      n = split(line, p, /[[:space:]]{2,}/)
      if (n >= 1 && p[1] == s) { print "yes"; exit }
    }'`]
      knownCheck.running = true
      return
    }
    connectKnown(net.ssid)
  }

  // 'x' on the highlighted row. Only meaningful on the currently-connected
  // network — forget is a no-op (and the X icon is hidden) otherwise.
  function forgetSelected() {
    if (busy || selectedIndex < 0 || selectedIndex >= wifiNetworks.length) return
    var net = wifiNetworks[selectedIndex]
    if (net && net.connected) forget(net.ssid)
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

  function networkTooltip() {
    if (kind === "wifi") {
      var f = parseFloat(frequency)
      var ftext = f > 0 ? " (" + (f / 1000).toFixed(1) + " GHz)" : ""
      return (label || "Wi-Fi") + ftext
    }
    if (kind === "ethernet") return "Connected"
    return "Disconnected"
  }

  function networkCommand() {
    return [
      "device=$(ip route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == \"dev\") { print $(i + 1); exit } }')",
      "if [[ -z $device ]]; then",
      "  printf 'disconnected\\t\\t\\t\\n'",
      "  exit 0",
      "fi",
      "if [[ ! -d /sys/class/net/$device/wireless ]]; then",
      "  printf 'ethernet\\t%s\\t\\t\\n' \"$device\"",
      "  exit 0",
      "fi",
      "show=$(iwctl station \"$device\" show 2>/dev/null | sed -e 's/\\x1b\\[[0-9;]*m//g')",
      "state=$(awk '/^[[:space:]]*State[[:space:]]/ { sub(/.*State[[:space:]]+/, \"\"); sub(/[[:space:]]+$/, \"\"); print; exit }' <<<\"$show\")",
      "ssid=$(awk '/^[[:space:]]*Connected network[[:space:]]/ { sub(/.*Connected network[[:space:]]+/, \"\"); sub(/[[:space:]]+$/, \"\"); print; exit }' <<<\"$show\")",
      "freq=$(awk '/^[[:space:]]*Frequency[[:space:]]/ { sub(/.*Frequency[[:space:]]+/, \"\"); sub(/[[:space:]]+$/, \"\"); print; exit }' <<<\"$show\")",
      "rssi=$(awk '/^[[:space:]]*RSSI[[:space:]]/ { sub(/.*RSSI[[:space:]]+/, \"\"); sub(/[[:space:]]+$/, \"\"); print; exit }' <<<\"$show\")",
      "dbm=${rssi%% *}",
      "signal=\"\"",
      "if [[ -n $dbm ]]; then",
      "  if (( dbm >= -50 )); then signal=100",
      "  elif (( dbm <= -100 )); then signal=0",
      "  else signal=$(( 2 * (dbm + 100) )); fi",
      "fi",
      "if [[ -n $state && $state != connected ]]; then",
      "  printf 'disconnected\\t\\t\\t\\n'",
      "  exit 0",
      "fi",
      "printf 'wifi\\t%s\\t%s\\t%s\\n' \"${ssid:-$device}\" \"$signal\" \"$freq\""
    ].join("\n")
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

  function refresh() {
    if (!detailsProc.running) detailsProc.running = true
    if (!dnsProc.running) {
      dnsProc.command = ["bash", "-lc", root.dnsCommand("")]
      dnsProc.running = true
    }
    if (!wifiProc.running) {
      scanning = true
      wifiProc.running = true
    }
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
  }

  function updateWifi(raw) {
    var lines = String(raw || "").split("\n")
    var hasStation = false
    var nets = []
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      if (line === "STATION_AVAILABLE") { hasStation = true; continue }
      // Format: connected<TAB>ssid<TAB>signal<TAB>security
      var parts = line.split("\t")
      if (parts.length < 3) continue
      nets.push({
        connected: parts[0] === "1",
        ssid: parts[1],
        signal: parseInt(parts[2], 10) || 0,
        security: parts[3] || ""
      })
    }
    nets.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      return b.signal - a.signal
    })
    wifiNetworks = nets
    wifiStationAvailable = hasStation
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
    var command = root.bar ? root.bar.shellQuote(root.bar.omarchyPath + "/bin/omarchy-dns") : "omarchy-dns"
    if (provider) command += " " + root.bar.shellQuote(provider)
    return command
  }

  function setDns(provider) {
    if (!root.bar || !provider || actionProc.running) return

    if (provider === "Custom") {
      var launcher = root.bar.shellQuote(root.bar.omarchyPath + "/bin/omarchy-launch-floating-terminal-with-presentation")
      root.bar.run(launcher + " " + root.bar.shellQuote(root.dnsCommand(provider)))
      root.closePopout()
      return
    }

    root.pendingDnsProvider = provider
    actionProc.command = ["bash", "-lc", root.dnsCommand(provider)]
    actionProc.running = true
    root.closePopout()
  }

  function isProtected(security) {
    var s = String(security || "").toLowerCase()
    return s !== "" && s !== "open"
  }

  function runAction(kind, ssid, command) {
    if (actionProc.running) return
    actionSsid = ssid
    actionKind = kind
    failureSsid = ""
    failureReason = ""
    actionProc.command = ["bash", "-c", command]
    actionProc.running = true
    // Safety net: if onExited never fires (process death, signal handler
    // throws, etc.), clear the busy state so the row doesn't get stuck on
    // "Connecting…" / "Disconnecting…" forever.
    actionTimeout.restart()
  }

  function connectKnown(ssid) {
    var quotedSsid = bar.shellQuote(ssid)
    runAction("connect", ssid, `
station=$(iwctl station list 2>/dev/null | sed -e 's/\\x1b\\[[0-9;]*m//g' | awk '/^[[:space:]]*wl/ { print $1; exit }')
[[ -z $station ]] && { echo "no Wi-Fi station available" >&2; exit 1; }
iwctl --dont-ask station "$station" connect ${quotedSsid}
`)
  }

  function connectWithPassphrase(ssid, passphrase) {
    var quotedSsid = bar.shellQuote(ssid)
    var quotedPass = bar.shellQuote(passphrase)
    runAction("connect", ssid, `
station=$(iwctl station list 2>/dev/null | sed -e 's/\\x1b\\[[0-9;]*m//g' | awk '/^[[:space:]]*wl/ { print $1; exit }')
[[ -z $station ]] && { echo "no Wi-Fi station available" >&2; exit 1; }
iwctl --passphrase ${quotedPass} station "$station" connect ${quotedSsid}
`)
  }

  function disconnect(ssid) {
    runAction("disconnect", ssid, `
station=$(iwctl station list 2>/dev/null | sed -e 's/\\x1b\\[[0-9;]*m//g' | awk '/^[[:space:]]*wl/ { print $1; exit }')
[[ -z $station ]] && { echo "no Wi-Fi station available" >&2; exit 1; }
iwctl station "$station" disconnect
`)
  }

  // iwd doesn't reliably tear down an active connection when you forget the
  // network underneath it, so if the station is currently on this SSID we
  // disconnect first and bail on failure rather than reporting a misleading
  // success. If the station isn't on this SSID (or there is no station),
  // skip straight to forget.
  function forget(ssid) {
    var quotedSsid = bar.shellQuote(ssid)
    runAction("forget", ssid, `
station=$(iwctl station list 2>/dev/null | sed -e 's/\\x1b\\[[0-9;]*m//g' | awk '/^[[:space:]]*wl/ { print $1; exit }')
if [[ -n $station ]]; then
  current=$(iwctl station "$station" show 2>/dev/null \
    | sed -e 's/\\x1b\\[[0-9;]*m//g' \
    | awk '/Connected network/ {
        s = $0
        sub(/.*Connected network[[:space:]]+/, "", s)
        sub(/[[:space:]]+$/, "", s)
        print s
        exit
      }')
  if [[ $current == ${quotedSsid} ]]; then
    iwctl station "$station" disconnect || { echo "failed to disconnect before forget" >&2; exit 1; }
  fi
fi
iwctl known-networks ${quotedSsid} forget
`)
  }

  function launchImpala() {
    if (!bar) return
    var quotedPath = bar.shellQuote(bar.omarchyPath)
    var quotedBin = bar.shellQuote(bar.omarchyPath + "/bin/omarchy-launch-wifi")
    var quotedFullPath = bar.shellQuote(bar.omarchyPath + "/bin:" + (Quickshell.env("PATH") || ""))
    bar.run("OMARCHY_PATH=" + quotedPath + " PATH=" + quotedFullPath + " " + quotedBin)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  // Lets a Hyprland keybind summon the panel without needing to click the
  // bar icon. Paired with the SUPER+CTRL+W binding in utilities.lua.
  IpcHandler {
    target: "networkPanel"
    function toggle(): void {
      if (root.popupOpen) root.closePopout()
      else root.popupOpen = true
    }
    function show(): void { if (!root.popupOpen) root.popupOpen = true }
    function hide(): void { root.closePopout() }
  }

  // Pulls everything we want about the active route's interface in one shot.
  Process {
    id: detailsProc
    command: ["bash", "-c", `
route_json=$(ip -j route get 1.1.1.1 2>/dev/null)
[[ -z $route_json ]] && exit 0
iface=$(echo "$route_json" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0].get("dev",""))' 2>/dev/null)
gw=$(echo "$route_json" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0].get("gateway",""))' 2>/dev/null)
src=$(echo "$route_json" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0].get("prefsrc",""))' 2>/dev/null)
[[ -z $iface ]] && exit 0
prefix=$(ip -j addr show "$iface" 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); ai=d[0].get("addr_info",[]); print(next((str(a.get("prefixlen","")) for a in ai if a.get("family")=="inet"),""))' 2>/dev/null)
printf 'iface\\t%s\\n' "$iface"
printf 'ip\\t%s\\n' "$src"
printf 'prefix\\t%s\\n' "$prefix"
printf 'gateway\\t%s\\n' "$gw"
if [[ -d /sys/class/net/$iface/wireless ]]; then
  printf 'type\\twifi\\n'
  if command -v iw >/dev/null; then
    link=$(iw dev "$iface" link 2>/dev/null)
    [[ -n $link ]] && {
      printf 'ssid\\t%s\\n' "$(echo "$link" | awk '/SSID:/ { sub(/.*SSID: /, ""); print; exit }')"
      printf 'signal_dbm\\t%s\\n' "$(echo "$link" | awk '/signal:/ { print $2; exit }')"
      printf 'freq\\t%s\\n' "$(echo "$link" | awk '/freq:/ { print $2; exit }')"
      printf 'bitrate\\t%s %s\\n' "$(echo "$link" | awk '/tx bitrate:/ { print $3; exit }')" "$(echo "$link" | awk '/tx bitrate:/ { print $4; exit }')"
    }
  fi
else
  printf 'type\\tethernet\\n'
  [[ -r /sys/class/net/$iface/speed ]] && printf 'speed\\t%s\\n' "$(cat /sys/class/net/$iface/speed)"
  [[ -r /sys/class/net/$iface/duplex ]] && printf 'duplex\\t%s\\n' "$(cat /sys/class/net/$iface/duplex)"
fi
`]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateDetails(text)
    }
  }

  // Wi-Fi scan via iwctl. Emits a STATION_AVAILABLE marker followed by TSV
  // rows (connected, ssid, signal_pct, security). Strip ANSI escapes early —
  // iwctl's table layout starts each row with one, which breaks naive parsing.
  Process {
    id: wifiProc
    command: ["bash", "-c", `
station=$(iwctl station list 2>/dev/null | sed -e 's/\\x1b\\[[0-9;]*m//g' | awk '/^[[:space:]]*wl/ { print $1; exit }')
[[ -z $station ]] && exit 0
echo STATION_AVAILABLE
iwctl station "$station" get-networks rssi-dbms 2>/dev/null \\
  | sed -e 's/\\x1b\\[[0-9;]*m//g' \\
  | awk '
      NR <= 4 { next }
      /^[[:space:]]*$/ { next }
      {
        connected = (substr($0, 1, 4) ~ />/) ? 1 : 0
        line = $0
        sub(/^[[:space:]]*>?[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        n = split(line, parts, /[[:space:]]{2,}/)
        if (n < 3) next
        ssid = parts[1]
        security = parts[n-1]
        dbm = parts[n] / 100
        signal = (dbm >= -50) ? 100 : (dbm <= -100) ? 0 : int(2 * (dbm + 100))
        printf "%d\\t%s\\t%d\\t%s\\n", connected, ssid, signal, security
      }'
`]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateWifi(text)
    }
  }

  Process {
    id: dnsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateDns(text)
    }
  }

  // Action runner for connect/disconnect/forget and DNS provider changes.
  // Streams stderr for wifi actions so we can surface "Operation failed" or
  // "Invalid passphrase" inline rather than dropping the user back to a
  // silent UI. setDns() and runAction() both gate on `actionProc.running`,
  // so the two flows can't overlap on this shared process.
  Process {
    id: actionProc
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      // DNS change finished — pendingDnsProvider is the in-flight marker
      // for that flow (setDns doesn't touch actionKind), so handle it and
      // return before the wifi-action path.
      if (root.pendingDnsProvider !== "") {
        if (exitCode === 0) root.dnsProvider = root.pendingDnsProvider
        root.pendingDnsProvider = ""
        return
      }
      // Timeout already cleared our state and killed us — the exit signal
      // is stale, don't clobber whatever the user has done since.
      if (root.actionKind === "") return
      actionTimeout.stop()
      var ssid = root.actionSsid
      var kind = root.actionKind
      if (exitCode === 0) {
        if (kind === "connect") root.passwordSsid = ""
        root.failureSsid = ""
        root.failureReason = ""
      } else {
        root.failureSsid = ssid
        var reason = (actionStderr.text || actionStdout.text || "").trim()
        if (!reason) {
          if (kind === "connect") reason = "Failed to connect"
          else if (kind === "disconnect") reason = "Failed to disconnect"
          else reason = "Failed to forget"
        }
        // Squash multi-line iwctl errors into a single readable line.
        root.failureReason = reason.split("\n").pop()
      }
      root.actionSsid = ""
      root.actionKind = ""
      root.refresh()
    }
  }

  // Poll detailsProc while the panel is open. `iwctl connect` returns
  // success the moment iwd accepts credentials — the IP/route isn't
  // actually assigned until a beat later, so a single post-action refresh
  // races against routing and the header stays blank. Polling fills the
  // details in as soon as the route comes up; cheap since the script is
  // small and only runs while the panel is visible.
  Timer {
    id: detailsPoll
    interval: 1500
    repeat: true
    running: root.popupOpen
    onTriggered: if (!detailsProc.running) detailsProc.running = true
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
      // Clear state *before* killing the process so the eventual onExited
      // sees actionKind === "" and bails out as stale.
      root.failureSsid = root.actionSsid
      root.failureReason = reason
      root.actionSsid = ""
      root.actionKind = ""
      if (actionProc.running) actionProc.running = false  // SIGTERM
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
      if (b === Qt.RightButton) root.launchImpala()
      else if (root.popupOpen) root.closePopout()
      else { root.popupOpen = true; root.refresh() }
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
    open: root.popupOpen
    contentWidth: 340
    contentHeight: column.implicitHeight + 28

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
        if (dy !== 0) {
          if (root.focusSection === "dns") {
            // j from DNS drops into the wifi list if there's anywhere to
            // land; otherwise hold position so j isn't a no-op surprise.
            if (dy > 0 && root.wifiNetworks.length > 0) {
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
        if (dx !== 0 && root.focusSection === "dns") root.selectDnsByDelta(dx)
      }
      onActivateRequested: {
        if (root.focusSection === "dns") root.activateDns()
        else root.activateSelected()
      }
      onCloseRequested: root.closePopout()
      onDeleteRequested: {
        if (root.focusSection === "wifi") root.forgetSelected()
      }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
      }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: 12

      // Header — interface name + type, refresh on the right.
      Item {
        width: parent.width
        height: Math.max(headerInfo.implicitHeight, refreshBtn.implicitHeight)

        Row {
          id: headerInfo
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: 10

          Text {
            text: root.icon
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter

            Text {
              text: root.info.iface || (root.kind === "disconnected" ? "Disconnected" : "No connection")
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: {
                if (root.info.type === "wifi") {
                  var s = root.info.ssid || "Wi-Fi"
                  if (root.info.freq) s += "  ·  " + root.formatFreq(root.info.freq)
                  return s
                }
                if (root.info.type === "ethernet") return "Ethernet"
                return ""
              }
              visible: text !== ""
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Button {
          id: refreshBtn
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰑐"
          tooltipText: "Refresh"
          tooltipBackground: root.bar.background
          tooltipForeground: root.bar.foreground
          foreground: root.bar.foreground
          horizontalPadding: 8
          verticalPadding: 4
          iconSize: 14
          active: root.scanning
          onClicked: root.refresh()
        }
      }

      PanelSeparator {
        visible: !!root.info.iface
        foreground: root.bar.foreground
      }

      // Connection details: IP, gateway, link speed, etc.
      Grid {
        visible: !!root.info.iface
        width: parent.width
        columns: 2
        columnSpacing: 14
        rowSpacing: 4

        // IP address.
        Text {
          visible: !!root.info.ip
          text: "IP address"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          visible: !!root.info.ip
          text: (root.info.ip || "") + (root.info.prefix ? "/" + root.info.prefix : "")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // Gateway.
        Text {
          visible: !!root.info.gateway
          text: "Gateway"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          visible: !!root.info.gateway
          text: root.info.gateway || ""
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // Ethernet link speed / duplex.
        Text {
          visible: root.info.type === "ethernet" && !!root.info.speed
          text: "Link"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          visible: root.info.type === "ethernet" && !!root.info.speed
          text: root.formatSpeed(root.info.speed || "") + (root.info.duplex ? "  ·  " + root.info.duplex + " duplex" : "")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // Wi-Fi signal.
        Text {
          visible: root.info.type === "wifi" && !!root.info.signal_dbm
          text: "Signal"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          visible: root.info.type === "wifi" && !!root.info.signal_dbm
          text: (root.info.signal_dbm || "") + " dBm"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // Wi-Fi tx bitrate.
        Text {
          visible: root.info.type === "wifi" && !!root.info.bitrate
          text: "Link rate"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          visible: root.info.type === "wifi" && !!root.info.bitrate
          text: root.info.bitrate || ""
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      // DNS provider selection.
      PanelSeparator {
        foreground: root.bar.foreground
      }

      Column {
        width: parent.width
        spacing: 8

        PanelSectionHeader {
          text: "DNS provider"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Row {
          width: parent.width
          spacing: 6

          DnsProviderPill {
            provider: "DHCP"
            index: 0
            tooltipText: "Use DNS from DHCP"
            onClicked: root.setDns(provider)
          }

          DnsProviderPill {
            provider: "Cloudflare"
            index: 1
            tooltipText: "Set DNS to Cloudflare"
            onClicked: root.setDns(provider)
          }

          DnsProviderPill {
            provider: "Google"
            index: 2
            tooltipText: "Set DNS to Google"
            onClicked: root.setDns(provider)
          }

          DnsProviderPill {
            provider: "Custom"
            index: 3
            tooltipText: "Set custom DNS servers"
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
        text: root.scanning ? "Scanning Wi-Fi…" : "Wi-Fi networks"
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
        height: Math.min(contentHeight, 240)
        spacing: 4
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
    foreground: root.bar.foreground
    tooltipBackground: root.bar.background
    tooltipForeground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: 10
    verticalPadding: 6

    // Map the panel's domain semantics onto Button's structural props:
    // `current DNS` is the pill's `active` fill; the keyboard cursor lights
    // up `hasCursor`.
    active: root.dnsProvider === provider
    hasCursor: root.focusSection === "dns" && root.dnsIndex === index

    onHovered: function(isHovered) {
      if (!isHovered) return
      root.focusSection = "dns"
      root.dnsIndex = pill.index
    }
  }

  // A single Wi-Fi network entry. Collapses to a one-line pill normally;
  // expands inline to a passphrase prompt when the user picks a protected
  // network we don't have credentials for. Clicking a connected row
  // disconnects; the X button on a connected row forgets the network.
  component NetworkRow: CursorSurface {
    id: row
    required property var net
    required property int index

    readonly property bool isConnected: net && net.connected
    readonly property bool isProtected: root.isProtected(net ? net.security : "")
    readonly property bool isSelected: root.focusSection === "wifi" && root.selectedIndex === index

    hasCursor: isSelected
    current: isConnected
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    // Gate on the matching *Kind/*Reason being non-empty so a hidden-SSID
    // row (ssid == "") doesn't match the "" defaults of actionSsid etc.
    readonly property bool isBusy: root.actionKind !== "" && root.actionSsid === (net ? net.ssid : "")
    readonly property bool isFailed: root.failureReason !== "" && root.failureSsid === (net ? net.ssid : "")
    readonly property bool isPasswordOpen: root.passwordSsid !== "" && root.passwordSsid === (net ? net.ssid : "")

    readonly property string statusText: {
      if (!net) return ""
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

    implicitHeight: rowBody.implicitHeight + (isPasswordOpen ? passwordPanel.implicitHeight + 6 : 0)

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
      onContainsMouseChanged: if (containsMouse) { root.focusSection = "wifi"; root.selectedIndex = row.index }

      onClicked: {
        if (!row.net) return
        // Resync cursor in case keyboard nav moved it away while the mouse
        // stayed parked on this row — the click target is unambiguously here.
        root.focusSection = "wifi"
        root.selectedIndex = row.index
        if (row.isConnected) {
          root.disconnect(row.net.ssid)
          return
        }
        if (row.isProtected) {
          // Known protected network: iwd has the passphrase, just connect.
          // Otherwise expand the inline password prompt for this row. Stash
          // the SSID as a string — if we held a reference to the row
          // delegate it could be destroyed by a model refresh, and a rapid
          // second click would overwrite it and misroute the first result.
          var quotedSsid = root.bar.shellQuote(row.net.ssid)
          knownCheck.targetSsid = row.net.ssid
          knownCheck.command = ["bash", "-c", `
iwctl known-networks list 2>/dev/null \\
  | sed -e 's/\\x1b\\[[0-9;]*m//g' \\
  | awk -v s=${quotedSsid} 'NR > 3 {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      n = split(line, p, /[[:space:]]{2,}/)
      if (n >= 1 && p[1] == s) { print "yes"; exit }
    }'`]
          knownCheck.running = true
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
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      implicitHeight: Math.max(networkIcon.implicitHeight, networkInfo.implicitHeight, forgetBtn.implicitHeight) + 12

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
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: row.isConnected
        enabled: !root.busy
        iconText: "󰅙"
        tooltipText: "Forget network"
        foreground: root.bar.foreground
        hoverColor: root.bar.urgent
        panelBackground: root.bar.background
        fontFamily: root.bar.fontFamily
        onClicked: if (row.net) root.forget(row.net.ssid)
      }

      // Shows a lock glyph on the right for protected networks that
      // aren't currently connected. Once connected, the forget X takes
      // its place (and 'protected' is implied by the fact we're on it).
      // Same 22-wide right-anchored centered geometry as forgetBtn so the
      // glyph centers line up across rows.
      Text {
        id: lockIndicator
        visible: row.isProtected && !row.isConnected
        width: 22
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
        spacing: 1
        anchors.left: networkIcon.right
        anchors.leftMargin: 10
        anchors.right: forgetBtn.visible ? forgetBtn.left
                      : lockIndicator.visible ? lockIndicator.left
                      : parent.right
        anchors.rightMargin: (forgetBtn.visible || lockIndicator.visible) ? 8 : 0
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
          // Signal strength is conveyed by the wifi-bars icon and a lock
          // glyph on the right denotes protected networks, so the second
          // line only carries action status (Connecting…, Connected,
          // Failed, etc.). Collapses to zero height when empty so rows
          // without status keep a tight one-line look.
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

    // Inline passphrase prompt — only shown when we hit a protected network
    // we don't have saved credentials for. Submitting (Enter or the check
    // button) fires connect; Esc cancels back to the row.
    Item {
      id: passwordPanel
      visible: row.isPasswordOpen
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: rowMouse.bottom
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      anchors.topMargin: 4
      implicitHeight: pwField.implicitHeight + 8

      TextField {
        id: pwField
        anchors.left: parent.left
        anchors.right: connectPwBtn.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: 6
        password: true
        placeholderText: "Passphrase"
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        foreground: root.bar.foreground
        horizontalPadding: 8
        verticalPadding: 6
        enabled: !row.isBusy

        onAccepted: {
          if (!root.busy && row.net && text.length > 0) root.connectWithPassphrase(row.net.ssid, text)
        }
        Keys.onEscapePressed: { root.passwordSsid = ""; text = "" }

        onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
        Component.onCompleted: if (visible) Qt.callLater(forceActiveFocus)
      }

      // 22×22 right-anchored to line up with forgetBtn and lockIndicator
      // above. Esc closes the prompt (handled by pwField.Keys.onEscapePressed)
      // so there's no separate cancel button.
      PanelActionButton {
        id: connectPwBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        enabled: !root.busy && row.net && pwField.text.length > 0
        iconText: "󰄬"
        tooltipText: "Connect"
        foreground: root.bar.foreground
        panelBackground: root.bar.background
        fontFamily: root.bar.fontFamily
        onClicked: if (row.net) root.connectWithPassphrase(row.net.ssid, pwField.text)
      }
    }
  }

  // One-shot probe: is the just-clicked SSID in iwd's known-networks?
  // If so, skip the passphrase prompt and connect directly. We hold an SSID
  // string (not a row delegate) so a model refresh during the probe can't
  // leave us pointing at a destroyed object. Rows are globally disabled
  // while `knownCheck.running`, so the SSID can't be overwritten mid-flight.
  Process {
    id: knownCheck
    property string targetSsid: ""
    stdout: StdioCollector {
      id: knownStdout
      waitForEnd: true
      onStreamFinished: {
        var ssid = knownCheck.targetSsid
        knownCheck.targetSsid = ""
        if (!ssid) return
        if (text.indexOf("yes") !== -1) root.connectKnown(ssid)
        else root.passwordSsid = ssid
      }
    }
  }

  // Poll the wifi/ethernet pill state every 3s. Local to this panel so
  // Bar.qml does not need to mirror network state.
  Process {
    id: networkProc
    command: ["bash", "-lc", root.bar ? root.bar.commandWithOmarchyPath(root.networkCommand()) : ""]
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
}
