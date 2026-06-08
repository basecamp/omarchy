import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "omarchy.system-stats"


  property real cpuPercent: 0
  property real memPercent: 0
  property var cpuHistory: []
  property var memHistory: []
  property real loadAvg: 0

  property var prevCpu: ({ idle: 0, total: 0 })

  property bool popupOpen: false

  function close() { popupOpen = false }

  readonly property int historyLimit: 30

  function refresh() {
    if (!statsProc.running) statsProc.running = true
  }

  function pushHistory(arr, value) {
    var next = arr.slice()
    next.push(value)
    if (next.length > historyLimit) next.shift()
    return next
  }

  function updateCpuTotals(idle, total) {
    var idleDiff = idle - prevCpu.idle
    var totalDiff = total - prevCpu.total

    if (prevCpu.total > 0 && totalDiff > 0) {
      var usage = (1 - idleDiff / totalDiff) * 100
      cpuPercent = Math.max(0, Math.min(100, usage))
      cpuHistory = pushHistory(cpuHistory, cpuPercent)
    }

    prevCpu = { idle: idle, total: total }
  }

  function updateLoad(raw) {
    var n = parseFloat(String(raw || "").trim().split(/\s+/)[0])
    if (!isNaN(n)) loadAvg = n
  }

  function updateStats(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].trim().split("\t")
      if (parts.length < 2) continue
      if (parts[0] === "cpu") updateCpuTotals(parseInt(parts[1], 10) || 0, parseInt(parts[2], 10) || 0)
      else if (parts[0] === "memory") updateMemPercent(parts[1])
      else if (parts[0] === "load") updateLoad(parts[1])
    }
  }

  function updateMemPercent(raw) {
    var n = parseFloat(String(raw || "").trim())
    if (!isNaN(n)) {
      memPercent = Math.max(0, Math.min(100, n))
      memHistory = pushHistory(memHistory, memPercent)
    }
  }

  Component.onCompleted: refresh()

  Process {
    id: statsProc
    command: [root.bar ? root.bar.omarchyPath + "/bin/omarchy-system-stats" : "omarchy-system-stats", "--bar-widget"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateStats(text)
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  readonly property color statColor: bar ? bar.barForeground : Color.foreground

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Hover state across the trigger button and the popup.
  property bool buttonHovered: false
  property bool popupHovered: popup.containsMouse

  function showPopup() {
    hideTimer.stop()
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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍛"
    horizontalMargin: 7.5
    tooltipText: ""

    onPressed: function(b) {
      if (b === Qt.LeftButton) {
        root.popupOpen = false
        root.bar.run("omarchy-launch-or-focus-tui btop")
      }
    }
  }

  HoverHandler {
    id: hoverHandler
    target: button
    onHoveredChanged: root.buttonHovered = hovered
  }

  PopupCard {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    triggerMode: "hover"
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(detailColumn.implicitHeight)

    Column {
      id: detailColumn
      anchors.fill: parent
      spacing: Style.space(10)

      Text {
        text: "System"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      DetailStat {
        title: "CPU"
        value: Math.round(root.cpuPercent) + "%"
        history: root.cpuHistory
        barFg: root.bar.foreground
        fontFamily: root.bar.fontFamily
        width: parent.width
      }

      DetailStat {
        title: "Memory"
        value: Math.round(root.memPercent) + "%"
        history: root.memHistory
        barFg: root.bar.foreground
        fontFamily: root.bar.fontFamily
        width: parent.width
      }

      Row {
        width: parent.width
        spacing: Style.space(6)
        Text {
          text: "Load"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          text: root.loadAvg.toFixed(2)
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  component DetailStat: Column {
    id: detail

    property string title: ""
    property string value: ""
    property var history: []
    property color barFg: Color.foreground
    property string fontFamily: Style.font.family

    spacing: Style.space(4)

    Row {
      width: parent.width
      Text {
        text: detail.title
        color: Qt.darker(detail.barFg, 1.4)
        font.family: detail.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Item { width: detail.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth; height: 1 }
      Text {
        text: detail.value
        color: detail.barFg
        font.family: detail.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Canvas {
      id: detailCanvas
      width: parent.width
      height: Style.space(40)
      property var history: detail.history
      onHistoryChanged: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!detail.history || detail.history.length === 0) return

        ctx.strokeStyle = detail.barFg
        ctx.fillStyle = Qt.rgba(detail.barFg.r, detail.barFg.g, detail.barFg.b, 0.25)
        ctx.lineWidth = 1.5

        ctx.beginPath()
        var step = width / Math.max(1, detail.history.length - 1)
        for (var i = 0; i < detail.history.length; i++) {
          var x = i * step
          var y = height - (detail.history[i] / 100) * (height - 2) - 1
          if (i === 0) ctx.moveTo(x, y)
          else ctx.lineTo(x, y)
        }
        ctx.stroke()
        ctx.lineTo(width, height)
        ctx.lineTo(0, height)
        ctx.closePath()
        ctx.fill()
      }
    }
  }
}
