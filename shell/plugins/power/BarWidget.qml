import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "PowerModel.js" as PowerModel

Panel {
  id: root
  moduleName: "omarchy.power"
  ipcTarget: "omarchy.power"
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = PowerModel.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return PowerModel.batteryIcon(device, UPower.onBattery, upowerStates())
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return PowerModel.modeLabel(device, UPower.onBattery, upowerStates())
  }

  function profileIcon(name) {
    return PowerModel.profileIcon(name)
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return PowerModel.chargeThresholdActive(device, UPower.onBattery, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!UPower.onBattery && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return PowerModel.batteryFraction(d)
  }

  readonly property bool batteryLow: UPower.onBattery && batteryFraction > 0 && batteryFraction <= 0.2
  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && d.state === UPowerDeviceState.Charging && !root.chargeThresholdActive
  }

  readonly property color batteryFillColor: {
    if (batteryLow) return Color.urgent
    return root.bar ? root.bar.foreground : Color.foreground
  }

  // Cute agent-flavored phrases shown in the hero status line, rotated on a
  // timer so the panel feels alive when current is flowing (either direction).
  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]
  property int phraseIndex: 0

  // Whichever list is "active" given the current power state.
  readonly property var activePhrases: {
    if (fullyCharged) return []
    if (charging) return chargingPhrases
    if (UPower.onBattery || chargeThresholdActive) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: {
    if (fullyCharged) return "Fully charged"
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
  }

  function updateKeyValue(raw, targetName) {
    var next = PowerModel.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
  }

  function updateProfiles(raw) {
    var parsed = PowerModel.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
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
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
    }
  }

  onBatteryPresentChanged: if (!batteryPresent) close()

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

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

  // Rotate the status phrase while the panel is open and we're in a
  // rotating state (charging or on battery). The text swap is wrapped in a
  // fade so the changeover reads as one organism rather than a hard cut.
  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // If we leave a rotating state mid-swap, halt the animation and snap back
  // to full opacity so "FULLY CHARGED" is legible immediately rather than
  // appearing dimmed.
  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        heroStatus.opacity = 1.0
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.batteryIcon()
    horizontalMargin: 8.5
    rightExtraMargin: 2
    active: root.batteryPresent && UPower.displayDevice.percentage <= 0.2 && UPower.onBattery
    tooltipText: ""
    onPressed: function(b) { if (root.batteryPresent) root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
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
        spacing: Style.space(14)

        // ---------- Hero: battery icon · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            text: root.batteryIcon()
            color: root.batteryLow ? Color.urgent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Battery"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              text: root.heroStatusText.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            text: root.batteryInfo.percentage || "—"
            color: root.batteryLow ? Color.urgent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        // ---------- Battery progress bar ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryFillColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 220 } }

            // Subtle pulse while charging — visible signal that energy is flowing in.
            SequentialAnimation on opacity {
              running: root.charging && !root.fullyCharged && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: 950; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
            }
          }
        }

        // ---------- Stats ----------
        // Visibility is intentionally only gated by "we've ever loaded data" so
        // the section never collapses mid-transition. fullyCharged is *not* part
        // of the condition: UPower briefly reports FullyCharged on plug-in when
        // the battery sits above the charge-control start threshold, and we
        // refuse to flicker the whole panel for that ~1s window.
        Row {
          visible: root.batteryInfo.percentage !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "Battery size"; value: root.batteryInfo.size || "" }
            InfoPair { label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? "Charge limit" : (UPower.onBattery ? "Time left" : "Time to full")
              value: root.chargeThresholdActive ? (root.batteryInfo.threshold || "-") : (root.batteryFlowIdle ? "-" : (root.batteryInfo.time || "—"))
            }
            InfoPair {
              label: root.chargeThresholdActive ? "Battery state" : (UPower.onBattery ? "Discharging" : "Charging")
              value: root.chargeThresholdActive ? "Holding" : (root.batteryFull ? "-" : (root.batteryInfo.rate || ""))
            }
          }
        }

        // ---------- Power profile picker ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POWER PROFILE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
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
