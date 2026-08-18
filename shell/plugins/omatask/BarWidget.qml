import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget plus its under-bar panel. The widget paints a live CPU history
// graph in the bar itself; clicking drops the panel below it with per-core
// meters, memory, I/O, and the busiest processes. The full process table lives
// in the overlay, one click further in.
Panel {
  id: root

  // Dimming has to know what it is dimming *against*. dim() only reads as
  // "less prominent" on a dark ground; on a light theme it makes secondary text
  // darker — and therefore louder — than the primary text it sits behind. This
  // moves toward the background either way.
  readonly property bool groundIsDark: {
    var g = (root.bar ? root.bar.background : Color.popups.background)
    return (g.r * 0.2126 + g.g * 0.7152 + g.b * 0.0722) < 0.5
  }
  function dim(c, amount) {
    return groundIsDark ? Qt.darker(c, amount) : Qt.lighter(c, amount)
  }

  moduleName: "omarchy.omatask"
  ipcTarget: "omatask"
  // The base Panel would register its own handler for that target; this widget
  // owns the single allowed one so it can add expand() alongside the standard
  // open/close/toggle.
  manageIpc: false

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null

  readonly property int intervalSec: Math.max(1, Number(setting("intervalSec", 2)) || 2)
  readonly property int historyPoints: Math.max(10, Number(setting("historyPoints", 60)) || 60)
  readonly property int processLimit: Math.max(10, Number(setting("processLimit", 60)) || 60)
  readonly property bool showPercent: setting("showPercent", true) === true
  readonly property bool alerts: setting("alerts", false) === true
  readonly property bool groupApps: setting("groupApps", true) === true
  readonly property string listMode: String(setting("listMode", "processes"))
  readonly property string sortBy: String(setting("sortBy", "cpu"))
  readonly property bool sortDescending: setting("sortDescending", true) === true
  readonly property string barGraph: String(setting("barGraph", "sparkline"))

  // How many samples the in-bar graph shows. Deliberately shorter than the
  // panel's history: at 30px wide, sixty points is noise.
  readonly property int barPoints: 24
  readonly property int panelProcessCount: 8

  property int cursorIndex: -1
  property bool cursorActive: false

  readonly property real cpuPercent: service ? service.cpuPercent : 0
  readonly property var panelProcesses: {
    if (!service) return []
    var rows = service.processes || []
    return rows.slice(0, root.panelProcessCount)
  }

  // Push settings down into the shared sampler. The widget owns the shell.json
  // entry, so it is the only surface that knows what the user configured.
  function syncService() {
    if (!service) return
    service.intervalSec = intervalSec
    service.historyPoints = historyPoints
    service.processLimit = processLimit
    service.alertsEnabled = alerts
    service.groupApps = groupApps
    service.listMode = listMode
    service.sortBy = sortBy
    service.sortDescending = sortDescending
    // Hand over the whole entry so the service can merge into it when a
    // preference changes from the overlay, which has no access to shell.json.
    service.widgetSettings = settings || ({})
  }

  onServiceChanged: syncService()
  onIntervalSecChanged: syncService()
  onHistoryPointsChanged: syncService()
  onProcessLimitChanged: syncService()
  onAlertsChanged: syncService()
  onGroupAppsChanged: syncService()
  onListModeChanged: syncService()
  onSortByChanged: syncService()
  onSortDescendingChanged: syncService()
  // The bar host injects `settings` after construction, so a preference read
  // at Component.onCompleted would still be the default. Re-sync whenever the
  // entry itself changes — including when this widget writes back to it.
  onSettingsChanged: syncService()
  Component.onCompleted: syncService()

  // The sampler skips the process walk unless something is showing it.
  onOpenedChanged: {
    if (!service) return
    if (opened) {
      service.retainProcesses()
      service.retainGpu()
      cursorIndex = -1
      cursorActive = false
    } else {
      service.releaseProcesses()
      service.releaseGpu()
    }
  }

    Component.onDestruction: {
    if (!service || !opened) return
    service.releaseProcesses()
    service.releaseGpu()
  }

  function expand() {
    close()
    if (bar && bar.shell) bar.shell.summon(moduleName, "{}")
  }

  function moveCursor(delta) {
    var count = panelProcesses.length
    if (count === 0) return
    if (!cursorActive) {
      cursorActive = true
      cursorIndex = 0
      return
    }
    cursorIndex = Math.max(0, Math.min(count - 1, cursorIndex + delta))
  }

  function killCursor(signalName) {
    if (!service || cursorIndex < 0 || cursorIndex >= panelProcesses.length) return
    service.killProcess(panelProcesses[cursorIndex].pid, signalName)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ------------------------------------------------------------ bar button

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.service && root.service.ready
      ? "CPU " + Model.formatPercent(root.cpuPercent) + " · MEM " + Model.formatPercent(root.service.memPercent)
      : "Task Manager"

    // Vertical bars have no room for a history graph, so they fall back to the
    // percentage alone — the same compromise the media widget makes.
    readonly property bool graphVisible: !vertical && root.barGraph !== "none"
    readonly property real graphWidth: graphVisible ? Style.space(34) : 0

    fixedWidth: vertical ? -1 : graphWidth + (root.showPercent ? percentLabel.implicitWidth + Style.space(5) : 0) + Style.space(10)
    fixedHeight: vertical ? Style.bar.iconSlot : -1

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.expand()
      else root.toggle()
    }

    Row {
      anchors.centerIn: parent
      spacing: Style.space(5)

      Sparkline {
        id: barGraphCanvas
        visible: button.graphVisible
        width: button.graphWidth
        height: Math.max(Style.space(9), button.barSize - Style.space(14))
        anchors.verticalCenter: parent.verticalCenter
        values: root.service ? root.service.cpuHistory.slice(-root.barPoints) : []
        capacity: root.barPoints
        maxValue: 100
        bars: root.barGraph === "bars"
        stroke: root.cpuPercent >= 85 ? button.activeColor : button.foreground
        lineWidth: 1
        fillOpacity: 0.22
        barGap: 1
      }

      Text {
        id: percentLabel
        visible: root.showPercent || button.vertical
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.cpuPercent) + (button.vertical ? "" : "%")
        color: root.cpuPercent >= 85 ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering
      }
    }
  }

  IpcHandler {
    target: "omarchy.omatask"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function expand(): void { root.expand() }
  }

  // ----------------------------------------------------------- under-bar panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.expand()
      onDeleteRequested: root.killCursor("TERM")
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- CPU ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(cpuLabels.implicitHeight, cpuValue.implicitHeight)

          Column {
            id: cpuLabels
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              text: "CPU"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: {
                var service = root.service
                if (!service || !service.ready) return "SAMPLING…"
                var load = service.loadAverage
                var parts = [service.coreCount + " THREADS"]
                if (service.hasCpuTemp) parts.push(Math.round(service.cpuTemp) + "°C")
                parts.push("LOAD " + Number(load[0]).toFixed(2) + " " + Number(load[1]).toFixed(2))
                return parts.join(" · ")
              }
              color: dim(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.0
            }
          }

          Text {
            id: cpuValue
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.cpuPercent.toFixed(1) + "%"
            color: root.cpuPercent >= 85 ? root.bar.urgent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        Sparkline {
          width: parent.width
          height: Style.space(52)
          values: root.service ? root.service.cpuHistory : []
          capacity: root.historyPoints
          maxValue: 100
          stroke: root.bar.foreground
          showBaseline: true
        }

        CoreGrid {
          ground: root.bar.background
          width: parent.width
          cores: root.service ? root.service.cores : []
          foreground: root.bar.foreground
          fill: root.bar.foreground
          hotColor: root.bar.urgent
          rowHeight: Style.space(22)
        }

        // ---------- Memory ----------
        PanelSeparator { foreground: root.bar.foreground }

        Meter {
          ground: root.bar.background
          width: parent.width
          label: "MEMORY"
          value: root.service
            ? Model.formatBytes(root.service.memUsed) + " / " + Model.formatBytes(root.service.memTotal)
            : ""
          fraction: root.service ? root.service.memPercent / 100 : 0
          foreground: root.bar.foreground
          fill: root.service && root.service.memPercent >= 90 ? root.bar.urgent : root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Meter {
          ground: root.bar.background
          width: parent.width
          // Plenty of Omarchy machines run zram or no swap at all; an empty
          // meter would just be a permanently dead row.
          visible: root.service && root.service.swapTotal > 0
          label: "SWAP"
          value: root.service
            ? Model.formatBytes(root.service.swapUsed) + " / " + Model.formatBytes(root.service.swapTotal)
            : ""
          fraction: root.service ? root.service.swapPercent / 100 : 0
          foreground: root.bar.foreground
          fill: root.bar.foreground
          fontFamily: root.bar.fontFamily
          compact: true
        }

        // ---------- GPU ----------
        // Hidden outright when nothing readable is present, so machines with
        // no discrete GPU don't carry a dead row.
        PanelSeparator {
          foreground: root.bar.foreground
          visible: root.service && root.service.hasGpu
        }

        Meter {
          ground: root.bar.background
          width: parent.width
          visible: root.service && root.service.hasGpu
          label: "GPU"
          value: root.service && root.service.hasGpu
            ? Math.round(root.service.gpuPercent) + "% · "
              + Model.formatBytes(root.service.gpuMemUsed) + " / "
              + Model.formatBytes(root.service.gpuMemTotal)
            : ""
          fraction: root.service ? root.service.gpuPercent / 100 : 0
          foreground: root.bar.foreground
          fill: root.service && root.service.gpuPercent >= 85 ? root.bar.urgent : root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Meter {
          ground: root.bar.background
          width: parent.width
          visible: root.service && root.service.hasGpu
          label: "VRAM"
          value: {
            if (!root.service || !root.service.hasGpu) return ""
            var device = root.service.primaryGpu
            var parts = [Math.round(root.service.gpuMemPercent) + "%"]
            if (device.temp !== null && device.temp !== undefined) parts.push(device.temp + "°C")
            if (device.power !== null && device.power !== undefined) parts.push(device.power + "W")
            return parts.join(" · ")
          }
          fraction: root.service ? root.service.gpuMemPercent / 100 : 0
          foreground: root.bar.foreground
          fill: root.bar.foreground
          fontFamily: root.bar.fontFamily
          compact: true
        }

        // ---------- I/O ----------
        PanelSeparator { foreground: root.bar.foreground }

        Row {
          width: parent.width
          spacing: Style.space(16)

          IoReadout {
            width: (parent.width - parent.spacing) / 2
            label: "NETWORK"
            down: root.service ? Model.formatRate(root.service.net.rx) : "—"
            up: root.service ? Model.formatRate(root.service.net.tx) : "—"
          }

          IoReadout {
            width: (parent.width - parent.spacing) / 2
            label: "DISK"
            down: root.service ? Model.formatRate(root.service.disk.read) : "—"
            up: root.service ? Model.formatRate(root.service.disk.write) : "—"
          }
        }

        // ---------- Processes ----------
        PanelSeparator { foreground: root.bar.foreground }

        Item {
          width: parent.width
          implicitHeight: processHeader.implicitHeight

          PanelSectionHeader {
            id: processHeader
            anchors.left: parent.left
            text: "TOP PROCESSES"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Text {
            anchors.right: parent.right
            anchors.baseline: processHeader.baseline
            text: root.service && root.service.ready
              ? root.service.processCount + " PROCS · " + root.service.threadCount + " THREADS"
              : ""
            color: dim(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.8
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(1)

          Repeater {
            model: root.panelProcesses

            ProcessRow {
              ground: root.bar.background
              required property var modelData
              required property int index

              process: modelData
              machineCapacity: root.service ? Math.max(1, root.service.coreCount) * 100 : 100
              selected: root.cursorActive && root.cursorIndex === index
              foreground: root.bar.foreground
              accent: root.bar.foreground
              urgent: root.bar.urgent
              fontFamily: root.bar.fontFamily
              onActivated: {
                root.cursorActive = true
                root.cursorIndex = index
              }
              onKillRequested: function(signalName) {
                if (root.service) root.service.killProcess(modelData.pid, signalName)
              }
            }
          }

          Text {
            visible: root.panelProcesses.length === 0
            width: parent.width
            height: Style.spacing.popupRowHeight
            verticalAlignment: Text.AlignVCenter
            text: "Waiting for the first sample…"
            color: dim(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---------- Footer ----------
        PanelSeparator { foreground: root.bar.foreground }

        Item {
          width: parent.width
          implicitHeight: expandButton.implicitHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            // The panel is the glance surface, so it carries a fact rather
            // than an instruction list; the ✕ appears on hover and the full
            // key legend lives behind `?` in the overlay.
            text: root.service && root.service.ready
              ? "UP " + Model.formatUptime(root.service.uptime)
              : ""
            color: dim(root.bar.foreground, 1.7)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.6
            elide: Text.ElideRight
            width: parent.width - expandButton.width - Style.space(10)
          }

          Button {
            id: expandButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Expand"
            iconText: "⤢"
            iconSize: Style.font.body
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            onClicked: root.expand()
          }
        }
      }
    }
  }

  // Two-line down/up readout, used for both network and disk so the pair reads
  // as one unit rather than two differently-shaped blocks.
  component IoReadout: Column {
    property string label: ""
    property string down: ""
    property string up: ""

    spacing: Style.spacing.labelGap

    PanelSectionHeader {
      text: parent.label
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }

    Text {
      text: "↓ " + parent.down
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      text: "↑ " + parent.up
      color: dim(root.bar.foreground, 1.3)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
