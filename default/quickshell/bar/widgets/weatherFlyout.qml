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
  property var forecast: ({})
  property string fullReport: ""

  readonly property string label: bar ? bar.weatherText : ""
  readonly property string klass: bar ? bar.weatherClass : ""

  visible: label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!forecastProc.running) forecastProc.running = true
  }

  function parseForecast(text) {
    var lines = String(text || "").split("\n")
    var data = { location: "", current: "", hourly: [], daily: [] }
    var section = ""

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (i === 0 && line.indexOf("Weather report:") === 0) {
        data.location = line.replace("Weather report:", "").trim()
      } else if (line.match(/^[├└]\s/)) {
        section = "daily"
      }
    }
    return data
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
    contentHeight: column.implicitHeight + 28

    Column {
      id: column
      anchors.fill: parent
      spacing: 10

      Row {
        spacing: 12
        width: parent.width

        Text {
          text: root.label || "—"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 28
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2

          Text {
            text: "Weather"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: 12
            font.bold: true
          }

          Text {
            text: root.fullReport || "Fetching forecast…"
            color: Qt.darker(root.bar.foreground, 1.2)
            font.family: root.bar.fontFamily
            font.pixelSize: 10
            wrapMode: Text.WordWrap
            width: 220
          }
        }
      }

      Common.PillButton {
        width: parent.width
        iconText: "󰑐"
        text: "Refresh"
        foreground: root.bar.foreground
        horizontalPadding: 10
        verticalPadding: 6
        onClicked: root.refresh()
      }

      Common.PillButton {
        width: parent.width
        iconText: "󰏌"
        text: "Open wttr.in"
        foreground: root.bar.foreground
        horizontalPadding: 10
        verticalPadding: 6
        onClicked: { root.bar.run("xdg-open https://wttr.in"); root.popupOpen = false }
      }
    }
  }
}
