import QtQuick
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
  property var networks: []
  property bool scanning: false

  readonly property string kind: bar ? bar.networkKind : "disconnected"
  readonly property string label: bar ? bar.networkLabel : ""
  readonly property int signal: bar ? bar.networkSignal : -1

  readonly property string icon: {
    if (kind === "wifi") {
      var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
      var index = Math.max(0, Math.min(4, Math.ceil(signal / 20) - 1))
      return icons[index]
    }
    if (kind === "ethernet") return "󰀂"
    return "󰤮"
  }

  function refresh() {
    if (!scanProc.running) {
      scanning = true
      scanProc.running = true
    }
  }

  function updateScan(raw) {
    var list = []
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      if (parts.length < 3) continue
      list.push({
        inUse: parts[0] === "*",
        ssid: parts[1],
        signal: parseInt(parts[2], 10) || 0,
        security: parts[3] || ""
      })
    }
    list.sort(function(a, b) {
      if (a.inUse !== b.inUse) return a.inUse ? -1 : 1
      return b.signal - a.signal
    })
    networks = list
    scanning = false
  }

  function wifiIconFor(signal) {
    var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    var index = Math.max(0, Math.min(4, Math.ceil(signal / 20) - 1))
    return icons[index]
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  Process {
    id: scanProc
    command: ["bash", "-lc", "command -v nmcli >/dev/null && nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan no 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateScan(text)
    }
  }

  Process { id: actionProc }

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    horizontalMargin: 6.5
    tooltipText: bar ? bar.networkTooltip() : ""

    onPressed: function(b) {
      if (b === Qt.RightButton) root.bar.run("OMARCHY_PATH=" + root.bar.shellQuote(root.bar.omarchyPath) + " " + root.bar.omarchyPath + "/bin/omarchy-launch-wifi")
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
    contentWidth: 320
    contentHeight: column.implicitHeight + 28

    Column {
      id: column
      anchors.fill: parent
      spacing: 8

      Row {
        width: parent.width
        spacing: 8

        Text {
          text: root.icon
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 16
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          spacing: 2
          width: parent.width - 100
          anchors.verticalCenter: parent.verticalCenter

          Text {
            text: root.kind === "disconnected" ? "Disconnected" : (root.label || root.kind)
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: 12
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            visible: root.kind !== "disconnected"
            text: root.kind === "wifi" ? "Wi-Fi · " + root.signal + "%" : "Ethernet"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: 10
          }
        }

        Common.PillButton {
          iconText: ""
          foreground: root.bar.foreground
          horizontalPadding: 8
          verticalPadding: 4
          active: root.scanning
          onClicked: {
            scanProc.command = ["bash", "-lc", "command -v nmcli >/dev/null && nmcli device wifi rescan 2>/dev/null; nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan no 2>/dev/null"]
            root.refresh()
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.15)
      }

      Column {
        spacing: 2
        width: parent.width

        Repeater {
          model: root.networks.slice(0, 6)

          Common.PillButton {
            required property var modelData

            width: parent.width
            iconText: root.wifiIconFor(modelData.signal)
            text: (modelData.ssid || "Hidden") + (modelData.security ? "  ·  " : "") + (modelData.security || "")
            foreground: root.bar.foreground
            horizontalPadding: 10
            verticalPadding: 6
            active: modelData.inUse

            onClicked: {
              if (modelData.inUse) return
              actionProc.command = ["bash", "-lc", "command -v nmcli >/dev/null && nmcli device wifi connect " + root.bar.shellQuote(modelData.ssid)]
              actionProc.running = true
              root.popupOpen = false
            }
          }
        }

        Text {
          visible: root.networks.length === 0
          text: root.scanning ? "Scanning…" : "No networks found"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }
      }

      Common.PillButton {
        width: parent.width
        iconText: ""
        text: "Open Wi-Fi manager"
        foreground: root.bar.foreground
        horizontalPadding: 10
        verticalPadding: 6
        onClicked: { root.bar.run(root.bar.omarchyPath + "/bin/omarchy-launch-wifi"); root.popupOpen = false }
      }
    }
  }
}
