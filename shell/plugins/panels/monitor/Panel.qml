import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.monitor"
  ipcTarget: "omarchy.monitor"
  manageIpc: false

  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the brightness + state methods below.
  property int brightnessPercent: 0
  property int pendingBrightnessPercent: 0
  property bool brightnessSetQueued: false
  property bool brightnessAvailable: false
  property string focusedMonitor: ""
  property var displays: []
  property int enabledDisplayCount: 0

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  // ---------------------------------------------------------------------
  // Arrangement + per-monitor selection and pending edits
  // ---------------------------------------------------------------------
  // Identity is desc:<description> (falling back to connector name), never
  // the raw connector name alone: matches Model.monitorIdentity and stays
  // valid across a DisplayLink reconnect that renumbers connectors.
  property string selectedIdentity: ""
  property var pendingChanges: ({})   // { identity: { enabled, mode, scale, transform, x, y } }

  readonly property var displayByIdentity: {
    var map = {}
    for (var i = 0; i < displays.length; i++) {
      var d = displays[i]
      if (d) map[Model.monitorIdentity(d)] = d
    }
    return map
  }

  readonly property var selectedDisplay: displayByIdentity[selectedIdentity] || null

  readonly property var arrangementDisplays: {
    var result = []
    for (var i = 0; i < displays.length; i++) {
      var d = displays[i]
      if (!d) continue
      var identity = Model.monitorIdentity(d)
      var pending = pendingChanges[identity] || {}
      result.push(Object.assign({}, d, {
        x: pending.x !== undefined ? pending.x : d.x,
        y: pending.y !== undefined ? pending.y : d.y,
        scale: pending.scale !== undefined ? pending.scale : d.scale,
        transform: pending.transform !== undefined ? pending.transform : d.transform,
        enabled: pending.enabled !== undefined ? pending.enabled : d.enabled
      }))
    }
    return result
  }

  readonly property var pendingDiff: Model.diffPending(displayByIdentity, pendingChanges)
  readonly property bool dirty: Model.isDirty(pendingDiff)

  function monitorValue(identity, field, fallback) {
    var pending = pendingChanges[identity]
    if (pending && pending[field] !== undefined) return pending[field]
    var live = displayByIdentity[identity]
    if (!live) return fallback
    if (field === "enabled") return live.enabled
    if (field === "mode") return live.currentMode
    if (field === "scale") return live.scale
    if (field === "transform") return live.transform
    if (field === "x") return live.x
    if (field === "y") return live.y
    return fallback
  }

  function setPendingField(identity, field, value) {
    var clone = {}
    var names = Object.keys(root.pendingChanges)
    for (var i = 0; i < names.length; i++) {
      var n = names[i]
      clone[n] = Object.assign({}, root.pendingChanges[n])
    }
    if (!clone[identity]) clone[identity] = {}
    clone[identity][field] = value
    root.pendingChanges = clone
  }

  function clearPending() {
    root.pendingChanges = {}
  }

  function selectMonitor(identity) {
    root.selectedIdentity = identity
  }

  function snapLogical(value) {
    return Math.round(Number(value) / 10) * 10
  }

  // ---------------------------------------------------------------------
  // Safe apply / preview / revert, through omarchy-monitor-arrange
  // ---------------------------------------------------------------------
  // "Apply" pushes the pending layout live (transient, via `arrange apply`)
  // and starts a preview countdown; "Keep" persists it to monitors.lua
  // (`arrange persist`), "Revert" re-applies the pre-change snapshot. An
  // unconfirmed preview auto-reverts so a bad layout can't strand the user.
  readonly property int previewSeconds: 12
  property bool previewActive: false
  property int previewRemaining: 0
  property var liveSnapshot: []
  property string statusText: ""

  function startApply() {
    if (!root.dirty) return
    root.liveSnapshot = Model.buildArrangeLayout(root.displays, {})
    var layout = Model.buildArrangeLayout(root.displays, root.pendingDiff)
    runArrange(arrangeApplyProc, "apply", layout)
  }

  function keepApplied() {
    var layout = Model.buildArrangeLayout(root.displays, root.pendingDiff)
    runArrange(arrangePersistProc, "persist", layout)
  }

  function revertPreview() {
    previewCountdown.stop()
    if (root.previewActive) runArrange(arrangeRevertProc, "apply", root.liveSnapshot)
    root.previewActive = false
    root.previewRemaining = 0
    root.clearPending()
  }

  function primaryAction() {
    if (root.previewActive) root.keepApplied()
    else root.startApply()
  }

  function secondaryAction() {
    if (root.previewActive) root.revertPreview()
    else root.clearPending()
  }

  function runArrange(proc, command, layout) {
    proc.command = ["bash", "-c", "omarchy-monitor-arrange " + command + " <<< \"$1\"", "--", JSON.stringify(layout)]
    if (!proc.running) proc.running = true
  }

  // ---------------------------------------------------------------------
  // Keyboard cursor model
  // ---------------------------------------------------------------------
  // Sections:
  //   "brightness" - single slider row, selectedIndex = -1 sentinel.
  //   "textsize"   - single slider row, selectedIndex = -1 sentinel.
  //   "canvas"     - arrangement tiles; only present with 2+ displays.
  //   "enable"/"mode"/"scale"/"rotation" - single rows for the selected
  //                  monitor; only present once a monitor is selected.
  //   "actions"    - Apply/Cancel (or Keep/Revert) footer, 2 entries.
  // Mouse hover on a target updates root state via the components' `hovered`
  // signal so keyboard cursor and pointer share one highlight.
  property string focusSection: "brightness"
  property int selectedIndex: -1
  property bool cursorActive: false

  // Text size slider — curated macOS-style notches (px). The panel snaps to
  // these stops; the CLI (omarchy-display-text-size) accepts any integer in range.
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  // While a change is in flight, the chosen stop index overrides the live
  // base-size so the knob doesn't snap back during the file round-trip. -1 =
  // no pending change; follow Style.font.baseSize.
  property int textSizePreviewIndex: -1

  // A text-size change reflows the whole panel (both font and spacing scale),
  // which slides rows under a stationary pointer and fires synthetic hover.
  // While true, hover is not allowed to hijack the keyboard focus section —
  // otherwise h/l on the text-size slider can jump focus to another row.
  property bool reflowingText: false
  function markReflowing() {
    root.reflowingText = true
    reflowSettle.restart()
  }

  readonly property var visibleSections: {
    var list = []
    if (brightnessAvailable) list.push("brightness")
    list.push("textsize")
    if (displays.length > 1) list.push("canvas")
    if (selectedDisplay) list.push("enable", "mode", "scale", "rotation")
    if (dirty || previewActive) list.push("actions")
    return list
  }

  function sectionCount(section) {
    if (section === "canvas") return displays.length
    if (section === "actions") return 2
    return 0  // brightness/textsize/enable/mode/scale/rotation are lone rows
  }

  function sectionIsSingleRow(section) {
    return section !== "canvas"
  }

  function sectionFirstIndex(section) {
    if (section === "brightness" || section === "textsize") return -1
    return 0
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var inSingleRow = sectionIsSingleRow(focusSection)
    var max = inSingleRow ? 0 : sectionCount(focusSection) - 1

    if (delta > 0) {
      if (!inSingleRow && selectedIndex < max) { selectedIndex = selectedIndex + 1; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionFirstIndex(focusSection)
      }
    } else {
      if (!inSingleRow && selectedIndex > 0) { selectedIndex = selectedIndex - 1; return }
      if (sIdx > 0) {
        var prev = sections[sIdx - 1]
        focusSection = prev
        // Coming up from below — land on the last navigable row of the prev
        // section, or its sentinel for single-row sections.
        selectedIndex = sectionIsSingleRow(prev) ? sectionFirstIndex(prev) : sectionCount(prev) - 1
      }
    }
  }

  // h/l: canvas walks tiles left-to-right by array order; actions walks
  // Apply/Cancel; everywhere else, no-op because adjustBrightness/
  // adjustTextSize handle horizontal motion on their own sliders.
  function moveCursorH(delta) {
    if (focusSection === "canvas" && displays.length > 0) {
      var next = selectedIndex + delta
      if (next < 0) next = 0
      if (next > displays.length - 1) next = displays.length - 1
      selectedIndex = next
      root.selectMonitor(Model.monitorIdentity(displays[selectedIndex]))
      return
    }
    if (focusSection === "actions") {
      selectedIndex = Math.max(0, Math.min(1, selectedIndex + delta))
    }
  }

  function adjustBrightness(delta) {
    if (focusSection !== "brightness") return
    if (!brightnessAvailable) return
    setBrightness(root.brightnessPercent + delta)
  }

  function activateCursor() {
    if (focusSection === "canvas" && selectedIndex >= 0 && selectedIndex < displays.length) {
      root.selectMonitor(Model.monitorIdentity(displays[selectedIndex]))
      return
    }
    if (focusSection === "enable" && selectedDisplay) {
      var identity = root.selectedIdentity
      root.setPendingField(identity, "enabled", !monitorValue(identity, "enabled", selectedDisplay.enabled))
      return
    }
    if (focusSection === "actions") {
      if (selectedIndex === 0) root.primaryAction()
      else if (selectedIndex === 1) root.secondaryAction()
    }
    // brightness/textsize: no separate action; the slider value is the action.
    // mode/scale/rotation: opened via click; no keyboard-activate shortcut yet.
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var count = sectionCount(focusSection)
    if (sectionIsSingleRow(focusSection)) {
      if (focusSection === "brightness" || focusSection === "textsize") selectedIndex = -1
      else if (selectedIndex < 0 || selectedIndex >= Math.max(1, count)) selectedIndex = 0
      return
    }
    if (count === 0) {
      var sIdx = sections.indexOf(focusSection)
      focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    if (selectedIndex > count - 1) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  // Keep the keyboard-focused row inside the viewport when the panel grows
  // taller than its allotted height (lots of displays). Mirrors audio's
  // ensureCursorVisible helper.
  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  function brightnessIpc(percent) {
    var value = Number(percent)
    root.setBrightness(value)
    return "got " + root.pendingBrightnessPercent
  }

  function stateIpc() {
    return JSON.stringify({
      brightness: root.brightnessPercent,
      brightnessAvailable: root.brightnessAvailable,
      focusedMonitor: root.focusedMonitor,
      displays: root.displays,
      pendingDiff: root.pendingDiff,
      dirty: root.dirty,
      previewActive: root.previewActive
    })
  }

  IpcHandler {
    target: "omarchy.monitor"

    function brightness(percent: string): string { return root.brightnessIpc(percent) }
    function state(): string { return root.stateIpc() }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  function setBrightness(value) {
    var percent = Model.clampBrightness(value)
    root.brightnessPercent = percent
    root.pendingBrightnessPercent = percent

    if (setBrightnessProc.running) {
      root.brightnessSetQueued = true
      return
    }

    root.brightnessSetQueued = false
    setBrightnessProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", root.focusedMonitor, percent + "%"]
    setBrightnessProc.running = true
  }

  function previewBrightness(value) {
    root.brightnessPercent = Model.clampBrightness(value)
    brightnessDebounce.restart()
  }

  function showBrightnessOsd(percent) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: "brightness",
      value: percent
    }))
  }

  // Playful mood-name for a given brightness percent. Bands intentionally
  // span ~10–20 points so casual tweaks change the label, while small
  // nudges within one band don't.
  function brightnessName(percent) {
    return Model.brightnessName(percent)
  }

  function updateDisplays(displaysJson) {
    var parsed = Model.parseExtendedDisplays(displaysJson)
    root.displays = parsed.displays
    root.enabledDisplayCount = parsed.enabledDisplayCount
    if ((!root.selectedIdentity || !root.displayByIdentity[root.selectedIdentity]) && parsed.displays.length > 0) {
      root.selectMonitor(Model.monitorIdentity(parsed.displays[0]))
    }
  }

  // ---- Text size (shell base font + GTK text-scaling, via one CLI) ----
  function nearestTextStop(px) {
    var best = 0
    var bestDist = 1e9
    for (var i = 0; i < textSizeStops.length; i++) {
      var d = Math.abs(textSizeStops[i] - px)
      if (d < bestDist) { bestDist = d; best = i }
    }
    return best
  }

  // Effective stop index: the pending choice while a change is in flight,
  // otherwise whatever Style's live base-size rounds to.
  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize)
  }

  // px shown in the header: the pending stop if any, else the true base-size
  // (which may be an off-notch value set from the CLI).
  function displayedTextPx() {
    return textSizePreviewIndex >= 0 ? textSizeStops[textSizePreviewIndex] : Style.font.baseSize
  }

  function setTextSize(px) {
    textScaleProc.command = ["omarchy-display-text-size", String(px)]
    if (!textScaleProc.running) textScaleProc.running = true
  }

  function adjustTextSize(deltaSteps) {
    var idx = currentTextIndex() + deltaSteps
    if (idx < 0) idx = 0
    if (idx > textSizeStops.length - 1) idx = textSizeStops.length - 1
    markReflowing()
    textSizePreviewIndex = idx
    setTextSize(textSizeStops[idx])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  // KeyboardPanel primes focus at open-time, so SUPER-bound IPC summons land
  // with j/k ready to navigate. Keep a default landing point, but don't paint
  // the cursor until hover or the first navigation key.
  onOpenedChanged: {
    if (opened) {
      refresh()
      focusSection = brightnessAvailable ? "brightness" : "textsize"
      selectedIndex = -1
      cursorActive = false
    }
  }

  onBrightnessAvailableChanged: clampCursor()
  onDisplaysChanged: clampCursor()
  onVisibleSectionsChanged: clampCursor()

  // Only poll while the panel is open; the bar glyph tracks monitor count via
  // Quickshell.screens, and open-time refresh + Component.onCompleted cover the
  // rest. External brightness changes are reflected whenever the panel is open.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: ["omarchy-monitor-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var brightness = String(lines[0] || "").trim()
        root.brightnessAvailable = brightness !== "unavailable" && brightness !== ""
        root.brightnessPercent = root.brightnessAvailable ? Math.max(0, Math.min(100, parseInt(brightness, 10))) : 0
        root.focusedMonitor = String(lines[5] || "").trim()
        // Line 9 (index 8) is the extended per-display shape the arrangement
        // canvas and detail controls need — description/serial identity,
        // position, scale, transform, mode. Lines 1-4/6 (internal/external
        // connector names, mirror state, legacy scale) aren't read here
        // since the extended shape already carries everything this panel
        // needs per display; they stay in omarchy-monitor-state's output
        // for older consumers.
        root.updateDisplays(String(lines[8] || "[]").trim())
      }
    }
  }

  Timer {
    id: brightnessDebounce
    interval: 180
    repeat: false
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    // Do NOT call refresh() after a brightness set completes. The local
    // brightnessPercent we just wrote is authoritative; re-reading via
    // `omarchy-brightness-display` races the hardware/driver and can
    // return an empty string, which the parser then coerces to 0 —
    // visible as a "bounce to zero" after h/l keypresses. External
    // brightness changes are still picked up by the 5s periodic refresh,
    // the open-time refresh, and Component.onCompleted.
    onRunningChanged: {
      if (running) return
      if (root.brightnessSetQueued) {
        root.setBrightness(root.pendingBrightnessPercent)
      }
    }
  }

  // Preview countdown: an applied-but-unconfirmed layout auto-reverts if the
  // user never taps Keep. Interval matches displaylink.service's observed
  // RestartUSec=5s crash/restart bounce plus margin, so a transient
  // DisplayLink drop during apply doesn't eat the whole confirm window.
  Timer {
    id: previewCountdown
    interval: 1000
    running: root.previewActive && root.previewRemaining > 0
    repeat: true
    onTriggered: {
      root.previewRemaining = Math.max(0, root.previewRemaining - 1)
      if (root.previewRemaining <= 0) root.revertPreview()
    }
  }

  Process {
    id: arrangeApplyProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: {
      if (running) return
      var res = Model.parseArrangeResult(arrangeApplyProc.stdout.text)
      if (res.success) {
        root.previewActive = true
        root.previewRemaining = root.previewSeconds
      } else {
        root.previewActive = false
        root.statusText = res.message
      }
    }
  }

  Process {
    id: arrangePersistProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: {
      if (running) return
      var res = Model.parseArrangeResult(arrangePersistProc.stdout.text)
      root.previewActive = false
      root.previewRemaining = 0
      if (res.success) root.clearPending()
      else root.statusText = res.message
      root.refresh()
    }
  }

  // Re-applies the pre-change snapshot on revert/timeout. A failure here
  // still clears the local preview state (handled by revertPreview's
  // caller) rather than get stuck showing a countdown that already hit
  // zero; the next refresh() reports whatever Hyprland actually settled on.
  Process {
    id: arrangeRevertProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.refresh()
  }

  // Applies text size via the CLI, which rewrites the shell override file;
  // Style picks the new base-size up through its own file watch, so there's
  // nothing to refresh here.
  Process {
    id: textScaleProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // Clears the hover-suppression flag once the reflow triggered by a text-size
  // change has settled.
  Timer {
    id: reflowSettle
    interval: 300
    repeat: false
    onTriggered: root.reflowingText = false
  }

  // Once Style's base-size catches up to the pending choice, drop the preview
  // so the slider tracks the live value again. The change itself reflows the
  // panel, so suppress hover for a beat while it lands.
  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      root.markReflowing()
      if (root.textSizePreviewIndex >= 0
          && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      if (!root.brightnessAvailable) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.setBrightness(root.brightnessPercent + wheel.steps * 5)
      root.showBrightnessOsd(root.brightnessPercent)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) {
          if (root.focusSection === "brightness") root.adjustBrightness(dx * 5)
          else if (root.focusSection === "textsize") root.adjustTextSize(dx)
          else root.moveCursorH(dx)
        }
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero: display icon · title/status ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: root.displays.length > 1 ? "󰍺" : "󰍹"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Display"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                id: heroLabel
                textFormat: Text.PlainText
                text: {
                  if (root.brightnessAvailable) {
                    return root.brightnessName(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent).toUpperCase()
                  }
                  return "FIXED BRIGHTNESS"
                }
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // ---------- Brightness ----------
          PanelSeparator {
            visible: root.brightnessAvailable
            foreground: root.bar.foreground
          }

          Column {
            visible: root.brightnessAvailable
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(brightnessHeader.implicitHeight, brightnessPercent.implicitHeight)

              PanelSectionHeader {
                id: brightnessHeader
                text: "BRIGHTNESS"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: brightnessPercent
                textFormat: Text.PlainText
                text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent) + "%"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: brightnessRow
              width: parent.width
              height: brightnessSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "brightness" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(brightnessRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: brightnessSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 1
                maximum: 100
                step: 1
                value: root.brightnessPercent
                integer: true
                onMoved: function(v) { root.previewBrightness(v) }
                onReleased: function(v) {
                  brightnessDebounce.stop()
                  root.setBrightness(v)
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "brightness"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Text size ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(textSizeHeader.implicitHeight, textSizePx.implicitHeight)

              PanelSectionHeader {
                id: textSizeHeader
                text: "TEXT SIZE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: textSizePx
                textFormat: Text.PlainText
                text: (textSizeSlider.dragging
                       ? root.textSizeStops[Math.round(textSizeSlider.liveValue)]
                       : root.displayedTextPx()) + "px"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: textSizeRow
              width: parent.width
              height: textSizeSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "textsize" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(textSizeRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: textSizeSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: root.textSizeStops.length - 1
                step: 1
                integer: true
                tickCount: root.textSizeStops.length
                value: root.currentTextIndex()
                onReleased: function(v) { root.setTextSize(root.textSizeStops[Math.round(v)]) }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "textsize"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Arrangement (hidden with only one display) ----------
          PanelSeparator {
            visible: root.displays.length > 1
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.displays.length > 1

            PanelSectionHeader {
              text: "ARRANGEMENT"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            CursorSurface {
              id: canvasSurface
              width: parent.width
              height: Style.space(104)
              hasCursor: root.cursorActive && root.focusSection === "canvas"
              foreground: root.bar.foreground
              outline: true
              current: root.focusSection === "canvas"

              // Keep bounds anchored to the live layout while dragging. If
              // they followed pending coordinates, the viewport would move
              // with the tile and make upward/leftward motion feel stuck.
              readonly property var bounds: Model.paddedBounds(Model.arrangementBounds(root.displays), 0.2)
              readonly property real canvasScale: Model.arrangementCanvasScale(
                bounds, width - Style.space(12), height - Style.space(12), Style.space(6))
              readonly property var scaledDisplays: Model.scaleArrangement(
                root.arrangementDisplays, bounds, width - Style.space(12), height - Style.space(12), Style.space(6), root.selectedIdentity)

              Rectangle {
                id: canvasRect
                anchors.fill: parent
                anchors.margins: Style.space(6)
                color: Style.hoverFillFor(root.bar.foreground, Color.accent)
                radius: Style.space(6)
                border.width: 0

                Repeater {
                  model: canvasSurface.scaledDisplays

                  Rectangle {
                    required property var modelData
                    required property int index

                    x: modelData.x
                    y: modelData.y
                    width: Math.max(Style.space(28), modelData.width)
                    height: Math.max(Style.space(18), modelData.height)
                    color: modelData.selected
                      ? Style.selectedFillFor(root.bar.foreground, Color.accent)
                      : Style.hoverFillFor(root.bar.foreground, Color.accent)
                    border.color: modelData.selected ? Color.accent : Qt.darker(root.bar.foreground, 1.6)
                    border.width: modelData.selected ? 2 : 1
                    radius: Style.space(4)
                    opacity: modelData.enabled ? 1.0 : 0.45

                    Text {
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: modelData.name
                      color: root.bar.foreground
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      elide: Text.ElideRight
                      horizontalAlignment: Text.AlignHCenter
                      width: parent.width - Style.space(4)
                    }

                    MouseArea {
                      id: tileMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                      property real startCanvasX: 0
                      property real startCanvasY: 0
                      property real startLogicalX: 0
                      property real startLogicalY: 0
                      property bool dragged: false

                      onPressed: function(mouse) {
                        dragged = false
                        var pos = mapToItem(canvasRect, mouse.x, mouse.y)
                        startCanvasX = pos.x
                        startCanvasY = pos.y
                        startLogicalX = root.monitorValue(modelData.identity, "x", 0)
                        startLogicalY = root.monitorValue(modelData.identity, "y", 0)
                        root.selectMonitor(modelData.identity)
                        root.cursorActive = true
                        root.focusSection = "canvas"
                        root.selectedIndex = index
                      }

                      onPositionChanged: function(mouse) {
                        if (!pressed) return
                        var pos = mapToItem(canvasRect, mouse.x, mouse.y)
                        var canvasDx = pos.x - startCanvasX
                        var canvasDy = pos.y - startCanvasY
                        if (Math.abs(canvasDx) > 2 || Math.abs(canvasDy) > 2) dragged = true
                        root.setPendingField(modelData.identity, "x",
                          root.snapLogical(startLogicalX + Model.logicalFromCanvas(canvasDx, canvasSurface.canvasScale)))
                        root.setPendingField(modelData.identity, "y",
                          root.snapLogical(startLogicalY + Model.logicalFromCanvas(canvasDy, canvasSurface.canvasScale)))
                      }

                      onReleased: function(mouse) {
                        if (!dragged) root.selectMonitor(modelData.identity)
                      }
                      onContainsMouseChanged: if (containsMouse) {
                        root.cursorActive = true
                        root.focusSection = "canvas"
                        root.selectedIndex = index
                      }
                    }
                  }
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "canvas"
                }
              }
            }
          }

          // ---------- Selected monitor: enable / resolution / scale / rotation ----------
          PanelSeparator {
            visible: !!root.selectedDisplay
            foreground: root.bar.foreground
          }

          Column {
            visible: !!root.selectedDisplay
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: root.selectedDisplay
                ? (root.selectedDisplay.name + (root.selectedDisplay.description ? " · " + root.selectedDisplay.description : "")).toUpperCase()
                : "DISPLAY"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            // Enabled
            CursorSurface {
              id: enableRow
              width: parent.width
              height: Style.space(22) + Style.spacing.xl
              hasCursor: root.cursorActive && root.focusSection === "enable"
              foreground: root.bar.foreground
              outline: true

              Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(8)

                Text {
                  text: "Enabled"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  width: parent.width - Style.space(22)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.selectedDisplay && root.monitorValue(root.selectedIdentity, "enabled", root.selectedDisplay.enabled) ? "󰄬" : ""
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.subtitle
                  width: Style.space(14)
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.focusSection = "enable"
                  root.selectedIndex = -1
                }
                onClicked: {
                  if (!root.selectedDisplay) return
                  var current = root.monitorValue(root.selectedIdentity, "enabled", root.selectedDisplay.enabled)
                  if (current && root.enabledDisplayCount <= 1) return
                  root.setPendingField(root.selectedIdentity, "enabled", !current)
                }
              }
            }

            // Resolution
            CursorSurface {
              id: modeRow
              width: parent.width
              height: Style.space(22) + Style.spacing.xl
              hasCursor: root.cursorActive && root.focusSection === "mode"
              foreground: root.bar.foreground
              outline: true

              Text {
                text: "Resolution"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
              }

              // Equal-width dropdowns: mode/scale/rotation all share this
              // literal width rather than sizing to their own content, so
              // the three rows line up.
              Dropdown {
                id: modeDropdown
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(170)
                showLabel: false
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                hasCursor: modeRow.hasCursor
                enabled: root.selectedDisplay && (root.selectedDisplay.availableModes || []).length > 0
                options: root.selectedDisplay
                  ? Model.modeOptions(root.selectedDisplay.availableModes || [], root.selectedDisplay.currentMode, 6)
                  : []
                value: root.selectedDisplay
                  ? root.monitorValue(root.selectedIdentity, "mode", root.selectedDisplay.currentMode)
                  : ""
                onChanged: function(mode) {
                  if (!root.selectedDisplay) return
                  root.setPendingField(root.selectedIdentity, "mode", mode)
                  // Dropdown owns `value` once selected, which breaks this
                  // binding — restore it so the row keeps tracking pending/
                  // live state (e.g. after Cancel or selecting another tile).
                  modeDropdown.value = Qt.binding(function() {
                    return root.selectedDisplay
                      ? root.monitorValue(root.selectedIdentity, "mode", root.selectedDisplay.currentMode)
                      : ""
                  })
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "mode"
                  root.selectedIndex = -1
                }
              }
            }

            // Scale
            CursorSurface {
              id: scaleRow
              width: parent.width
              height: Style.space(22) + Style.spacing.xl
              hasCursor: root.cursorActive && root.focusSection === "scale"
              foreground: root.bar.foreground
              outline: true

              Text {
                text: "Scale"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
              }

              Dropdown {
                id: scaleDropdown
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(170)
                showLabel: false
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                hasCursor: scaleRow.hasCursor
                enabled: !!root.selectedDisplay

                readonly property var currentMode: root.selectedDisplay
                  ? Model.parseMode(root.monitorValue(root.selectedIdentity, "mode", root.selectedDisplay.currentMode))
                  : { width: 0, height: 0 }

                options: {
                  if (!root.selectedDisplay) return []
                  var presets = ["1", "1.25", "1.6", "2", "3", "4"]
                  var scales = Model.availableScales(presets, currentMode.width, currentMode.height)
                  return scales.map(function(s) {
                    return { value: s, label: Model.cleanScale(s, currentMode.width, currentMode.height) + "x" }
                  })
                }
                value: root.selectedDisplay
                  ? String(root.monitorValue(root.selectedIdentity, "scale", root.selectedDisplay.scale))
                  : ""
                onChanged: function(scale) {
                  if (!root.selectedDisplay) return
                  root.setPendingField(root.selectedIdentity, "scale", scale)
                  scaleDropdown.value = Qt.binding(function() {
                    return root.selectedDisplay
                      ? String(root.monitorValue(root.selectedIdentity, "scale", root.selectedDisplay.scale))
                      : ""
                  })
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "scale"
                  root.selectedIndex = -1
                }
              }
            }

            // Rotation
            CursorSurface {
              id: rotationRow
              width: parent.width
              height: Style.space(22) + Style.spacing.xl
              hasCursor: root.cursorActive && root.focusSection === "rotation"
              foreground: root.bar.foreground
              outline: true

              Text {
                text: "Rotation"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
              }

              Dropdown {
                id: rotationDropdown
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(170)
                showLabel: false
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                hasCursor: rotationRow.hasCursor
                enabled: !!root.selectedDisplay
                options: [
                  { value: "0", label: "0°" },
                  { value: "1", label: "90°" },
                  { value: "2", label: "180°" },
                  { value: "3", label: "270°" }
                ]
                value: root.selectedDisplay
                  ? String(root.monitorValue(root.selectedIdentity, "transform", root.selectedDisplay.transform))
                  : "0"
                onChanged: function(transform) {
                  if (!root.selectedDisplay) return
                  root.setPendingField(root.selectedIdentity, "transform", parseInt(transform, 10))
                  rotationDropdown.value = Qt.binding(function() {
                    return root.selectedDisplay
                      ? String(root.monitorValue(root.selectedIdentity, "transform", root.selectedDisplay.transform))
                      : "0"
                  })
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "rotation"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Apply / Cancel (relabels to Keep / Revert mid-preview) ----------
          PanelSeparator {
            visible: root.dirty || root.previewActive
            foreground: root.bar.foreground
          }

          Column {
            visible: root.dirty || root.previewActive
            width: parent.width
            spacing: Style.space(8)

            Text {
              visible: root.statusText !== "" && !root.previewActive
              width: parent.width
              text: root.statusText
              color: Color.accent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            Row {
              width: parent.width
              spacing: Style.spacing.sm

              Button {
                text: root.previewActive ? "Keep" : "Apply"
                fontSize: Style.font.body
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.md
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                hasCursor: root.cursorActive && root.focusSection === "actions" && root.selectedIndex === 0
                onHovered: function(isHovered) {
                  if (!isHovered) return
                  root.cursorActive = true
                  root.focusSection = "actions"
                  root.selectedIndex = 0
                }
                onClicked: root.primaryAction()
              }

              Button {
                text: root.previewActive ? ("Revert (" + root.previewRemaining + "s)") : "Cancel"
                fontSize: Style.font.body
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.md
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                hasCursor: root.cursorActive && root.focusSection === "actions" && root.selectedIndex === 1
                onHovered: function(isHovered) {
                  if (!isHovered) return
                  root.cursorActive = true
                  root.focusSection = "actions"
                  root.selectedIndex = 1
                }
                onClicked: root.secondaryAction()
              }
            }
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }
        }
      }
    }
  }
}
