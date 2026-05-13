import QtQuick
import Quickshell
import Quickshell.Io
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "weatherFlyout"
  property var settings: ({})

  property bool popupOpen: false
  function closePopout() { popupOpen = false }

  property string fullReport: ""

  readonly property string label: bar ? bar.weatherText : ""
  readonly property string klass: bar ? bar.weatherClass : ""

  // Parse the wttr.in single-line report into location + condition halves so
  // we can render them with different emphasis.
  readonly property string reportLocation: {
    var parts = String(fullReport || "").split(":")
    return parts.length > 1 ? parts[0].trim() : ""
  }
  readonly property string reportCondition: {
    var parts = String(fullReport || "").split(":")
    if (parts.length > 1) return parts.slice(1).join(":").trim()
    return String(fullReport || "").trim()
  }

  visible: label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!forecastProc.running) forecastProc.running = true
  }

  Process {
    id: forecastProc
    command: ["bash", "-lc", "curl -fsS --max-time 5 'wttr.in/?T0&format=%l:+%C+%t+%f+wind+%w+%h+humidity' 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.fullReport = String(text || "").trim()
    }
  }

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    active: root.klass === "active"
    horizontalMargin: 7.5
    tooltipText: root.fullReport || "Weather"

    onPressed: function(b) {
      if (b === Qt.RightButton) root.bar.run("omarchy-notification-send \"$(omarchy-weather-status)\"")
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
    contentHeight: card.implicitHeight + 28

    Column {
      id: card
      anchors.fill: parent
      spacing: 12

      Row {
        width: parent.width
        spacing: 10

        Text {
          id: glyph
          text: root.label || "—"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 24
          anchors.verticalCenter: location.verticalCenter
        }

        Text {
          id: location
          text: root.reportLocation || "Weather"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 13
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - glyph.width - parent.spacing
          elide: Text.ElideRight
        }
      }

      Text {
        text: root.reportCondition || "Fetching forecast…"
        color: Qt.darker(root.bar.foreground, 1.2)
        font.family: root.bar.fontFamily
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Row {
        width: parent.width
        spacing: 8

        Common.PillButton {
          iconText: "󰑐"
          text: "Refresh"
          foreground: root.bar.foreground
          horizontalPadding: 12
          verticalPadding: 6
          onClicked: root.refresh()
        }

        Common.PillButton {
          iconText: "󰏌"
          text: "wttr.in"
          foreground: root.bar.foreground
          horizontalPadding: 12
          verticalPadding: 6
          onClicked: { root.bar.run("xdg-open https://wttr.in"); root.popupOpen = false }
        }
      }
    }
  }
}
