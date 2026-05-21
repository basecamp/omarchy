import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "PowerPanel"
  ipcTarget: "panels.power"
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false

  function selectProfileByDelta(delta) {
    if (profiles.length === 0) { profileIndex = 0; return }
    profileIndex = Math.max(0, Math.min(profiles.length - 1, profileIndex + delta))
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

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

  function modeLabel() {
    var device = UPower.displayDevice
    var percentage = device && device.isPresent ? device.percentage : 0

    if (!UPower.onBattery && percentage >= 1) {
      return "Fully charged"
    } else if (UPower.onBattery) {
      return "Battery"
    } else {
      return "Charging"
    }
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged
  }

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
    if (profileIndex >= profiles.length) profileIndex = Math.max(0, profiles.length - 1)
    if (opened && activeProfile !== "") {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["powerprofilesctl", "set", profile]
    actionProc.running = true
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: batteryProc
    command: [root.bar ? root.bar.omarchyPath + "/bin/omarchy-battery-status" : "omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  Process {
    id: profilesProc
    command: [root.bar ? root.bar.omarchyPath + "/bin/omarchy-powerprofiles-list" : "omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: systemProc
    command: [root.bar ? root.bar.omarchyPath + "/bin/omarchy-system-stats" : "omarchy-system-stats"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "system") }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.batteryIcon()
    horizontalMargin: 8.5
    rightExtraMargin: 2
    active: UPower.displayDevice && UPower.displayDevice.percentage <= 0.2 && UPower.onBattery
    tooltipText: ""
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) root.selectProfileByDelta(dx)
        else if (dy !== 0) root.selectProfileByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(16)

      Item {
        width: parent.width
        implicitHeight: Style.space(28)

        Item {
          id: iconWrapper
          width: Style.space(28)
          height: Style.space(28)
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter

          Text {
            id: acIcon
            text: root.batteryIcon()
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.iconLarge
            anchors.centerIn: parent
          }
        }

        Text {
          text: root.modeLabel()
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          anchors.left: iconWrapper.right
          anchors.leftMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          visible: root.batteryInfo.percentage !== undefined
          text: root.batteryInfo.percentage || ""
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Row {
        visible: root.batteryInfo.percentage !== undefined && !root.fullyCharged
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(24)

        Column {
          width: Style.space(140)
          spacing: Style.spacing.labelGap
          InfoPair { label: "Battery size"; value: root.batteryInfo.size || "" }
          InfoPair { label: "Threshold"; value: root.batteryInfo.threshold || "—" }
        }

        Column {
          width: Style.space(140)
          spacing: Style.spacing.labelGap
          InfoPair { label: UPower.onBattery ? "Time left" : "Time to full"; value: root.batteryInfo.time || "—" }
          InfoPair { label: UPower.onBattery ? "Discharging" : "Charging"; value: root.batteryInfo.rate || "" }
        }
      }

      PanelSeparator {
        visible: !root.fullyCharged
        foreground: root.bar.foreground
      }

      Column {
        width: parent.width
        spacing: Style.space(12)
        PanelSectionHeader {
          visible: !root.fullyCharged
          text: "POWER PROFILE"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }
        Row {
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: root.profiles
            Button {
              required property var modelData
              required property int index
              text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              active: root.activeProfile === modelData
              hasCursor: root.cursorActive && root.profileIndex === index
              onClicked: root.setProfile(modelData)
              onHovered: function(h) {
                if (h) {
                  root.cursorActive = true
                  root.profileIndex = index
                }
              }
            }
          }
        }
      }
    }
  }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
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
