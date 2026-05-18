import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Ui

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "powerPanel"
  property var settings: ({})

  property bool popupOpen: false
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""

  function closePopout() { popupOpen = false }

  function batteryIcon() {
    var device = UPower.displayDevice
    if (!device || !device.isPresent) return ""

    var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
    var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    var index = Math.max(0, Math.min(9, Math.floor(device.percentage * 10)))

    if (device.state === UPowerDeviceState.FullyCharged) return "󰂅"
    if (!UPower.onBattery && device.state !== UPowerDeviceState.Charging) return ""
    if (device.state === UPowerDeviceState.Charging) return chargingIcons[index]
    return defaultIcons[index]
  }

  function modeLabel() { return UPower.onBattery ? "Battery" : "AC" }

  function refresh() {
    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
  }

  function updateKeyValue(raw, targetName) {
    var next = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var idx = lines[i].indexOf("\t")
      if (idx <= 0) continue
      next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
    }
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
  }

  function updateProfiles(raw) {
    var lines = String(raw || "").split("\n")
    var list = []
    var active = ""
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      list.push(parts[0])
      if (parts[1] === "1") active = parts[0]
    }
    profiles = list
    activeProfile = active
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["powerprofilesctl", "set", profile]
    actionProc.running = true
  }

  Component.onCompleted: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "powerPanel"
    function toggle(): void { root.popupOpen = !root.popupOpen }
    function show(): void { root.popupOpen = true }
    function hide(): void { root.closePopout() }
  }

  Process {
    id: batteryProc
    command: ["bash", "-lc", `
bat=$(upower -e 2>/dev/null | grep BAT | head -n1)
[[ -z $bat ]] && exit 0
info=$(upower -i "$bat")
printf 'percentage\t%s\n' "$(awk '/percentage/ { print int($2) "%"; exit }' <<<"$info")"
printf 'state\t%s\n' "$(awk '/state/ { print $2; exit }' <<<"$info")"
printf 'rate\t%s\n' "$(awk '/energy-rate/ { v=sprintf("%.1f", $2); sub(/\.0$/, "", v); print v "W"; exit }' <<<"$info")"
printf 'size\t%s\n' "$(awk '/energy-full:/ { printf "%dWh", $2; exit }' <<<"$info")"
printf 'time\t%s\n' "$($OMARCHY_PATH/bin/omarchy-battery-remaining-time 2>/dev/null)"
`]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  Process {
    id: profilesProc
    command: ["bash", "-lc", "powerprofilesctl list 2>/dev/null | awk '/^\\s*[* ]\\s*[a-zA-Z0-9-]+:$/ { active=($1==\"*\"); gsub(/^[*[:space:]]+|:$/,\"\"); print $0 \"\\t\" (active ? 1 : 0) }'"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: systemProc
    command: ["bash", "-lc", "cpu=$(top -bn1 | awk '/^%?Cpu/ { gsub(/,/, \"\"); for (i=1; i<=NF; i++) if ($(i+1) == \"id\") { printf \"%.0f%%\", 100 - $i; exit } }'); awk -v cpu=\"$cpu\" '/^MemTotal:/ { total=$2 } /^MemAvailable:/ { avail=$2 } END { used=total-avail; printf \"cpu\\t%s\\n\", cpu; printf \"memory\\t%.1fGB / %.0fGB\\n\", used/1024/1024, total/1024/1024 }' /proc/meminfo"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "system") }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.batteryIcon()
    horizontalMargin: 8.5
    active: UPower.displayDevice && UPower.displayDevice.percentage <= 0.2 && UPower.onBattery
    tooltipText: ""
    onPressed: function(b) { root.popupOpen = !root.popupOpen; if (root.popupOpen) root.refresh() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: 340
    contentHeight: column.implicitHeight + 28

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: 16

      Row {
        spacing: 10
        anchors.left: parent.left
        Text { id: acIcon; text: root.batteryIcon(); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: 22 }
        Text { text: root.modeLabel(); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: 13; font.bold: true; anchors.verticalCenter: acIcon.verticalCenter }
      }

      Row {
        visible: root.batteryInfo.percentage !== undefined
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 24

        Column {
          width: 140
          spacing: 4
          InfoPair { label: "Percentage"; value: root.batteryInfo.percentage || "" }
          InfoPair { label: "Battery size"; value: root.batteryInfo.size || "" }
        }

        Column {
          width: 140
          spacing: 4
          InfoPair { label: UPower.onBattery ? "Time left" : "Time to full"; value: root.batteryInfo.time || "—" }
          InfoPair { label: UPower.onBattery ? "Draw" : "Charge rate"; value: root.batteryInfo.rate || "" }
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      Column {
        width: parent.width
        spacing: 12
        PanelSectionHeader { text: "POWER PROFILE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
        Row {
          width: parent.width
          spacing: 6
          Repeater {
            model: root.profiles
            CursorPill {
              required property var modelData
              text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
              foreground: root.bar.foreground
              background: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.04)
              tooltipBackground: root.bar.background
              tooltipForeground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: 10
              verticalPadding: 6
              active: root.activeProfile === modelData
              onClicked: root.setProfile(modelData)
            }
          }
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      Column {
        width: parent.width
        spacing: 12
        PanelSectionHeader { text: "SYSTEM"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
        Grid {
          width: parent.width
          columns: 2
          columnSpacing: 14
          rowSpacing: 4
          InfoLabel { text: "CPU" } InfoValue { text: root.systemInfo.cpu || "—" }
          InfoLabel { text: "Mem" } InfoValue { text: root.systemInfo.memory || "—" }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: 8

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: 11
  }

  component InfoValue: Text {
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: 11
  }
}
