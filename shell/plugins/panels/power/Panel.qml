import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.power"
  ipcTarget: "omarchy.power"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the togglePercentage method below.
  manageIpc: false
  property var batteryInfo: ({})
  property var systemInfo: ({})
  // Power Hungry: top-consumer attribution, panel-only by design. The bar
  // pill is untouched — this answers a question you ask with the panel open.
  property real baseWatts: -1
  property var prevSnapshot: null
  property var topProcesses: []
  property var systemRows: []
  property var resourceSplits: null
  property var heat: ({})
  property var processColumns: []
  // Composition-bar gap geometry: a constant separator width and a constant
  // budget for the maximum segment count, so fills scale identically across
  // refreshes and resources regardless of how many segments are visible.
  readonly property real splitGap: Style.space(2)
  readonly property real splitGapBudget: Model.SPLIT_MAX_SEGMENTS * root.splitGap
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false
  readonly property bool showPercentage: setting("showPercentage", false) === true
  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  readonly property color batteryFillColor: {
    return root.bar ? root.bar.foreground : Color.foreground
  }

  // Cute agent-flavored phrases shown in the hero status line, rotated on a
  // timer so the panel feels alive when current is flowing (either direction).
  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]
  property int phraseIndex: 0

  // Whichever list is "active" given the current power state.
  readonly property var activePhrases: {
    if (fullyCharged) return []
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: {
    if (fullyCharged) return "Fully charged"
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  // Ink, not hue: RANK-NORMALIZED heat — foreground at even steps from
  // 1.0 (rank 1) down to 0.35 (last rank), and that value follows the
  // process everywhere (row mark, every bar segment). The system block/row
  // is WHITE (the machine itself). Magnitude lives in segment SIZE and the
  // numeric cells; ink's only job is ORDER. Identity is positional and by
  // label (operator decisions, 2026-08-29).
  function segmentInk(seg) {
    if (seg.kind === "system") return 1
    if (seg.ink !== undefined) return seg.ink
    return 0.35
  }

  function segmentColor(seg) {
    if (seg.kind === "rest") return Color.muted
    return root.bar ? root.bar.foreground : Color.foreground
  }

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
    if (!samplerProc.running) samplerProc.running = true
  }

  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") {
      // The rate is SIGNED by the source (negative while discharging); the
      // panel shows magnitude — direction lives in the state row. Strip the
      // sign here, the single write point, so the value never flickers.
      if (typeof next.rate === "string") next.rate = next.rate.replace(/^-/, "")
      batteryInfo = next
    } else systemInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  IpcHandler {
    target: "omarchy.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
    }
  }

  onBatteryPresentChanged: if (!batteryPresent) close()

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: systemProc
    command: ["omarchy-system-stats"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "system") }
  }

  // Power Hungry: battery flow + per-process jiffies, in one snapshot.
  Process {
    id: samplerProc
    command: [Qt.resolvedUrl("sampler.sh").toString().replace("file://", "")]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onSample(text) }
  }

  function onSample(raw) {
    var snap = Model.parseSnapshot(raw)
    if (!snap) return
    // NOTE: the sampler's watts feed the ATTRIBUTION here — the displayed
    // rate comes only from batteryProc (the stock smoothed source), written
    // in exactly one place. A second writer here (tried in v1) made the row
    // flip sign and value at 1 Hz — two reads of the same telemetry with
    // different conventions. Never two writers on one field.
    // A snapshot without a readable cputotal would diff nonsense percentages;
    // drop it and wait for the next one instead of storing it as a baseline.
    if (snap.cpuTotalJiffies === null) {
      prevSnapshot = null
      return
    }
    // Attribute watts whenever the BATTERY DEVICE is discharging — its own
    // claim, not the plug's (UPower.onBattery). In the marginal-adapter
    // wedge (adapter latched online, delivering nothing) the battery is the
    // power source, its sampled rate is real system draw, and attribution
    // is valid; while charging/full/pending the adapter input is unreadable
    // and per-process watts stay hidden. The basis lives in Model.wattsBasis
    // so the rule is one pure, tested function.
    var device = UPower.displayDevice
    var draw = Model.wattsBasis(device ? device.state : -1, UPowerDeviceState.Discharging, snap.watts)
    if (draw >= 0) {
      // Rolling idle floor: track the minimum draw, drifting up slowly so a
      // brightness change doesn't pin a stale base forever.
      if (baseWatts < 0) baseWatts = draw
      else if (draw < baseWatts) baseWatts = draw
      else baseWatts += (draw - baseWatts) * 0.02
    }
    if (prevSnapshot) {
      // The system row (everything unattributed: idle floor + tail) comes
      // first from the builder itself — folded there in operator review so
      // table, bars, and model exports share ONE system concept.
      topProcesses = Model.buildTopProcesses(prevSnapshot, snap, 5, draw, baseWatts)
    }
    // column set = the first row's cell metrics, in the builder's fixed
    // order (CPU, RAM, W discharging only, GPU when a source exists)
    var cols = []
    for (var ci = 0; ci < topProcesses.length; ci++) {
      if (topProcesses[ci].cells !== undefined && topProcesses[ci].cells.length > 0) {
        cols = topProcesses[ci].cells.map(function(c) { return c.metric })
        break
      }
    }
    processColumns = cols
    resourceSplits = Model.buildResourceSplits(prevSnapshot, snap, 5, draw, baseWatts)
    // ONE HEAT PER PROCESS (operator decision, 2026-08-29): a process's ink
    // is a single value — its share of the busiest process's CPU load,
    // 0.35..1.0 — and that value follows it EVERYWHERE: the table row's
    // mark, its segment in every composition bar. Like a heatmap of
    // processes: the system leads in white (the machine itself), the top
    // process glows brightest, and ink fades monotonically down the table's
    // rank. Segment SIZE still encodes each bar's own metric share; INK
    // encodes who the process is and how hot it runs. One writer: computed
    // here, once per refresh, onto plain numbers.
    // RANK-NORMALIZED (operator decision, 2026-08-29): ink steps EVENLY by
    // rank — rank 1 is white, the last rank sits at the 0.35 floor — not by
    // share ratio. How much hotter one process runs than another is already
    // encoded by segment SIZE; ink's only job is order.
    var heatMap = {}
    var cpuBar = resourceSplits.cpu
    // The cpu split is NULL until two samples exist (and stays null on AC
    // restarts) — a null bar means "no heat yet", not an error.
    if (cpuBar !== null && cpuBar !== undefined) {
      var comms = []
      for (var hi = 0; hi < cpuBar.length; hi++)
        if (cpuBar[hi].kind === "comm") comms.push(cpuBar[hi])
      for (var hj = 0; hj < comms.length; hj++) {
        var step = comms.length > 1 ? 0.65 / (comms.length - 1) : 0
        heatMap[comms[hj].key] = 1 - hj * step
      }
    }
    var allBars = [resourceSplits.cpu, resourceSplits.ram, resourceSplits.watts, resourceSplits.gpu]
    for (var bi = 0; bi < allBars.length; bi++) {
      var bar = allBars[bi]
      if (!bar) continue
      for (var si3 = 0; si3 < bar.length; si3++)
        if (bar[si3].kind === "comm") bar[si3].ink = heatMap[bar[si3].key] !== undefined ? heatMap[bar[si3].key] : 0.35
    }
    heat = heatMap
    // Vitals rows are rebuilt complete with their segments attached: a
    // property added to a plain JS object after the fact carries no change
    // signal, so a delegate that bound before the attach would stay null.
    var rows = Model.buildSystemRows(prevSnapshot, snap)
    for (var si = 0; si < rows.length; si++) {
      var segsFor = null
      var intensityFor = 0.45
      if (rows[si].label === "CPU") { segsFor = resourceSplits.cpu; intensityFor = resourceSplits.intensity.cpu }
      else if (rows[si].label === "RAM") { segsFor = resourceSplits.ram; intensityFor = resourceSplits.intensity.ram }
      else if (rows[si].label === "GPU") { segsFor = resourceSplits.gpu; intensityFor = resourceSplits.intensity.gpu }
      rows[si] = { label: rows[si].label, value: rows[si].value, meter: rows[si].meter, segments: segsFor, barIntensity: intensityFor }
    }
    systemRows = rows
    prevSnapshot = snap
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  // Power Hungry samples at panel cadence: 1 s while open, so the attribution
  // tracks what the machine is doing right now rather than a 5 s average.
  Timer { interval: 1000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  // Rotate the status phrase while the panel is open and we're in a
  // rotating state (charging or on battery). The text swap is wrapped in a
  // fade so the changeover reads as one organism rather than a hard cut.
  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // If we leave a rotating state mid-swap, halt the animation and snap back
  // to full opacity so "FULLY CHARGED" is legible immediately rather than
  // appearing dimmed.
  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        heroStatus.opacity = 1.0
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showPercentage && !vertical
      ? Math.round(root.batteryFraction * 100) + "% " + root.batteryIcon()
      : root.batteryIcon()
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) root.selectProfileByDelta(dx)
        else if (dy !== 0) root.selectProfileByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: battery icon · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.batteryIcon()
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Battery"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              textFormat: Text.PlainText
              text: root.heroStatusText.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.batteryInfo.percentage || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        // ---------- Battery progress bar ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryFillColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 220 } }

            // Subtle pulse while charging — visible signal that energy is flowing in.
            SequentialAnimation on opacity {
              running: root.charging && !root.fullyCharged && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: 950; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
            }
          }
        }

        // ---------- Stats ----------
        // Visibility is intentionally only gated by "we've ever loaded data" so
        // the section never collapses mid-transition. fullyCharged is *not* part
        // of the condition: UPower briefly reports FullyCharged on plug-in when
        // the battery sits above the charge-control start threshold, and we
        // refuse to flicker the whole panel for that ~1s window.
        Row {
          visible: root.batteryInfo.percentage !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "Battery size"; value: root.batteryInfo.size || "" }
            InfoPair { label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? "Charge limit" : (root.discharging ? "Time left" : "Time to full")
              value: root.chargeThresholdActive ? (root.batteryInfo.threshold || "-") : (root.batteryFlowIdle ? "-" : (root.batteryInfo.time || "—"))
            }
            InfoPair {
              label: root.chargeThresholdActive ? "Battery state" : (root.discharging ? "Discharging" : "Charging")
              value: root.chargeThresholdActive ? "Holding" : (root.batteryFull ? "-" : (root.batteryInfo.rate || ""))
            }
          }
        }

        // ---------- System vitals ----------
        // General system state, kin to the battery stats above; the
        // attribution section below answers "who is eating it". Rows come
        // from the same sampler snapshots as everything else, so vitals and
        // attribution can never disagree. Meters reuse the battery bar's
        // own idiom — a rounded track at foreground alpha with a foreground
        // fill — no new widget. There is deliberately no Draw row: total
        // draw is the stock pill's number (same sampler telemetry), and a
        // second copy of it here was removed in operator review.
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "SYSTEM"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.systemRows

            SplitBar {
              required property var modelData
              label: modelData.label
              value: modelData.value
              segments: modelData.segments !== undefined ? modelData.segments : null
              meter: modelData.meter
              barIntensity: modelData.barIntensity !== undefined ? modelData.barIntensity : 0.45
              fillColor: root.bar ? root.bar.foreground : Color.foreground
            }
          }
        }

        // ---------- Power Hungry: top consumers ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "POWER HUNGRY"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          // The attribution model as one bar, mirroring the table below:
          // the system block first (everything unattributed, in foreground —
          // the leading neutral segment the table's system row also wears),
          // then the top processes biggest-to-lightest in their table-row
          // colors. Discharging only — on AC the battery flow is charge
          // rate, not system draw, so there is no honest bar to draw.
          Rectangle {
            visible: root.resourceSplits !== null && root.resourceSplits.watts !== null
            width: column.width
            height: Style.space(6)
            radius: height / 2
            clip: true
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)

            Row {
              id: wattsSegmentRow
              anchors.fill: parent
              spacing: root.splitGap

              Repeater {
                model: root.resourceSplits !== null && root.resourceSplits.watts !== null ? root.resourceSplits.watts : []

                Rectangle {
                  required property var modelData
                  width: modelData.share * Math.max(0, wattsSegmentRow.width - root.splitGapBudget)
                  height: parent.height
                  color: root.segmentColor(modelData)
                  opacity: root.segmentInk(modelData)
                }
              }
            }
          }

          // Column headers, learned once: CPU / RAM / W (discharging only).
          // The column set is derived in onSample from the rows' own cells,
          // so the header can never drift from what renders beneath it.
          // Header on the same fixed grid as the rows: each label right-aligned
          // inside its column slot, matching where the values render below.
          Row {
            id: processHeader
            visible: root.processColumns.length > 0
            width: column.width

            TextMetrics {
              id: headerCommMetrics
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              text: "WWWWWWWWWWWWWWW"
            }

            Item {
              width: headerCommMetrics.advanceWidth + Style.space(16)
              height: Style.space(12)
            }

            Repeater {
              model: root.processColumns

              Item {
                required property var modelData
                width: (processHeader.width - headerCommMetrics.advanceWidth - Style.space(16)) / Math.max(1, root.processColumns.length)
                height: Style.space(12)

                Text {
                  text: parent.modelData
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  color: root.bar ? root.bar.foreground : Color.foreground
                  opacity: 0.8
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }
          }

          Repeater {
            model: root.topProcesses

            MetricRow {
              required property var modelData
              label: modelData.label
              cells: modelData.cells !== undefined ? modelData.cells : []
              columns: root.processColumns
              anchor: modelData.key === "system"
              commColor: root.bar ? root.bar.foreground : Color.foreground
              // The mark IS the process's heat — the same one-writer value
              // its bar segments use (root.heat), so mark and bars can
              // never disagree about a process.
              commInk: modelData.key === "system" ? 1
                : (root.heat[modelData.key] !== undefined ? root.heat[modelData.key] : 0.35)
            }
          }

          Text {
            visible: root.topProcesses.length === 0
            text: "warming up…"
            color: root.bar.foreground
            opacity: 0.5
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---------- Power profile picker ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POWER PROFILE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.profileIndex = index
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  // One graphic line per process on a FIXED grid, recalculated only on
  // basis change (column set) or panel width — never per sample. Comm
  // column: the identity mark in its own slot — foreground ink, since
  // identity is carried by the label and by row order (system leads;
  // processes descend by load) — plus a left-aligned label elided at
  // the kernel's 15-char comm cap (Model.COMM_MAX_CHARS, sized once via
  // TextMetrics). Metric cells: the remaining track split equally across
  // the section's column set, so every row lands in the same pixel columns
  // as the header. Value text is right-aligned INSIDE its fixed cell: the
  // same pixel column every refresh regardless of fill length, and fills
  // are capped short of the text so type never sits on a fill. No width
  // Behaviors anywhere — fills step at the 1 Hz cadence, geometry never
  // moves. Fixed decimals (pct one place, watts one place, RAM auto-unit
  // in the slot) keep digit-count changes absorbed by the right alignment.
  component MetricRow: Item {
    id: metricRow
    property string label: ""
    property var cells: []
    property var columns: []
    property bool anchor: false
    property color commColor: root.bar ? root.bar.foreground : Color.foreground
    property real commInk: 1

    width: column.width
    implicitHeight: Style.space(16)

    TextMetrics {
      id: commMetrics
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      text: "WWWWWWWWWWWWWWW"
    }

    Rectangle {
      id: commMark
      width: Style.space(3)
      height: Style.space(10)
      radius: width / 2
      x: 0
      anchors.verticalCenter: parent.verticalCenter
      color: metricRow.commColor
      opacity: metricRow.commInk
    }

    Text {
      id: rowLabel
      text: metricRow.label
      // mark(3) + 5 + label + 8 = the header's 16-unit comm gutter, so the
      // metric columns line up exactly beneath their headers
      x: commMark.width + Style.space(5)
      width: commMetrics.advanceWidth
      anchors.verticalCenter: parent.verticalCenter
      color: root.bar ? root.bar.foreground : Color.foreground
      opacity: 0.75
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Rectangle {
      id: cellTrack
      x: rowLabel.x + rowLabel.width + Style.space(8)
      width: parent.width - x
      height: parent.height
      radius: height / 3
      color: Qt.rgba((root.bar ? root.bar.foreground : Color.foreground).r,
                     (root.bar ? root.bar.foreground : Color.foreground).g,
                     (root.bar ? root.bar.foreground : Color.foreground).b, 0.08)

      Row {
        id: cellGrid
        anchors.fill: parent

        Repeater {
          model: metricRow.columns

          Item {
            id: cellSlot
            required property var modelData
            width: metricRow.columns.length > 0 ? cellGrid.width / metricRow.columns.length : cellGrid.width
            height: cellGrid.height

            // the cell for this column, when the row carries one
            readonly property var cellData: {
              for (var i = 0; i < metricRow.cells.length; i++)
                if (metricRow.cells[i].metric === cellSlot.modelData) return metricRow.cells[i]
              return null
            }

            Text {
              id: cellValue
              visible: cellSlot.cellData !== null
              text: cellSlot.cellData !== null ? cellSlot.cellData.value : ""
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              color: root.bar ? root.bar.foreground : Color.foreground
              opacity: 0.75
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Rectangle {
              visible: cellSlot.cellData !== null
              x: Style.space(2)
              y: Style.space(2)
              width: cellSlot.cellData !== null
                ? Math.max(0, Math.min(1, cellSlot.cellData.normalized)) * Math.max(0, parent.width - cellValue.implicitWidth - Style.space(10))
                : 0
              height: parent.height - Style.space(4)
              radius: height / 3
              color: root.bar ? root.bar.foreground : Color.foreground
              opacity: cellSlot.cellData !== null ? cellSlot.cellData.intensity : 0
            }
          }
        }
      }
    }
  }

  // A SYSTEM bar: one rounded track per resource with the label in the left
  // gutter and the value at the right edge. With segments the fill is the
  // composition (the table's colors: foreground system block first, then
  // comm hues; idle/available left as track), ramped by the resource's
  // utilization; without segments it is a single intensity-graded fill.
  component SplitBar: Item {
    id: splitBar
    property string label: ""
    property string value: ""
    property real meter: -1
    property real barIntensity: 0.45
    property var segments: null
    property color fillColor: root.bar ? root.bar.foreground : Color.foreground

    width: column.width
    implicitHeight: Style.space(16)

    Rectangle {
      id: splitTrack
      width: parent.width
      height: Style.space(16)
      radius: height / 3
      clip: true
      color: Qt.rgba(splitBar.fillColor.r, splitBar.fillColor.g, splitBar.fillColor.b, 0.08)

      Text {
        id: splitLabel
        text: splitBar.label
        x: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        color: root.bar ? root.bar.foreground : Color.foreground
        opacity: 0.65
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Rectangle {
        visible: splitBar.segments === null && splitBar.meter >= 0
        x: splitLabel.implicitWidth + Style.space(12)
        width: Math.max(0, Math.min(1, splitBar.meter)) * (splitTrack.width - x - splitValue.width - Style.space(10))
        y: Style.space(2)
        height: parent.height - Style.space(4)
        radius: height / 3
        color: splitBar.fillColor
        opacity: splitBar.barIntensity
      }

      Row {
        id: splitSegments
        visible: splitBar.segments !== null
        x: splitLabel.implicitWidth + Style.space(12)
        width: splitTrack.width - x - splitValue.width - Style.space(10)
        height: parent.height - Style.space(4)
        y: Style.space(2)
        spacing: root.splitGap
        opacity: splitBar.barIntensity

        Repeater {
          model: {
            var segs = splitBar.segments
            if (!segs) return []
            var drawn = []
            for (var i = 0; i < segs.length; i++)
              if (segs[i].kind !== "idle" && segs[i].kind !== "avail") drawn.push(segs[i])
            return drawn
          }

          Rectangle {
            required property var modelData
            width: modelData.share * Math.max(0, splitSegments.width - root.splitGapBudget)
            height: splitSegments.height
            color: root.segmentColor(modelData)
            opacity: root.segmentInk(modelData)
          }
        }
      }

      Text {
        id: splitValue
        text: splitBar.value
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
