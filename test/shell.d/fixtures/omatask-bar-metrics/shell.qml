import QtQuick
import Quickshell
import qs.Commons

// The Task Manager bar widget, driven against a stub service, checking the
// always-visible metric pair: that a second reading actually reaches the bar
// without opening anything, that it comes out of the one shared sampler rather
// than a second one, that a widget on every monitor still shares that sampler,
// and that swap and GPU stay out of the bar on machines that have neither.
ShellRoot {
  id: root

  readonly property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")
  readonly property string rootPath: Quickshell.env("OMARCHY_PATH")
  readonly property string widgetUrl: Quickshell.env("OMARCHY_OMATASK_WIDGET_URL")
  readonly property string moduleName: "omarchy.omatask"

  property var failures: []
  property int checks: 0

  function fail(message) { failures.push(String(message)) }

  function check(condition, message) {
    checks = checks + 1
    if (!condition) fail(message)
  }

  function checkEqual(actual, expected, message) {
    checks = checks + 1
    if (actual !== expected) fail(message + " expected=" + expected + " actual=" + actual)
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function writeResult() {
    var payload = JSON.stringify({ ok: failures.length === 0, failures: failures, checks: checks })
    if (resultPath) {
      Quickshell.execDetached(["bash", "-lc", "printf '%s' " + shellQuote(payload) + " > " + shellQuote(resultPath)])
    }
  }

  property var component: null

  function widget(secondaryMetric) {
    var item = component.createObject(host, {
      bar: fakeBar,
      moduleName: root.moduleName,
      settings: { secondaryMetric: secondaryMetric, showPercent: true, barGraph: "sparkline" }
    })
    if (!item) fail("bar widget failed to instantiate for secondaryMetric=" + secondaryMetric)
    return item
  }

  Item { id: host }

  // One sampler, one service, however many bars ask for it — the shell caches
  // service instances per plugin id, and this stands in for that cache.
  QtObject {
    id: stubService

    property bool ready: true

    property real cpuPercent: 41
    property var cpuHistory: [10, 20, 30, 41]
    property int coreCount: 8
    property var cores: []
    property var loadAverage: [0.4, 0.3, 0.2]
    property bool hasCpuTemp: false
    property real cpuTemp: 0

    property real memPercent: 63
    property var memHistory: [50, 55, 60, 63]
    property real memTotal: 16 * 1024 * 1024 * 1024
    property real memUsed: 10 * 1024 * 1024 * 1024

    // Starts at zero the way a zram-only machine reports it.
    property real swapTotal: 0
    property real swapUsed: 0
    property real swapPercent: 0
    property var swapUsedHistory: [0, 0, 0, 0]

    // Starts absent the way a machine with no discrete GPU reports it, and the
    // way a hybrid machine reports it before anything asks for GPU sampling.
    property bool hasGpu: false
    property real gpuPercent: 0
    property var gpuHistory: [0, 0, 0, 0]
    property var primaryGpu: ({})
    property real gpuMemPercent: 0
    property real gpuMemTotal: 0
    property real gpuMemUsed: 0

    property var net: ({})
    property var disk: ({})
    property var processes: []
    property int processCount: 0
    property int threadCount: 0
    property real uptime: 0

    // Written by the widget's syncService(); present so those assignments land
    // somewhere instead of throwing.
    property int intervalSec: 2
    property int historyPoints: 60
    property int processLimit: 60
    property bool alertsEnabled: false
    property bool groupApps: true
    property string listMode: "processes"
    property string sortBy: "cpu"
    property bool sortDescending: true
    property var widgetSettings: ({})

    // GPU is refcounted because polling it costs a driver query per tick. The
    // counter is the point of the GPU half of this test.
    property int gpuHolders: 0
    property int processHolders: 0

    function retainGpu() { gpuHolders = gpuHolders + 1 }
    function releaseGpu() { gpuHolders = Math.max(0, gpuHolders - 1) }
    function retainProcesses() { processHolders = processHolders + 1 }
    function releaseProcesses() { processHolders = Math.max(0, processHolders - 1) }
    function killProcess(pid, signalName) {}
  }

  QtObject {
    id: mockShell
    property var bar: fakeBar
    property var barConfig: ({ position: "top" })
    property var shellConfig: ({ version: 1, idle: {}, plugins: [], bar: { layout: { left: [], center: [], right: [] } } })
    function firstPartyServiceFor(id) { return serviceFor(id) }
    function serviceFor(id) { return id === root.moduleName ? stubService : null }
    function summon(id, payloadJson) { return true }
    function hide(id) { return true }
    function toggle(id, payloadJson) { return true }
    function updateEntryInline(moduleName, settings) { return true }
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 26
    property string omarchyPath: root.rootPath
    property string fontFamily: "monospace"
    property color foreground: "white"
    property color background: "black"
    property color urgent: "red"
    property var shell: mockShell
    function run(command) {}
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function requestPopout(owner) {}
    function releasePopout(owner) {}
    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
  }

  Timer {
    interval: 1
    running: true
    repeat: false
    onTriggered: {
      root.component = Qt.createComponent(root.widgetUrl, Component.PreferSynchronous)
      if (root.component.status !== Component.Ready) {
        root.fail("bar widget failed to load: " + root.component.errorString())
        root.writeResult()
        return
      }

      var cpuOnly = root.widget("none")
      var withMemory = root.widget("mem")
      var withSwap = root.widget("swap")
      var withGpu = root.widget("gpu")

      // ---- both readings reach the bar, with nothing opened ----
      root.check(!cpuOnly.opened && !withMemory.opened, "the pair is readable without opening the panel")
      root.checkEqual(cpuOnly.secondaryVisible, false, "CPU alone stays the default")
      root.checkEqual(withMemory.secondaryVisible, true, "memory reaches the bar beside CPU")
      root.checkEqual(withMemory.secondaryPercent, stubService.memPercent, "the bar reads memory off the shared sample")
      root.checkEqual(withMemory.cpuPercent, stubService.cpuPercent, "CPU is still read off the same sample")
      root.checkEqual(withMemory.secondaryLabel, "MEM", "the tooltip names the second metric")

      // ---- the pair is captioned, and captions follow the metric ----
      root.checkEqual(cpuOnly.cpuIcon, "", "CPU wears the processor glyph")
      root.checkEqual(withMemory.secondaryIcon, "", "memory wears the memory glyph")
      root.checkEqual(withSwap.secondaryIcon, "󰓡", "swap wears its own glyph")
      root.checkEqual(withGpu.secondaryIcon, "󰾲", "GPU wears its own glyph")

      // ---- the second metric starts nothing ----
      root.checkEqual(stubService.gpuHolders, 1, "only the GPU metric asks for GPU polling")
      root.checkEqual(stubService.processHolders, 0, "a closed widget never asks for the process walk")
      root.checkEqual(withMemory.service, stubService, "the widget reads the shared service")

      // ---- a value nothing recognises reads as off ----
      var misspelled = root.widget("memm")
      root.checkEqual(misspelled.secondaryMetric, "none", "an unrecognised metric falls back to off")
      root.checkEqual(misspelled.secondaryVisible, false, "an unrecognised metric shows no second strip")
      misspelled.destroy()

      // ---- swap and GPU hide where they do not exist ----
      root.checkEqual(withSwap.secondaryVisible, false, "swap stays out of the bar with no swap configured")
      root.checkEqual(withGpu.secondaryVisible, false, "GPU stays out of the bar until a device is seen")

      stubService.swapTotal = 8 * 1024 * 1024 * 1024
      stubService.swapUsed = 2 * 1024 * 1024 * 1024
      stubService.swapPercent = 25
      stubService.hasGpu = true
      stubService.gpuPercent = 77

      root.checkEqual(withSwap.secondaryVisible, true, "swap appears once a swap device exists")
      root.checkEqual(withSwap.secondaryCeiling, stubService.swapTotal, "the swap graph scales to the partition, not to 100")
      root.checkEqual(withGpu.secondaryVisible, true, "GPU appears once sampling reports a device")
      root.checkEqual(withGpu.secondaryPercent, stubService.gpuPercent, "the bar reads GPU off the shared sample")

      Qt.callLater(function() {
        // ---- the pair costs bar width, but not double ----
        var single = cpuOnly.implicitWidth
        var pair = withMemory.implicitWidth
        root.check(isFinite(single) && single > 0, "the CPU-only widget has a finite width")
        root.check(pair > single, "a second metric takes more bar than one single=" + single + " pair=" + pair)
        root.check(pair < single * 2, "the pair stays compact rather than doubling the widget single=" + single + " pair=" + pair)

        // ---- a widget per monitor still shares one sampler ----
        var secondMonitor = root.widget("mem")
        Qt.callLater(function() {
          root.checkEqual(secondMonitor.service, cpuOnly.service, "every monitor's widget resolves the same service")
          root.checkEqual(secondMonitor.implicitWidth, withMemory.implicitWidth, "the compact pair measures the same on a second monitor")
          root.checkEqual(stubService.gpuHolders, 1, "a second monitor does not double the GPU hold")

          // ---- vertical bars stack rather than overflow ----
          fakeBar.vertical = true
          fakeBar.barSize = Style.bar.sizeVertical

          Qt.callLater(function() {
            root.checkEqual(cpuOnly.implicitHeight, Style.bar.iconSlot, "one metric still uses one slot on a vertical bar")
            root.check(withMemory.implicitHeight > Style.bar.iconSlot, "two metrics take a second line on a vertical bar")
            root.check(isFinite(withMemory.implicitHeight), "the stacked pair has a finite height")

            // ---- the GPU hold is given back ----
            withGpu.destroy()
            Qt.callLater(function() {
              root.checkEqual(stubService.gpuHolders, 0, "the GPU hold is released with the widget")
              cpuOnly.destroy()
              withMemory.destroy()
              withSwap.destroy()
              secondMonitor.destroy()
              root.writeResult()
            })
          })
        })
      })
    }
  }
}
