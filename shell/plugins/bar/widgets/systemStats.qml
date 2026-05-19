import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "systemStats"


  property real cpuPercent: 0
  property real memPercent: 0
  property var cpuHistory: []
  property var memHistory: []
  property real loadAvg: 0

  property var prevCpu: ({ idle: 0, total: 0 })

  property bool popupOpen: false

  function closePopout() { popupOpen = false }

  readonly property int historyLimit: 30

  function refresh() {
    if (!cpuProc.running) cpuProc.running = true
    if (!memProc.running) memProc.running = true
    if (!loadProc.running) loadProc.running = true
  }

  function pushHistory(arr, value) {
    var next = arr.slice()
    next.push(value)
    if (next.length > historyLimit) next.shift()
    return next
  }

  function updateCpu(raw) {
    var fields = String(raw || "").trim().split(/\s+/)
    if (fields.length < 8) return
    var user = parseInt(fields[1], 10) || 0
    var nice = parseInt(fields[2], 10) || 0
    var sys = parseInt(fields[3], 10) || 0
    var idle = parseInt(fields[4], 10) || 0
    var iowait = parseInt(fields[5], 10) || 0
    var irq = parseInt(fields[6], 10) || 0
    var softirq = parseInt(fields[7], 10) || 0

    var total = user + nice + sys + idle + iowait + irq + softirq
    var totalDiff = total - prevCpu.total
    var idleDiff = idle - prevCpu.idle

    if (prevCpu.total > 0 && totalDiff > 0) {
      var usage = (1 - idleDiff / totalDiff) * 100
      cpuPercent = Math.max(0, Math.min(100, usage))
      cpuHistory = pushHistory(cpuHistory, cpuPercent)
    }

    prevCpu = { idle: idle, total: total }
  }

  function updateMem(raw) {
    var lines = String(raw || "").split("\n")
    var total = 0
    var available = 0
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line.indexOf("MemTotal:") === 0) total = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0
      else if (line.indexOf("MemAvailable:") === 0) available = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0
    }
    if (total > 0) {
      memPercent = ((total - available) / total) * 100
      memHistory = pushHistory(memHistory, memPercent)
    }
  }

  function updateLoad(raw) {
    var n = parseFloat(String(raw || "").trim().split(/\s+/)[0])
    if (!isNaN(n)) loadAvg = n
  }

  Component.onCompleted: refresh()

  Process {
    id: cpuProc
    command: ["bash", "-lc", "head -n1 /proc/stat"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateCpu(text)
    }
  }

  Process {
    id: memProc
    command: ["bash", "-lc", "head -n3 /proc/meminfo"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateMem(text)
    }
  }

  Process {
    id: loadProc
    command: ["bash", "-lc", "cat /proc/loadavg"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateLoad(text)
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color statColor: bar ? bar.foreground : "#cacccc"

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
        barFg: root.statColor
        fontFamily: root.bar.fontFamily
        width: parent.width
      }

      DetailStat {
        title: "Memory"
        value: Math.round(root.memPercent) + "%"
        history: root.memHistory
        barFg: root.statColor
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
    property color barFg: "#cacccc"
    property string fontFamily: "JetBrainsMono Nerd Font"

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
