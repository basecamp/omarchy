import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "networkPanel"
  property var settings: ({})

  property bool popupOpen: false
  function closePopout() { popupOpen = false }

  // Live connection details from `ip` / /sys / iw.
  property var info: ({})  // { iface, type, ip, prefix, gateway, speed, duplex, ssid, signal, freq, bitrate }
  property var wifiNetworks: []
  property bool scanning: false
  property bool wifiStationAvailable: false
  property string dnsProvider: ""
  property string pendingDnsProvider: ""

  readonly property string kind: bar ? bar.networkKind : "disconnected"
  readonly property string label: bar ? bar.networkLabel : ""
  readonly property int signalStrength: bar ? bar.networkSignal : -1

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
    if (!dnsProc.running) dnsProc.running = true
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
    return "pkexec " + root.bar.shellQuote(root.bar.omarchyPath + "/bin/omarchy-setup-dns") + " " + root.bar.shellQuote(provider)
  }

  function setDns(provider) {
    if (!root.bar || !provider || actionProc.running) return

    if (provider === "Custom") {
      var launcher = root.bar.shellQuote(root.bar.omarchyPath + "/bin/omarchy-launch-floating-terminal-with-presentation")
      root.bar.run(launcher + " " + root.bar.shellQuote(root.dnsCommand(provider)))
      root.popupOpen = false
      return
    }

    root.pendingDnsProvider = provider
    actionProc.command = ["bash", "-lc", root.dnsCommand(provider)]
    actionProc.running = true
    root.popupOpen = false
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

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
    command: ["bash", "-c", `
dns=$(awk -F= '/^[[:space:]]*DNS[[:space:]]*=/ { value=$0; sub(/^[^=]*=/, "", value); print value; exit }' /etc/systemd/resolved.conf 2>/dev/null)
compact=$(printf '%s' "$dns" | tr -d '[:space:]')
if [[ -z $compact ]]; then
  echo DHCP
elif [[ $dns == *cloudflare-dns.com* || $dns == *"1.1.1.1"* || $dns == *"2606:4700:4700::1111"* ]]; then
  echo Cloudflare
elif [[ $dns == *dns.google* || $dns == *"8.8.8.8"* || $dns == *"2001:4860:4860::8888"* ]]; then
  echo Google
else
  echo Custom
fi
`]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateDns(text)
    }
  }

  Process {
    id: actionProc
    onExited: function(exitCode) {
      if (root.pendingDnsProvider !== "") {
        if (exitCode === 0) root.dnsProvider = root.pendingDnsProvider
        root.pendingDnsProvider = ""
      }
    }
  }

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    horizontalMargin: 8.5
    rightExtraMargin: 2
    tooltipText: bar ? bar.networkTooltip() : ""

    onPressed: function(b) {
      if (b === Qt.RightButton) root.bar.run(root.bar.omarchyPath + "/bin/omarchy-launch-wifi")
      else {
        root.popupOpen = !root.popupOpen
        if (root.popupOpen) root.refresh()
      }
    }
  }

  Common.PopupCard {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: 340
    contentHeight: column.implicitHeight + 28

    Column {
      id: column
      anchors.fill: parent
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
            font.pixelSize: 22
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter

            Text {
              text: root.info.iface || (root.kind === "disconnected" ? "Disconnected" : "No connection")
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: 13
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
              font.pixelSize: 10
            }
          }
        }

        Common.PillButton {
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

      Rectangle {
        visible: !!root.info.iface
        width: parent.width
        height: 1
        color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
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
          font.pixelSize: 11
        }
        Text {
          visible: !!root.info.ip
          text: (root.info.ip || "") + (root.info.prefix ? "/" + root.info.prefix : "")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }

        // Gateway.
        Text {
          visible: !!root.info.gateway
          text: "Gateway"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }
        Text {
          visible: !!root.info.gateway
          text: root.info.gateway || ""
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }

        // Ethernet link speed / duplex.
        Text {
          visible: root.info.type === "ethernet" && !!root.info.speed
          text: "Link"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }
        Text {
          visible: root.info.type === "ethernet" && !!root.info.speed
          text: root.formatSpeed(root.info.speed || "") + (root.info.duplex ? "  ·  " + root.info.duplex + " duplex" : "")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }

        // Wi-Fi signal.
        Text {
          visible: root.info.type === "wifi" && !!root.info.signal_dbm
          text: "Signal"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }
        Text {
          visible: root.info.type === "wifi" && !!root.info.signal_dbm
          text: (root.info.signal_dbm || "") + " dBm"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }

        // Wi-Fi tx bitrate.
        Text {
          visible: root.info.type === "wifi" && !!root.info.bitrate
          text: "Link rate"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }
        Text {
          visible: root.info.type === "wifi" && !!root.info.bitrate
          text: root.info.bitrate || ""
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }
      }

      // DNS provider selection.
      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
      }

      Column {
        width: parent.width
        spacing: 8

        Text {
          text: "DNS provider"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: 10
          font.bold: true
        }

        Row {
          width: parent.width
          spacing: 6

          Common.PillButton {
            text: "DHCP"
            tooltipText: "Use DNS from DHCP"
            tooltipBackground: root.bar.background
            tooltipForeground: root.bar.foreground
            foreground: root.bar.foreground
            horizontalPadding: 10
            verticalPadding: 6
            active: root.dnsProvider === "DHCP"
            onClicked: root.setDns("DHCP")
          }

          Common.PillButton {
            text: "Cloudflare"
            tooltipText: "Set DNS to Cloudflare"
            tooltipBackground: root.bar.background
            tooltipForeground: root.bar.foreground
            foreground: root.bar.foreground
            horizontalPadding: 10
            verticalPadding: 6
            active: root.dnsProvider === "Cloudflare"
            onClicked: root.setDns("Cloudflare")
          }

          Common.PillButton {
            text: "Google"
            tooltipText: "Set DNS to Google"
            tooltipBackground: root.bar.background
            tooltipForeground: root.bar.foreground
            foreground: root.bar.foreground
            horizontalPadding: 10
            verticalPadding: 6
            active: root.dnsProvider === "Google"
            onClicked: root.setDns("Google")
          }

          Common.PillButton {
            text: "Custom"
            tooltipText: "Set custom DNS servers"
            tooltipBackground: root.bar.background
            tooltipForeground: root.bar.foreground
            foreground: root.bar.foreground
            horizontalPadding: 10
            verticalPadding: 6
            active: root.dnsProvider === "Custom"
            onClicked: root.setDns("Custom")
          }
        }
      }

      // Wi-Fi networks (only if a Wi-Fi station is available).
      Rectangle {
        visible: root.wifiStationAvailable
        width: parent.width
        height: 1
        color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
      }

      Text {
        visible: root.wifiStationAvailable
        text: root.scanning ? "Scanning Wi-Fi…" : "Wi-Fi networks"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: 10
        font.bold: true
      }

      // Scrollable network list — cap the height so a busy neighbourhood
      // doesn't push the popup off-screen. Bluetooth panel uses the same
      // pattern.
      Flickable {
        visible: root.wifiStationAvailable
        width: parent.width
        height: Math.min(networkList.implicitHeight, 240)
        contentWidth: width
        contentHeight: networkList.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: networkList
          width: parent.width
          spacing: 6

          Repeater {
            model: root.wifiStationAvailable ? root.wifiNetworks : []

            Common.PillButton {
              required property var modelData

              width: networkList.width
              leftAlign: true
              iconText: root.wifiIconFor(modelData.signal)
              text: (modelData.ssid || "Hidden") + (modelData.security ? "  ·  " + modelData.security : "")
              foreground: root.bar.foreground
              horizontalPadding: 10
              verticalPadding: 6
              active: modelData.connected

              onClicked: {
                if (modelData.connected) return
                if (actionProc.running) return
                // Known networks (and open networks) can connect non-interactively
                // via iwctl. Anything else needs Impala for passphrase entry.
                var ssid = root.bar.shellQuote(modelData.ssid)
                var security = root.bar.shellQuote(modelData.security || "")
                var omarchyPath = root.bar.omarchyPath
                actionProc.command = ["bash", "-c", `
ssid=${ssid}
security=${security}
station=$(iwctl station list 2>/dev/null | sed -e 's/\\x1b\\[[0-9;]*m//g' | awk '/^[[:space:]]*wl/ { print $1; exit }')
known=$(iwctl known-networks list 2>/dev/null | sed -e 's/\\x1b\\[[0-9;]*m//g' | awk -v s="$ssid" 'NR > 3 {
  line = $0
  sub(/^[[:space:]]+/, "", line)
  sub(/[[:space:]]+$/, "", line)
  n = split(line, p, /[[:space:]]{2,}/)
  if (n >= 1 && p[1] == s) { print "yes"; exit }
}')
if [[ -n $station && ( -n $known || $security == "open" ) ]]; then
  iwctl --dont-ask station "$station" connect "$ssid"
else
  ${omarchyPath}/bin/omarchy-launch-wifi
fi
`]
                actionProc.running = true
                root.popupOpen = false
              }
            }
          }
        }
      }

      Common.PillButton {
        visible: root.wifiStationAvailable
        width: parent.width
        iconText: "󰖩"
        text: "Open Wi-Fi manager (Impala)"
        foreground: root.bar.foreground
        horizontalPadding: 10
        verticalPadding: 6
        onClicked: { root.bar.run(root.bar.omarchyPath + "/bin/omarchy-launch-wifi"); root.popupOpen = false }
      }
    }
  }
}
