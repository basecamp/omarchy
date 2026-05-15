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

  // Parsed wttr.in j1 response. Kept on failure so stale data stays visible.
  property var report: null

  readonly property string label: bar ? bar.weatherText : ""
  readonly property string klass: bar ? bar.weatherClass : ""

  readonly property var current: report && report.current_condition && report.current_condition[0] ? report.current_condition[0] : null
  readonly property var areaInfo: report && report.nearest_area && report.nearest_area[0] ? report.nearest_area[0] : null
  readonly property var forecastDays: report && report.weather ? report.weather : []

  readonly property bool useImperial: {
    var override = setting("unit", "")
    if (override === "imperial") return true
    if (override === "metric") return false
    var name = String(Qt.locale().name || "")
    return /^en_US/.test(name) || /^en_LR/.test(name) || /^my/.test(name)
  }

  // Auto-refresh interval in minutes; clamped to a sane minimum.
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)

  readonly property string reportLocation:  areaInfo && areaInfo.areaName && areaInfo.areaName[0] ? areaInfo.areaName[0].value : ""
  readonly property string reportCondition: current && current.weatherDesc && current.weatherDesc[0] ? current.weatherDesc[0].value : ""
  readonly property string reportTemp:      current ? formatTemp(useImperial ? current.temp_F : current.temp_C) : ""
  readonly property string reportTempNum:   current ? String(useImperial ? current.temp_F : current.temp_C) : ""
  readonly property string tempUnit:        "°" + (useImperial ? "F" : "C")
  readonly property string reportFeels:     current ? formatTemp(useImperial ? current.FeelsLikeF : current.FeelsLikeC) : ""
  readonly property string reportWind:      current ? (useImperial ? (current.windspeedMiles + " mph") : (current.windspeedKmph + " km/h")) : ""
  readonly property string reportHumidity:  current ? (current.humidity + "%") : ""
  readonly property string conditionLine: {
    var parts = []
    if (reportCondition) parts.push(reportCondition)
    var wd = windDescriptor()
    if (wd) parts.push(wd)
    return parts.join(" · ")
  }

  visible: label !== ""
  implicitWidth: button.implicitWidth + 8
  implicitHeight: button.implicitHeight

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  function refresh() {
    if (!forecastProc.running) forecastProc.running = true
  }

  function formatTemp(value) {
    if (value === undefined || value === null || value === "") return ""
    return value + "°" + (useImperial ? "F" : "C")
  }

  function dayName(dateString) {
    if (!dateString) return ""
    var d = new Date(dateString + "T12:00:00")
    if (isNaN(d.getTime())) return ""
    return Qt.formatDate(d, "ddd")
  }

  function maxTempForDay(day) {
    if (!day) return ""
    return formatTemp(useImperial ? day.maxtempF : day.maxtempC)
  }

  function minTempForDay(day) {
    if (!day) return ""
    return formatTemp(useImperial ? day.mintempF : day.mintempC)
  }

  // Beaufort-ish descriptor based on current windspeed in mph.
  function windDescriptor() {
    if (!current) return ""
    var mph = parseInt(String(current.windspeedMiles || "0"), 10)
    if (isNaN(mph)) return ""
    if (mph < 1)  return "Calm"
    if (mph < 4)  return "Light air"
    if (mph < 8)  return "Light breeze"
    if (mph < 13) return "Gentle breeze"
    if (mph < 19) return "Moderate breeze"
    if (mph < 25) return "Fresh breeze"
    if (mph < 32) return "Strong breeze"
    if (mph < 39) return "Near gale"
    return "Gale"
  }

  // Bare degree value (no unit letter), used in the forecast row.
  function bareTempForDay(day, kind) {
    if (!day) return ""
    var v = useImperial
      ? (kind === "max" ? day.maxtempF : day.mintempF)
      : (kind === "max" ? day.maxtempC : day.mintempC)
    if (v === undefined || v === null || v === "") return ""
    return v + "°"
  }

  // Representative icon for a forecast day: the hourly entry nearest noon.
  function dayIcon(day) {
    if (!day || !day.hourly || day.hourly.length === 0) return ""
    var best = day.hourly[0]
    var bestDist = 9999
    for (var i = 0; i < day.hourly.length; ++i) {
      var t = parseInt(String(day.hourly[i].time || "0"), 10)
      var dist = Math.abs(t - 1200)
      if (dist < bestDist) { bestDist = dist; best = day.hourly[i] }
    }
    return iconForCode(best.weatherCode, false)
  }

  // Mirrors omarchy-weather-icon's wttr.in code → nerd-font glyph mapping.
  function iconForCode(code, night) {
    var c = parseInt(String(code || "0"), 10)
    switch (c) {
      case 113: return night ? "" : ""
      case 116: return night ? "" : ""
      case 119: case 122: return ""
      case 143: case 248: case 260: return ""
      case 176: case 263: case 353: return night ? "" : ""
      case 179: case 227: case 230: case 323: case 326: case 368: return night ? "" : ""
      case 182: case 185: case 281: case 284: case 311: case 314:
      case 317: case 320: case 350: case 362: case 365: case 374: case 377: return ""
      case 200: case 386: case 389: case 392: case 395: return ""
      case 266: case 293: case 296: case 299: case 302: case 305: case 308: case 356: case 359: return ""
      case 329: case 332: case 335: case 338: case 371: return ""
      default: return ""
    }
  }

  Process {
    id: forecastProc
    command: ["bash", "-lc", "curl -fsS --max-time 5 'https://wttr.in/?format=j1' 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          root.report = JSON.parse(raw)
        } catch (e) {
          // Keep last-good report on parse failure so the popup isn't blanked.
        }
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Common.WidgetButton {
    id: button
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: implicitWidth
    height: implicitHeight
    bar: root.bar
    text: root.label
    active: root.klass === "active"
    horizontalMargin: 1
    // Tooltip suppressed — the popup itself is the detail view.
    tooltipText: ""

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.bar.run("omarchy-notification-send \"$(omarchy-weather-status)\"")
      } else if (b === Qt.MiddleButton) {
        root.refresh()
      } else {
        var willOpen = !root.popupOpen
        root.popupOpen = willOpen
        if (willOpen) root.refresh()
      }
    }
  }

  Common.PopupCard {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    triggerMode: "click"
    contentWidth: 460
    contentHeight: card.implicitHeight + 28

    Column {
      id: card
      anchors.fill: parent
      spacing: 20

      // ---- Hero row: location/temp/condition on the left, big icon on the right.
      Item {
        width: parent.width
        height: heroLeft.height

        Column {
          id: heroLeft
          anchors.left: parent.left
          anchors.top: parent.top
          spacing: 6

          Row {
            visible: root.reportLocation !== ""
            spacing: 6

            Text {
              text: ""  // nf-fa-map_marker
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: 11
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: (root.reportLocation || "").toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: 11
              font.letterSpacing: 1
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            spacing: 2

            Text {
              id: tempBig
              text: root.reportTempNum || "—"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: 56
              font.bold: true
            }
            Text {
              text: root.current ? root.tempUnit : ""
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: 22
              anchors.top: tempBig.top
              anchors.topMargin: 10
            }
          }

          Text {
            visible: text !== ""
            text: root.conditionLine
            color: Qt.darker(root.bar.foreground, 1.2)
            font.family: root.bar.fontFamily
            font.pixelSize: 12
          }
        }

        Text {
          id: heroIcon
          anchors.right: parent.right
          anchors.verticalCenter: heroLeft.verticalCenter
          text: root.label || "—"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 56
        }
      }

      // ---- Stats row: three caps-labeled columns.
      Row {
        visible: !!root.current
        width: parent.width
        spacing: 36

        Column {
          spacing: 4
          Text {
            text: "FEELS"
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: 10
            font.letterSpacing: 1
          }
          Text {
            text: root.reportFeels
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: 13
          }
        }

        Column {
          spacing: 4
          Text {
            text: "WIND"
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: 10
            font.letterSpacing: 1
          }
          Text {
            text: root.reportWind
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: 13
          }
        }

        Column {
          spacing: 4
          Text {
            text: "HUMIDITY"
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: 10
            font.letterSpacing: 1
          }
          Text {
            text: root.reportHumidity
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: 13
          }
        }
      }

      Text {
        visible: !root.current
        text: "Fetching forecast…"
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: 11
        font.italic: true
      }

      // ---- Divider between current conditions and forecast.
      Rectangle {
        visible: root.forecastDays.length > 0
        width: parent.width
        height: 1
        color: root.bar.foreground
        opacity: 0.12
      }

      // ---- Forecast row: each cell has the day icon left of a day-name + hi/lo column.
      Row {
        id: forecastRow
        visible: root.forecastDays.length > 0
        width: parent.width

        Repeater {
          model: root.forecastDays

          Row {
            required property var modelData
            required property int index
            width: forecastRow.width / Math.max(1, root.forecastDays.length)
            spacing: 10

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.dayIcon(modelData)
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: 24
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2

              Text {
                text: root.dayName(modelData.date).toUpperCase()
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 1
              }

              Row {
                spacing: 6

                Text {
                  text: root.bareTempForDay(modelData, "max")
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: 12
                }
                Text {
                  text: root.bareTempForDay(modelData, "min")
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: 12
                }
              }
            }
          }
        }
      }
    }
  }
}
