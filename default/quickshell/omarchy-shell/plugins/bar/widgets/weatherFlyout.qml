import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "weatherFlyout"
  property var settings: ({})

  property bool popupOpen: false
  function closePopout() { popupOpen = false }

  IpcHandler {
    target: "weatherFlyout"
    function show(): void {
      root.popupOpen = !root.popupOpen
      if (root.popupOpen) root.refresh()
    }

    function toggle(): void {
      show()
    }
  }

  // Parsed wttr.in j1 response. Kept on failure so stale data stays visible.
  property var report: null
  property var dailyForecastReport: null
  property string wttrLocation: ""

  // Bar pill state. Polled locally; populated by weatherProc below.
  property string label: ""
  property string klass: ""

  function updateWeather(raw) {
    var data
    try { data = JSON.parse(raw || "{}") } catch (e) { data = {} }
    label = data.text || ""
    klass = data.class || ""
  }

  readonly property var current: report && report.current_condition && report.current_condition[0] ? report.current_condition[0] : null
  readonly property var areaInfo: report && report.nearest_area && report.nearest_area[0] ? report.nearest_area[0] : null
  readonly property var forecastDays: buildForecastDays()

  readonly property bool useImperial: {
    var override = setting("unit", "")
    if (override === "imperial") return true
    if (override === "metric") return false
    var name = String(Qt.locale().name || "")
    return /^en_US/.test(name) || /^en_LR/.test(name) || /^my/.test(name)
  }

  // Auto-refresh interval in minutes; clamped to a sane minimum.
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)

  readonly property string reportLocation:  wttrLocation || (areaInfo && areaInfo.areaName && areaInfo.areaName[0] ? areaInfo.areaName[0].value : "")
  readonly property string reportCondition: current && current.weatherDesc && current.weatherDesc[0] ? current.weatherDesc[0].value : ""
  readonly property string reportTemp:      current ? formatTemp(useImperial ? current.temp_F : current.temp_C) : ""
  readonly property string reportTempNum:   current ? String(useImperial ? current.temp_F : current.temp_C) : ""
  readonly property string tempUnit:        "°" + (useImperial ? "F" : "C")
  readonly property string reportFeels:     current ? formatTemp(useImperial ? current.FeelsLikeF : current.FeelsLikeC) : ""
  readonly property string reportWind:      current ? (useImperial ? (current.windspeedMiles + " mph") : (current.windspeedKmph + " km/h")) : ""
  readonly property string reportHumidity:  current ? (current.humidity + "%") : ""

  visible: label !== ""
  implicitWidth: button.implicitWidth + 8
  implicitHeight: button.implicitHeight

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  function refresh() {
    if (!forecastProc.running) forecastProc.running = true
    if (!locationProc.running) locationProc.running = true
  }

  function refreshDailyForecast(sourceReport) {
    var area = sourceReport && sourceReport.nearest_area && sourceReport.nearest_area[0] ? sourceReport.nearest_area[0] : root.areaInfo
    if (!area || dailyForecastProc.running) return

    var lat = parseFloat(String(area.latitude || ""))
    var lon = parseFloat(String(area.longitude || ""))
    if (isNaN(lat) || isNaN(lon)) return

    var url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + encodeURIComponent(String(lat))
      + "&longitude=" + encodeURIComponent(String(lon))
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
      + "&forecast_days=4"
      + "&timezone=auto"
    dailyForecastProc.command = ["curl", "-fsS", "--max-time", "5", url]
    dailyForecastProc.running = true
  }

  function buildForecastDays() {
    var days = openMeteoForecastDays()
    return days.length > 0 ? days : wttrNextForecastDays()
  }

  function openMeteoForecastDays() {
    var daily = dailyForecastReport && dailyForecastReport.daily ? dailyForecastReport.daily : null
    if (!daily || !daily.time) return []

    var result = []
    for (var i = 0; i < daily.time.length && result.length < 3; ++i) {
      var date = daily.time[i]
      if (!isFutureForecastDate(date)) continue

      var maxC = daily.temperature_2m_max ? daily.temperature_2m_max[i] : ""
      var minC = daily.temperature_2m_min ? daily.temperature_2m_min[i] : ""
      result.push({
        date: date,
        maxtempC: roundedTemp(maxC),
        mintempC: roundedTemp(minC),
        maxtempF: roundedTemp(celsiusToFahrenheit(maxC)),
        mintempF: roundedTemp(celsiusToFahrenheit(minC)),
        openMeteoWeatherCode: daily.weather_code ? daily.weather_code[i] : null
      })
    }
    return result
  }

  function wttrNextForecastDays() {
    var days = report && report.weather ? report.weather : []
    var result = []
    for (var i = 0; i < days.length && result.length < 3; ++i) {
      if (isFutureForecastDate(days[i].date)) result.push(days[i])
    }
    return result
  }

  function isFutureForecastDate(dateString) {
    if (!dateString) return false
    return String(dateString).slice(0, 10) > Qt.formatDate(new Date(), "yyyy-MM-dd")
  }

  function roundedTemp(value) {
    if (value === undefined || value === null || value === "") return ""
    var n = parseFloat(String(value))
    return isNaN(n) ? "" : String(Math.round(n))
  }

  function celsiusToFahrenheit(value) {
    if (value === undefined || value === null || value === "") return ""
    var n = parseFloat(String(value))
    return isNaN(n) ? "" : (n * 9 / 5) + 32
  }

  function formatTemp(value) {
    if (value === undefined || value === null || value === "") return ""
    return value + "°" + (useImperial ? "F" : "C")
  }

  function dayName(dateString) {
    if (!dateString) return ""
    var d = new Date(dateString + "T12:00:00")
    if (isNaN(d.getTime())) return ""
    return Qt.formatDate(d, "dddd")
  }

  function maxTempForDay(day) {
    if (!day) return ""
    return formatTemp(useImperial ? day.maxtempF : day.maxtempC)
  }

  function minTempForDay(day) {
    if (!day) return ""
    return formatTemp(useImperial ? day.mintempF : day.mintempC)
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
    if (!day) return ""
    if (day.openMeteoWeatherCode !== undefined && day.openMeteoWeatherCode !== null) return iconForOpenMeteoCode(day.openMeteoWeatherCode)
    if (!day.hourly || day.hourly.length === 0) return ""
    var best = day.hourly[0]
    var bestDist = 9999
    for (var i = 0; i < day.hourly.length; ++i) {
      var t = parseInt(String(day.hourly[i].time || "0"), 10)
      var dist = Math.abs(t - 1200)
      if (dist < bestDist) { bestDist = dist; best = day.hourly[i] }
    }
    return iconForCode(best.weatherCode, false)
  }

  function iconForOpenMeteoCode(code) {
    var c = parseInt(String(code || "0"), 10)
    if (c === 0) return iconForCode(113, false)
    if (c === 1 || c === 2) return iconForCode(116, false)
    if (c === 3) return iconForCode(119, false)
    if (c === 45 || c === 48) return iconForCode(143, false)
    if (c === 51 || c === 53 || c === 55 || c === 56 || c === 57 || c === 61) return iconForCode(266, false)
    if (c === 63 || c === 65 || c === 66 || c === 67 || c === 80 || c === 81 || c === 82) return iconForCode(308, false)
    if (c === 71 || c === 73 || c === 75 || c === 77 || c === 85 || c === 86) return iconForCode(338, false)
    if (c === 95 || c === 96 || c === 99) return iconForCode(389, false)
    return iconForCode(119, false)
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
          var parsed = JSON.parse(raw)
          root.report = parsed
          root.refreshDailyForecast(parsed)
        } catch (e) {
          // Keep last-good report on parse failure so the popup isn't blanked.
        }
      }
    }
  }

  Process {
    id: dailyForecastProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          root.dailyForecastReport = JSON.parse(raw)
        } catch (e) {
          // Keep last-good daily forecast on parse failure.
        }
      }
    }
  }

  Process {
    id: locationProc
    command: ["bash", "-lc", "curl -fsS --max-time 4 'https://wttr.in?format=%l' 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        root.wttrLocation = raw.split(",")[0]
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

  WidgetButton {
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

  PopupCard {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    centerOnBar: true
    triggerMode: "click"
    contentWidth: 480
    contentHeight: card.implicitHeight + 28

    Column {
      id: card
      anchors.fill: parent
      spacing: 14

      // ---- Hero row: big icon + temp on the left; location and stats stacked on the right.
      Item {
        width: parent.width
        height: Math.max(heroLeft.height, heroRight.height)

        Row {
          id: heroLeft
          anchors.left: parent.left
          anchors.leftMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          spacing: 16

          Text {
            id: heroIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 5
            text: root.label || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: 64
          }

          Row {
            anchors.verticalCenter: parent.verticalCenter
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
        }

        Column {
          id: heroRight
          anchors.right: parent.right
          anchors.rightMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 12

          Row {
            visible: root.reportLocation !== ""
            spacing: 6

            Text {
              text: ""  // nf-fa-map_marker
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: 12
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: (root.reportLocation || "").toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: 12
              font.letterSpacing: 1
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            visible: !!root.current
            spacing: 36

            Column {
              spacing: 5
              Text {
                text: "FEELS"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 1
              }
              Text {
                text: root.reportFeels
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: 15
              }
            }

            Column {
              spacing: 5
              Text {
                text: "WIND"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 1
              }
              Text {
                text: root.reportWind
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: 15
              }
            }

            Column {
              spacing: 5
              Text {
                text: "HUMID"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 1
              }
              Text {
                text: root.reportHumidity
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: 15
              }
            }
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
      //      Wrapped in an Item so the block of cells can be centered within the popup.
      Item {
        visible: root.forecastDays.length > 0
        width: parent.width
        height: forecastRow.height

        Row {
          id: forecastRow
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 44

          Repeater {
            model: root.forecastDays

            Row {
              required property var modelData
              required property int index
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

  // Poll the weather pill text/class every minute. Local to this widget.
  Process {
    id: weatherProc
    command: ["bash", "-lc", root.bar ? root.bar.commandWithOmarchyPath(root.bar.shellQuote(root.bar.omarchyPath + "/default/quickshell/omarchy-shell/scripts/weather.sh")) : ""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateWeather(text)
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!weatherProc.running) weatherProc.running = true
  }
}
