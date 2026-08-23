import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.pomodoro"
  ipcTarget: "omarchy.pomodoro"

  manageIpc: false

  IpcHandler {
    target: "omarchy.pomodoro"
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function start() { if (root.service) root.service.start() }
    function pause() { if (root.service) root.service.pause() }
    function reset() { root.stop() }
    function skip() { root.skip() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property var service: bar && bar.shell ? (bar.shell.serviceFor("omarchy.pomodoro")) : null

  onSettingsChanged: {
    if (root.service) root.service.settings = root.settings
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string phase: root.service ? root.service.phase : "focus"
  readonly property bool running: root.service ? root.service.running : false
  readonly property int remainingSecs: root.service ? root.service.remainingSecs : 0
  readonly property int totalSecs: root.service ? root.service.totalSecs : 0
  readonly property int completedSessions: root.service ? root.service.completedSessions : 0
  readonly property int customMinutes: root.service ? root.service.customMinutes : 10

  readonly property string phaseLabel: root.service ? root.service.phaseLabel : ""
  readonly property string timeText: root.service ? root.service.timeText : "00:00"
  readonly property real progress: root.service ? root.service.progress : 0
  readonly property bool alarming: root.service ? root.service.alarming : false

  function startPause() {
    if (!root.service) return
    if (root.running) root.service.pause()
    else root.service.start(0)
  }

  function stop() { if (root.service) root.service.reset() }
  function skip() { if (root.service) root.service.skip() }
  function setCustom(m) { if (root.service) root.service.setCustom(m) }

  function switchPhase(newPhase) {
    if (!root.service) return
    root.service.running = false
    root.service.phase = newPhase
    if (newPhase === "focus") root.service.totalSecs = root.service.focusSecs
    else if (newPhase === "shortBreak") root.service.totalSecs = root.service.shortBreakSecs
    else if (newPhase === "longBreak") root.service.totalSecs = root.service.longBreakSecs
    root.service.remainingSecs = root.service.totalSecs
  }

  // ---- bar slot ----------------------------------------------------------
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: {
      var icon = root.phase === "shortBreak" || root.phase === "longBreak" ? "󰒲" : "󰔟"
      if (root.bar && root.bar.vertical) return icon
      return root.running || root.remainingSecs !== root.totalSecs ? (icon + " " + root.timeText) : icon
    }
    tooltipText: root.phaseLabel
    active: root.running || root.alarming
    horizontalMargin: 7.5

    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
    }
  }

  // ---- dropdown panel ----------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: customField.field.activeFocus

      onActivateRequested: root.startPause()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "s" || t === "S") root.startPause()
        else if (t === "r" || t === "R") root.stop()
        else if (t === "n" || t === "N") root.skip()
        else if (t === "1") root.switchPhase("focus")
        else if (t === "2") root.switchPhase("shortBreak")
        else if (t === "3") root.switchPhase("longBreak")
        else if (t === "c" || t === "C") customField.field.forceActiveFocus()
      }

      ScrollView {
        id: scroll
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        Column {
          id: column
          width: parent.width
          spacing: Style.space(14)

          // Timer display
          Item {
            width: parent.width
            implicitHeight: heroCol.implicitHeight

            Column {
              id: heroCol
              width: parent.width
              spacing: Style.space(4)

              Text {
                width: parent.width
                text: root.phaseLabel.toUpperCase()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                horizontalAlignment: Text.AlignHCenter
              }

              Text {
                width: parent.width
                text: root.timeText
                color: root.alarming ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Math.round(Style.font.displayLarge * 1.5)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter

                Behavior on color { ColorAnimation { duration: 200 } }
              }

              Text {
                width: parent.width
                text: root.completedSessions > 0
                  ? root.completedSessions + " session" + (root.completedSessions > 1 ? "s" : "") + " completed"
                  : "Ready to focus"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }

          // Progress track
          Item {
            width: parent.width
            height: Style.space(4)

            Rectangle {
              anchors.fill: parent
              radius: height / 2
              color: root.track
              opacity: 0.3
            }

            Rectangle {
              width: parent.width * root.progress
              height: parent.height
              radius: height / 2
              color: root.alarming ? root.urgent : root.foreground

              Behavior on width {
                NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(6)
            property real cellWidth: (width - spacing * 2) / 3

            Button {
              width: parent.cellWidth
              iconText: root.running ? "󰏤" : "󰐊"
              text: root.running ? "Pause" : "Start"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              accent: root.running ? root.foreground : root.urgent
              onClicked: root.startPause()
            }

            Button {
              width: parent.cellWidth
              iconText: "󰒭"
              text: "Skip"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              onClicked: root.skip()
            }

            Button {
              width: parent.cellWidth
              iconText: "󰑐"
              text: "Reset"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              onClicked: root.stop()
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "MODES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(6)
            property real cellWidth: (width - spacing * 2) / 3

            Button {
              width: parent.cellWidth
              text: "Focus"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              selected: root.phase === "focus"
              onClicked: root.switchPhase("focus")
            }

            Button {
              width: parent.cellWidth
              text: "Short"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              selected: root.phase === "shortBreak"
              onClicked: root.switchPhase("shortBreak")
            }

            Button {
              width: parent.cellWidth
              text: "Long"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              selected: root.phase === "longBreak"
              onClicked: root.switchPhase("longBreak")
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "CUSTOM TIMER"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            NumberField {
              id: customField
              value: root.customMinutes
              from: 1
              to: 999
              stepSize: 1
              foreground: root.foreground
              accent: root.track
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              onModified: function(v) { if (root.service) root.service.customMinutes = v }

              field.Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                  keyCatcher.forceActiveFocus()
                  root.switchPanel(event.key === Qt.Key_Backtab ? "previous" : "next")
                  event.accepted = true
                } else if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                  root.setCustom(customField.value)
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
              }
            }

            Button {
              width: parent.width - customField.width - parent.spacing
              height: customField.height
              iconText: "󰐊"
              text: "Start Timer"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              bordered: true
              active: root.phase === "custom"
              onClicked: root.setCustom(customField.value)
            }
          }

          Text {
            width: parent.width
            text: "S start/pause · N skip · R reset\n1/2/3 modes · C custom · Enter start"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
