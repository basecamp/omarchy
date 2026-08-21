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
  readonly property bool groundIsDark: Model.groundIsDark((root.bar ? root.bar.background : Color.popups.background))
  function dim(c, amount) { return Model.dim((root.bar ? root.bar.background : Color.popups.background), c, amount) }

  moduleName: "omarchy.omatask"
  // Written once and bound everywhere else. Three copies of this string is how
  // a rename gets partially applied — which already happened once here, leaving
  // ipcTarget naming a target no handler answered on.
  ipcTarget: moduleName
  // The base Panel would register its own handler for that target; this widget
  // owns the single allowed one so it can add expand() alongside the standard
  // open/close/toggle.
  manageIpc: false

  // Bound, not readonly: the shell's own manifest-entrypoint test instantiates
  // every entry point and assigns `service` to check the contract, and a
  // readonly property makes that assignment throw — which aborts the harness
  // mid-load rather than failing one plugin.
  property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null

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
  // Checked here rather than trusted: `omarchy bar set` writes whatever value
  // it is handed straight into shell.json without consulting the manifest
  // schema, so a typo arrives intact. An unrecognised metric reads as off,
  // instead of falling through to memory and captioning it wrongly.
  readonly property string secondaryMetric: {
    var value = String(setting("secondaryMetric", "none"))
    return ["mem", "swap", "gpu"].indexOf(value) >= 0 ? value : "none"
  }

  // How many samples the in-bar graph shows. Deliberately shorter than the
  // panel's history: at 30px wide, sixty points is noise.
  readonly property int barPoints: 24
  readonly property int panelProcessCount: 8

  property int cursorIndex: -1
  property bool cursorActive: false

  readonly property real cpuPercent: service ? service.cpuPercent : 0

  // A second metric alongside CPU, so both are readable without opening
  // anything. Every candidate is already in the sample the shared service
  // receives each tick, so this costs a second strip of bar and nothing else —
  // with one exception, noted at syncSecondaryGpu().
  readonly property bool secondaryVisible: {
    if (!service || secondaryMetric === "none") return false
    // Plenty of Omarchy machines run zram or no swap, and a discrete GPU is
    // hardly universal; either would otherwise sit in the bar as a strip that
    // never moves. Same reason the panel hides those rows outright.
    if (secondaryMetric === "swap") return service.swapTotal > 0
    if (secondaryMetric === "gpu") return service.hasGpu
    return true
  }
  readonly property real secondaryPercent: {
    if (!service) return 0
    if (secondaryMetric === "swap") return service.swapPercent
    if (secondaryMetric === "gpu") return service.gpuPercent
    return service.memPercent
  }
  readonly property var secondaryHistory: {
    if (!service) return []
    var series = secondaryMetric === "swap" ? service.swapUsedHistory
      : secondaryMetric === "gpu" ? service.gpuHistory
      : service.memHistory
    return series.slice(-barPoints)
  }
  // Swap history is kept in bytes rather than percent, so its graph scales to
  // the partition instead of to 100.
  readonly property real secondaryCeiling: secondaryMetric === "swap" && service ? service.swapTotal : 100
  // Memory and GPU turn urgent where the panel's meters do. Swap does not:
  // a half-full swap file is ordinary on a machine that has been up a while,
  // and the panel leaves that meter in the foreground colour for the same
  // reason.
  readonly property bool secondaryHot: secondaryMetric !== "swap" && secondaryPercent >= 90
  readonly property string secondaryLabel: secondaryMetric === "swap" ? "SWAP"
    : secondaryMetric === "gpu" ? "GPU" : "MEM"
  // Nerd font glyphs, the same vocabulary the bar's indicators already speak.
  // They caption the pair and only the pair: one percentage beside a graph on a
  // system monitor needs no caption, and adding one would widen the widget for
  // everyone who never asked for a second metric.
  //
  // Chosen by silhouette at 13px rather than by name. Material's md-memory is a
  // chip, indistinguishable from a CPU at this size and the whole reason the
  // caption exists; fa-memory is a DIMM stick and shares no outline with the
  // processor. oct-cpu rasterises cleaner than md-cpu_64_bit here.
  readonly property string cpuIcon: ""          // oct-cpu
  readonly property string secondaryIcon: secondaryMetric === "swap" ? "󰓡"   // md-swap_horizontal
    : secondaryMetric === "gpu" ? "󰾲"   // md-expansion_card_variant
    : ""  // fa-memory
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

  onServiceChanged: {
    syncService()
    syncSecondaryGpu()
  }
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
  Component.onCompleted: {
    syncService()
    syncSecondaryGpu()
  }

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
    if (!service) return
    if (opened) {
      service.releaseProcesses()
      service.releaseGpu()
    }
    if (_gpuHeldOn) {
      _gpuHeldOn.releaseGpu()
      _gpuHeldOn = null
    }
  }

  // The service the retain below was taken against, rather than a bare held
  // flag: the setting and the service arrive in either order, and a flag
  // cleared on the way past takes a second retain without giving one back.
  property var _gpuHeldOn: null

  // Memory and swap ride along in a sample the service already receives every
  // tick, so putting either in the bar starts nothing. GPU is the exception —
  // it costs a driver query per tick, so the sampler leaves it off until some
  // view asks for it. Choosing it here holds that reference for the life of the
  // widget rather than for the life of an open panel, which is the price of an
  // always-visible metric and is what the settings copy warns about.
  //
  // Keyed on the setting and not on secondaryVisible: hasGpu only becomes true
  // *after* sampling starts, so gating the retain on it would leave the strip
  // permanently hidden and the GPU permanently unpolled.
  function syncSecondaryGpu() {
    var wanted = secondaryMetric === "gpu" ? service : null
    if (_gpuHeldOn === wanted) return
    if (_gpuHeldOn) _gpuHeldOn.releaseGpu()
    if (wanted) wanted.retainGpu()
    _gpuHeldOn = wanted
  }

  onSecondaryMetricChanged: syncSecondaryGpu()

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
    // The glyphs caption the pair on a horizontal bar; the tooltip spells the
    // same thing out in words, and is the only identity a vertical bar carries.
    tooltipText: {
      if (!root.service || !root.service.ready) return "Task Manager"
      var parts = ["CPU " + Model.formatPercent(root.cpuPercent),
                   "MEM " + Model.formatPercent(root.service.memPercent)]
      if (root.secondaryVisible && root.secondaryMetric !== "mem") {
        parts.push(root.secondaryLabel + " " + Model.formatPercent(root.secondaryPercent))
      }
      return parts.join(" · ")
    }

    // Vertical bars have no room for a history graph, so they fall back to the
    // percentage alone — the same compromise the media widget makes.
    readonly property bool graphVisible: !vertical && root.barGraph !== "none"
    // Two strips at the single-metric width would very nearly double what the
    // widget takes out of the bar. Narrowing them means the pair costs about
    // half again as much as CPU alone, which is what makes this wearable on a
    // laptop panel that is already carrying a workspace list and a clock.
    readonly property real graphWidth: graphVisible ? Style.space(root.secondaryVisible ? 22 : 34) : 0

    // Measured from the content rather than recomputed: with a second strip
    // that arithmetic has to know about spacing, visibility and orientation
    // all at once, and the positioner already does.
    fixedWidth: vertical ? -1 : metrics.implicitWidth + Style.space(10)
    // One slot is sized for a single row of glyphs; stacked percentages need
    // the second row's worth of bar.
    fixedHeight: vertical
      ? (root.secondaryVisible ? metrics.implicitHeight + Style.space(6) : Style.bar.iconSlot)
      : -1

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.expand()
      else root.toggle()
    }

    // Captions are for telling two otherwise identical strips apart, so they
    // arrive with the second metric and leave with it. A vertical bar has room
    // for neither — it is already down to bare stacked numbers.
    readonly property bool iconsVisible: root.secondaryVisible && !vertical

    // One metric's caption, graph and percentage.
    component MetricStrip: Row {
      id: metric

      property string icon: ""
      property var series: []
      property real percent: 0
      property real ceiling: 100
      property bool hot: false

      spacing: Style.space(5)

      Sparkline {
        visible: button.graphVisible
        width: button.graphWidth
        height: Math.max(Style.space(9), button.barSize - Style.space(14))
        anchors.verticalCenter: parent.verticalCenter
        values: metric.series
        capacity: root.barPoints
        maxValue: metric.ceiling
        bars: root.barGraph === "bars"
        stroke: metric.hot ? button.activeColor : button.foreground
        lineWidth: 1
        fillOpacity: 0.22
        barGap: 1
      }

      Text {
        visible: button.iconsVisible && metric.icon !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: metric.icon
        // The caption runs hot with the reading it names, so a spike colours the
        // whole strip rather than leaving the glyph behind in the plain colour.
        color: metric.hot ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering
      }

      Text {
        visible: root.showPercent || button.vertical
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(metric.percent) + (button.vertical ? "" : "%")
        color: metric.hot ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering
      }
    }

    // CPU always leads and the second metric always follows, on every monitor
    // and in both orientations: a pair that swapped places by context would be
    // unreadable at this size.
    Grid {
      id: metrics
      anchors.centerIn: parent
      // Side by side along a horizontal bar. Stacked on a vertical one, which
      // has width for two digits and never for two strips — the same place the
      // graph itself already drops out.
      columns: button.vertical ? 1 : 2
      columnSpacing: Style.space(7)
      rowSpacing: Style.space(1)

      MetricStrip {
        icon: root.cpuIcon
        series: root.service ? root.service.cpuHistory.slice(-root.barPoints) : []
        percent: root.cpuPercent
        hot: root.cpuPercent >= 85
      }

      MetricStrip {
        visible: root.secondaryVisible
        icon: root.secondaryIcon
        series: root.secondaryHistory
        percent: root.secondaryPercent
        ceiling: root.secondaryCeiling
        hot: root.secondaryHot
      }
    }
  }

  IpcHandler {
    target: root.ipcTarget

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
