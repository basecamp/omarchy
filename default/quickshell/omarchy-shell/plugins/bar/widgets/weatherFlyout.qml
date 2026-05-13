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

  // Pipe-delimited fields from wttr.in: location|condition|temp|feels|wind|humidity
  readonly property var reportFields: String(fullReport || "").split("|")
  readonly property string reportLocation:  reportFields.length > 0 ? String(reportFields[0] || "").trim() : ""
  readonly property string reportCondition: reportFields.length > 1 ? String(reportFields[1] || "").trim() : ""
  readonly property string reportTemp:      reportFields.length > 2 ? String(reportFields[2] || "").trim() : ""
  readonly property string reportFeels:     reportFields.length > 3 ? String(reportFields[3] || "").trim() : ""
  readonly property string reportWind:      reportFields.length > 4 ? String(reportFields[4] || "").trim() : ""
  readonly property string reportHumidity:  reportFields.length > 5 ? String(reportFields[5] || "").trim() : ""

  visible: label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!forecastProc.running) forecastProc.running = true
  }

  // Hover state across the trigger button and the popup.
  property bool buttonHovered: false
  property bool popupHovered: popup.containsMouse

  function showPopup() {
    hideTimer.stop()
    if (!popupOpen) refresh()
    popupOpen = true
  }

  function scheduleHide() {
    hideTimer.restart()
  }

  Timer {
    id: hideTimer
    interval: 220
    onTriggered: {
      if (!root.buttonHovered && !root.popupHovered) root.popupOpen = false
    }
  }

  onButtonHoveredChanged: buttonHovered ? showPopup() : scheduleHide()
  onPopupHoveredChanged: popupHovered ? hideTimer.stop() : scheduleHide()

  Process {
    id: forecastProc
    command: ["bash", "-lc", "curl -fsS --max-time 5 'wttr.in/?T0&format=%l|%C|%t|%f|%w|%h' 2>/dev/null"]
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
    // Tooltip suppressed — the popup itself is the detail view.
    tooltipText: ""

    onPressed: function(b) {
      if (b === Qt.RightButton) root.bar.run("omarchy-notification-send \"$(omarchy-weather-status)\"")
      else if (b === Qt.MiddleButton) root.refresh()
    }
  }

  HoverHandler {
    id: hoverHandler
    target: button
    onHoveredChanged: root.buttonHovered = hovered
  }

  Common.PopupCard {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    triggerMode: "hover"
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
        visible: text !== ""
        text: root.reportCondition
        color: Qt.darker(root.bar.foreground, 1.2)
        font.family: root.bar.fontFamily
        font.pixelSize: 11
        font.italic: true
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Text {
        visible: root.fullReport === ""
        text: "Fetching forecast…"
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: 11
        font.italic: true
      }

      // Key/value pairs — each metric on its own line for scanability.
      Grid {
        visible: root.reportTemp !== ""
        width: parent.width
        columns: 2
        columnSpacing: 12
        rowSpacing: 4

        Text {
          text: "Temperature"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }
        Text {
          text: root.reportTemp + (root.reportFeels && root.reportFeels !== root.reportTemp ? "  (feels " + root.reportFeels + ")" : "")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }

        Text {
          text: "Wind"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }
        Text {
          text: root.reportWind
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }

        Text {
          text: "Humidity"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }
        Text {
          text: root.reportHumidity
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }
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
