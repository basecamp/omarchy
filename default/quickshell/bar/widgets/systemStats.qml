import QtQuick
import Quickshell
import Quickshell.Io
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "systemStats"
  property var settings: ({})

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
    onTriggered: {
      root.refresh()
      if (!loadProc.running) loadProc.running = true
    }
  }

  readonly property bool vertical: bar ? bar.vertical : false

  implicitWidth: vertical ? (bar ? bar.barSize : 28) : (statLayout.item ? statLayout.item.implicitWidth + 6 : 0)
  implicitHeight: vertical ? (statLayout.item ? statLayout.item.implicitHeight + 6 : 0) : (bar ? bar.barSize : 26)

  readonly property color statColor: bar ? bar.foreground : "#cacccc"
  readonly property string statFont: bar ? bar.fontFamily : "JetBrainsMono Nerd Font"

  Loader {
    id: statLayout
    anchors.centerIn: parent
    sourceComponent: root.vertical ? statColumn : statRow
  }

  Component {
    id: statRow
    Row {
      spacing: 8
      StatPill {
        glyph: "󰻠"
        percent: root.cpuPercent
        history: root.cpuHistory
        vertical: false
        barFg: root.statColor
        fontFamily: root.statFont
      }
      StatPill {
        glyph: "󰍛"
        percent: root.memPercent
        history: root.memHistory
        vertical: false
        barFg: root.statColor
        fontFamily: root.statFont
      }
    }
  }

  Component {
    id: statColumn
    Column {
      spacing: 4
      StatPill {
        glyph: "󰻠"
        percent: root.cpuPercent
        history: root.cpuHistory
        vertical: true
        barFg: root.statColor
        fontFamily: root.statFont
      }
      StatPill {
        glyph: "󰍛"
        percent: root.memPercent
        history: root.memHistory
        vertical: true
        barFg: root.statColor
        fontFamily: root.statFont
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.bar.run("alacritty")
      else root.popupOpen = !root.popupOpen
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, "CPU " + Math.round(root.cpuPercent) + "%  ·  Mem " + Math.round(root.memPercent) + "%  ·  Load " + root.loadAvg.toFixed(2))
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  Common.PopupCard {
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: 320
    contentHeight: detailColumn.implicitHeight + 28

    Column {
      id: detailColumn
      anchors.fill: parent
      spacing: 10

      Text {
        text: "System"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: 12
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
        spacing: 6
        Text {
          text: "Load"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }
        Text {
          text: root.loadAvg.toFixed(2)
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 11
        }
      }

      Common.PillButton {
        width: parent.width
        iconText: "󰆍"
        text: "Open btop"
        foreground: root.bar.foreground
        horizontalPadding: 10
        verticalPadding: 8
        onClicked: { root.bar.run("omarchy-launch-or-focus-tui btop"); root.popupOpen = false }
      }
    }
  }

  component StatPill: Item {
    id: pill
    property string glyph: ""
    property real percent: 0
    property var history: []
    property bool vertical: false
    property color barFg: "#cacccc"
    property string fontFamily: "JetBrainsMono Nerd Font"

    implicitWidth: vertical ? 22 : 56
    implicitHeight: vertical ? 32 : 22

    Row {
      visible: !pill.vertical
      anchors.fill: parent
      spacing: 4

      Text {
        text: pill.glyph
        color: pill.barFg
        font.family: pill.fontFamily
        font.pixelSize: 12
        anchors.verticalCenter: parent.verticalCenter
      }

      Canvas {
        id: spark
        width: 36
        height: 14
        anchors.verticalCenter: parent.verticalCenter
        property var history: pill.history
        onHistoryChanged: requestPaint()

        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          if (!pill.history || pill.history.length === 0) return

          ctx.strokeStyle = pill.barFg
          ctx.fillStyle = Qt.rgba(pill.barFg.r, pill.barFg.g, pill.barFg.b, 0.2)
          ctx.lineWidth = 1

          ctx.beginPath()
          var step = width / Math.max(1, pill.history.length - 1)
          for (var i = 0; i < pill.history.length; i++) {
            var x = i * step
            var y = height - (pill.history[i] / 100) * height
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

    Column {
      visible: pill.vertical
      anchors.fill: parent
      spacing: 2

      Text {
        text: pill.glyph
        color: pill.barFg
        font.family: pill.fontFamily
        font.pixelSize: 10
        anchors.horizontalCenter: parent.horizontalCenter
      }

      Text {
        text: Math.round(pill.percent) + ""
        color: pill.barFg
        font.family: pill.fontFamily
        font.pixelSize: 9
        anchors.horizontalCenter: parent.horizontalCenter
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

    spacing: 4

    Row {
      width: parent.width
      Text {
        text: detail.title
        color: Qt.darker(detail.barFg, 1.4)
        font.family: detail.fontFamily
        font.pixelSize: 11
      }
      Item { width: detail.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth; height: 1 }
      Text {
        text: detail.value
        color: detail.barFg
        font.family: detail.fontFamily
        font.pixelSize: 11
      }
    }

    Canvas {
      id: detailCanvas
      width: parent.width
      height: 40
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
