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
  property string internalMonitor: ""
  property string externalMonitor: ""
  property string focusedMonitor: ""
  property bool internalEnabled: false
  property bool mirrorEnabled: false
  property string monitorScale: ""
  property var displays: []
  property int enabledDisplayCount: 0
  property var layoutMonitors: []
  property bool externalConnected: false
  property bool clamshell: false
  property bool internalOn: false
  property bool mirrorOn: false
  property string layoutError: ""
  property bool layoutReady: false
  property bool layoutReadOnly: false
  property bool keepLayoutError: false
  property bool dragging: false
  property string placeTarget: ""
  readonly property string layoutHelper: "omarchy-hyprland-monitor-layout"

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  // Cursor model shared by keyboard and mouse. Sections:
  //   "brightness" - single slider row, selectedIndex = -1 sentinel
  //                  (mirrors Audio's slider rows). Only present if a
  //                  controllable backlight was detected.
  //   "scale"      - 6 Button scale presets; treated as a single
  //                  horizontal row from j/k's perspective. h/l moves
  //                  between presets, identical to bluetooth's header.
  // Mouse hover on a target updates root state via the components' `hovered`
  // signal so keyboard cursor and pointer share one highlight.
  readonly property var scalePresets: ["1", "1.25", "1.6", "2", "3", "4"]
  readonly property var scaleValues: {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.availableScales(scalePresets, display.width, display.height)
    }
    return scalePresets
  }
  property string focusSection: "scale"
  property int selectedIndex: 0
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
    list.push("scale")
    return list
  }

  function sectionCount(section) {
    if (section === "brightness") return 0  // only the slider sentinel at -1
    if (section === "textsize") return 0    // slider sentinel at -1, like brightness
    if (section === "scale") return scaleValues.length
    return 0
  }

  function sectionIsSingleRow(section) {
    // brightness and text size are lone sliders; scale presets sit horizontally.
    return section === "brightness" || section === "textsize" || section === "scale"
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

  // h/l: in scale section, walks the preset row; everywhere else, no-op
  // because adjustBrightness handles horizontal motion on the brightness
  // slider.
  function moveCursorH(delta) {
    if (focusSection !== "scale") return
    var next = selectedIndex + delta
    if (next < 0) next = 0
    if (next > scaleValues.length - 1) next = scaleValues.length - 1
    selectedIndex = next
  }

  function adjustBrightness(delta) {
    if (focusSection !== "brightness") return
    if (!brightnessAvailable) return
    setBrightness(root.brightnessPercent + delta)
  }

  function activateCursor() {
    if (focusSection === "scale" && selectedIndex >= 0 && selectedIndex < scaleValues.length) {
      setScale(scaleValues[selectedIndex])
      return
    }
    // brightness: no separate action; the slider value is the action.
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
      // brightness/text size use the -1 sentinel; scale clamps into the presets.
      if (focusSection === "brightness" || focusSection === "textsize") selectedIndex = -1
      else if (selectedIndex < 0 || selectedIndex >= count) selectedIndex = 0
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
      scale: root.monitorScale,
      displays: root.displays
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
    refreshLayout()
  }

  function refreshLayout() {
    if (root.dragging) return
    if (!layoutProc.running) layoutProc.running = true
  }

  function applyLayoutFlags(obj) {
    root.layoutMonitors = obj.monitors || []
    root.externalConnected = obj.externalConnected === true
    root.clamshell = obj.clamshell === true
    root.internalOn = obj.internalOn === true
    root.mirrorOn = obj.mirrorOn === true
    root.layoutReady = true
    root.layoutReadOnly = false
    if (root.keepLayoutError)
      root.keepLayoutError = false
    else
      root.layoutError = ""
  }

  function runStock(bin, action) {
    actionProc.command = [bin, action]
    if (!actionProc.running) actionProc.running = true
  }

  function enabledLayoutMonitors() {
    var out = []
    for (var i = 0; i < layoutMonitors.length; i++) {
      if (layoutMonitors[i] && layoutMonitors[i].enabled) out.push(layoutMonitors[i])
    }
    return out
  }

  function disabledLayoutMonitors() {
    var out = []
    for (var i = 0; i < layoutMonitors.length; i++) {
      if (layoutMonitors[i] && !layoutMonitors[i].enabled) out.push(layoutMonitors[i])
    }
    return out
  }

  function toRect(m) {
    var size = Model.layoutSize(m.width, m.height, m.scale)
    return { name: m.name, x: m.x, y: m.y, w: size.w, h: size.h }
  }

  function canvasItems() {
    var enabled = enabledLayoutMonitors()
    var items = []
    for (var i = 0; i < enabled.length; i++) {
      var m = enabled[i]
      var size = Model.layoutSize(m.width, m.height, m.scale)
      items.push({
        output: m.name,
        posX: m.x,
        posY: m.y,
        layoutW: size.w,
        layoutH: size.h,
        modeW: m.width,
        modeH: m.height,
        scaleLabel: m.scale,
        focused: m.focused === true
      })
    }
    return items
  }

  function arrangementSide() {
    var list = canvasItems()
    if (list.length < 2) return ""
    var moved = null
    var other = null
    var i
    if (root.placeTarget) {
      for (i = 0; i < list.length; i++) {
        if (list[i].output === root.placeTarget) moved = list[i]
        else if (!other) other = list[i]
      }
    }
    if (!moved) {
      moved = list[0]
      other = list[1]
    }
    if (!other) {
      for (i = 0; i < list.length; i++) {
        if (list[i].output !== moved.output) {
          other = list[i]
          break
        }
      }
    }
    if (!moved || !other) return ""
    var cx = moved.posX + moved.layoutW / 2
    var cy = moved.posY + moved.layoutH / 2
    if (cy >= other.posY + other.layoutH) return "bottom"
    if (cy <= other.posY) return "top"
    if (cx >= other.posX + other.layoutW) return "right"
    if (cx <= other.posX) return "left"
    return ""
  }

  function sideCaption(side) {
    if (side === "left") return "LEFT"
    if (side === "right") return "RIGHT"
    if (side === "top") return "ABOVE"
    if (side === "bottom") return "BELOW"
    return ""
  }

  function commitDrag(name, x, y) {
    var enabled = enabledLayoutMonitors()
    if (enabled.length <= 1 || root.layoutReadOnly) {
      root.dragging = false
      return
    }
    var moved = null
    var current = null
    var others = []
    for (var i = 0; i < enabled.length; i++) {
      var r = toRect(enabled[i])
      if (enabled[i].name === name) {
        current = { x: r.x, y: r.y }
        r.x = x
        r.y = y
        moved = r
      } else {
        others.push(r)
      }
    }
    if (!moved || !others.length) {
      root.dragging = false
      return
    }
    var snapped = Model.snapWindows(moved, others)
    if (!snapped || (current && snapped.x === current.x && snapped.y === current.y)) {
      root.dragging = false
      return
    }
    applySnapped(name, snapped.x, snapped.y)
  }

  function applySnapped(name, x, y) {
    var next = []
    var payload = { monitors: [] }
    for (var j = 0; j < layoutMonitors.length; j++) {
      var item = layoutMonitors[j]
      var nx = item.name === name ? x : item.x
      var ny = item.name === name ? y : item.y
      next.push({
        name: item.name,
        width: item.width,
        height: item.height,
        x: nx,
        y: ny,
        scale: item.scale,
        refreshRate: item.refreshRate,
        enabled: item.enabled,
        focused: item.focused,
        internal: item.internal
      })
      if (item.enabled)
        payload.monitors.push({ name: item.name, x: nx, y: ny })
    }
    root.layoutMonitors = next
    applyLayoutProc.running = false
    applyLayoutProc.command = [root.layoutHelper, "apply", JSON.stringify(payload)]
    applyLayoutProc.running = true
  }

  function placeBeside(side) {
    var args = [root.layoutHelper, "place"]
    if (root.placeTarget) args.push(root.placeTarget)
    args.push(side)
    applyLayoutProc.command = args
    if (!applyLayoutProc.running) applyLayoutProc.running = true
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

  function normalizeScale(scale) {
    return Model.normalizeScale(scale)
  }

  function activeScaleIndex() {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.matchingScaleIndex(scaleValues, monitorScale, display.width, display.height)
    }
    return -1
  }

  function effectiveScale(scale) {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.cleanScale(scale, display.width, display.height)
    }
    return normalizeScale(scale)
  }

  // Playful mood-name for a given brightness percent. Bands intentionally
  // span ~10–20 points so casual tweaks change the label, while small
  // nudges within one band don't.
  function brightnessName(percent) {
    return Model.brightnessName(percent)
  }

  function updateDisplays(displaysJson) {
    var parsed = Model.parseDisplays(displaysJson)
    root.displays = parsed.displays
    root.enabledDisplayCount = parsed.enabledDisplayCount
  }

  function toggleDisplay(name, enabled) {
    if (!name) return
    if (enabled && root.enabledDisplayCount <= 1) return

    actionProc.command = ["hyprctl", "keyword", "monitor", name + (enabled ? ",disable" : ",preferred,auto,auto")]
    if (!actionProc.running) actionProc.running = true
  }

  function setScale(scale) {
    actionProc.command = ["bash", "-c", "omarchy-hyprland-monitor-scaling " + scale]
    if (!actionProc.running) actionProc.running = true
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

  Component.onCompleted: {
    refresh()
    layoutMissingCheck.start()
  }

  // KeyboardPanel primes focus at open-time, so SUPER-bound IPC summons land
  // with j/k ready to navigate. Keep a default landing point, but don't paint
  // the cursor until hover or the first navigation key.
  onOpenedChanged: {
    if (opened) {
      refresh()
      if (brightnessAvailable) {
        focusSection = "brightness"
        selectedIndex = -1
      } else {
        focusSection = "scale"
        selectedIndex = 0
      }
      cursorActive = false
    }
  }

  onBrightnessAvailableChanged: clampCursor()
  onDisplaysChanged: clampCursor()
  onScaleValuesChanged: clampCursor()
  onVisibleSectionsChanged: clampCursor()

  // Only poll while the panel is open; the bar glyph tracks monitor count via
  // Quickshell.screens, and open-time refresh + Component.onCompleted cover the
  // rest. External brightness changes are reflected whenever the panel is open.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: {
      root.refresh()
      root.refreshLayout()
    }
  }

  Timer {
    id: layoutMissingCheck
    interval: 200
    repeat: false
    onTriggered: {
      if (!root.layoutReady && root.layoutError === "") {
        root.layoutError = "layout helper missing"
        root.layoutReadOnly = true
      }
    }
  }

  Process {
    id: layoutProc
    command: [root.layoutHelper, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.applyLayoutFlags(JSON.parse(String(text || "{}")))
        } catch (e) {
          root.layoutError = "layout helper failed"
          root.layoutReadOnly = true
        }
      }
    }
    onExited: function(code) {
      if (code !== 0 && !root.layoutReady) {
        root.layoutError = "layout helper missing"
        root.layoutReadOnly = true
      }
    }
  }

  Process {
    id: applyLayoutProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var obj = JSON.parse(String(text || "{}"))
          if (obj.monitors) root.applyLayoutFlags(obj)
        } catch (e) {
          if (!root.layoutError)
            root.layoutError = "layout helper failed"
          root.keepLayoutError = true
          root.refreshLayout()
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err) {
          root.layoutError = err
          root.keepLayoutError = true
        }
      }
    }
    onExited: function(code) {
      root.dragging = false
      if (code !== 0) {
        root.keepLayoutError = true
        root.refreshLayout()
      }
    }
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
        root.internalMonitor = String(lines[1] || "").trim()
        root.externalMonitor = String(lines[2] || "").trim()
        root.internalEnabled = String(lines[3] || "").trim() !== ""
        root.mirrorEnabled = String(lines[4] || "").trim() === root.externalMonitor && root.externalMonitor !== ""
        root.focusedMonitor = String(lines[5] || "").trim()
        root.monitorScale = root.normalizeScale(String(lines[6] || "").trim())
        root.updateDisplays(String(lines[7] || "[]").trim())
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

  Process {
    id: actionProc
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
    contentWidth: panel.fittedContentWidth(Style.space(Quickshell.screens.length > 1 ? 520 : 380))
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
          else if (root.focusSection === "scale") root.moveCursorH(dx)
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
          value: panelColumn.implicitHeight > scrollArea.height && !root.dragging
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

          // ---------- Scale ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: Math.max(scaleHeader.implicitHeight, scaleMonitor.implicitHeight)

              PanelSectionHeader {
                id: scaleHeader
                text: "SCALE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              // Name the monitor SCALE targets, since it only applies to the
              // focused one.
              Text {
                id: scaleMonitor
                text: root.focusedMonitor
                // Only worth naming when more than one display is in play.
                visible: root.focusedMonitor !== "" && root.enabledDisplayCount > 1
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Grid {
              id: scaleRow
              width: parent.width
              columns: root.scaleValues.length
              spacing: Style.spacing.xs

              readonly property real cellWidth: root.scaleValues.length > 0
                ? (width - spacing * (columns - 1)) / columns
                : 0

              Repeater {
                model: root.scaleValues

                ScalePill {
                  required property string modelData
                  required property int index

                  scaleValue: modelData
                  scaleIndex: index
                  width: scaleRow.cellWidth
                }
              }
            }
          }

          PanelSeparator {
            foreground: root.bar.foreground
          }

          Text {
            visible: root.layoutError !== ""
            width: parent.width
            text: root.layoutError
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            StatusChip {
              label: root.externalConnected ? "EXT · connected" : "EXT · none"
              clickable: false
            }
            StatusChip {
              label: root.clamshell ? "CLAM · on" : "CLAM · off"
              clickable: false
            }
            StatusChip {
              label: root.internalOn ? "INT · on" : "INT · off"
              clickable: true
              onActivated: root.runStock("omarchy-hyprland-monitor-internal", "toggle")
            }
            StatusChip {
              label: root.mirrorOn ? "MIRROR · on" : "MIRROR · off"
              clickable: true
              onActivated: root.runStock("omarchy-hyprland-monitor-internal-mirror", "toggle")
            }
          }

          Text {
            width: parent.width
            visible: canvasHost.canvasList.length > 1
            text: root.sideCaption(root.arrangementSide())
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            width: parent.width
            visible: Quickshell.screens.length > 1
            text: "Drag a display to rearrange"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item {
            id: canvasHost
            width: parent.width
            height: Style.space(280)
            clip: true
            readonly property var canvasList: root.canvasItems()
            readonly property var bounds: {
              var list = canvasList
              if (!list.length) return { x: 0, y: 0, w: 1, h: 1 }
              var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9
              var padX = 0
              var padY = 0
              for (var i = 0; i < list.length; i++) {
                var r = list[i]
                if (r.posX < minX) minX = r.posX
                if (r.posY < minY) minY = r.posY
                if (r.posX + r.layoutW > maxX) maxX = r.posX + r.layoutW
                if (r.posY + r.layoutH > maxY) maxY = r.posY + r.layoutH
                if (r.layoutW > padX) padX = r.layoutW
                if (r.layoutH > padY) padY = r.layoutH
              }
              padX = Math.round(padX * 0.55)
              padY = Math.round(padY * 0.55)
              return { x: minX - padX, y: minY - padY, w: Math.max(1, maxX - minX + padX * 2), h: Math.max(1, maxY - minY + padY * 2) }
            }
            readonly property real fit: Math.min(width / bounds.w, height / bounds.h) * 0.92

            Repeater {
              model: canvasHost.canvasList.length
              CursorSurface {
                id: tile
                required property int index
                readonly property var mon: canvasHost.canvasList[index]
                readonly property real baseX: mon ? (mon.posX - canvasHost.bounds.x) * canvasHost.fit + (canvasHost.width - canvasHost.bounds.w * canvasHost.fit) / 2 : 0
                readonly property real baseY: mon ? (mon.posY - canvasHost.bounds.y) * canvasHost.fit + (canvasHost.height - canvasHost.bounds.h * canvasHost.fit) / 2 : 0
                property real dragDx: 0
                property real dragDy: 0

                width: mon ? mon.layoutW * canvasHost.fit : 0
                height: mon ? mon.layoutH * canvasHost.fit : 0
                x: baseX + (drag.active ? drag.translation.x : 0)
                y: baseY + (drag.active ? drag.translation.y : 0)
                visible: !!mon
                foreground: root.bar.foreground
                fill: Style.hoverFillFor(root.bar.foreground, Color.accent)
                currentFill: Style.selectedFillFor(root.bar.foreground, Color.accent)
                current: !!mon && (mon.focused || root.placeTarget === mon.output)
                hasCursor: drag.active
                bordered: true

                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(2)
                  width: Math.max(0, parent.width - Style.space(12))

                  Text {
                    text: String(tile.index + 1)
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                  }

                  Text {
                    text: tile.mon ? tile.mon.output : ""
                    color: Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.2
                    elide: Text.ElideRight
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                  }
                }

                DragHandler {
                  id: drag
                  enabled: canvasHost.canvasList.length > 1 && !root.layoutReadOnly && !!tile.mon
                  target: null
                  acceptedButtons: Qt.LeftButton
                  grabPermissions: PointerHandler.CanTakeOverFromAnything
                  onTranslationChanged: {
                    if (!active) return
                    tile.dragDx = translation.x
                    tile.dragDy = translation.y
                  }
                  onActiveChanged: {
                    if (!tile.mon) return
                    if (active) {
                      tile.dragDx = 0
                      tile.dragDy = 0
                      root.dragging = true
                      root.placeTarget = tile.mon.output
                      return
                    }
                    var dx = tile.dragDx
                    var dy = tile.dragDy
                    if (dx === 0 && dy === 0) {
                      dx = translation.x
                      dy = translation.y
                    }
                    var layoutX = tile.mon.posX + dx / canvasHost.fit
                    var layoutY = tile.mon.posY + dy / canvasHost.fit
                    root.commitDrag(tile.mon.output, Math.round(layoutX), Math.round(layoutY))
                  }
                }

                TapHandler {
                  enabled: !!tile.mon
                  acceptedButtons: Qt.LeftButton
                  onTapped: if (tile.mon) root.placeTarget = tile.mon.output
                }
              }
            }
          }

          Row {
            visible: Quickshell.screens.length > 1
            width: parent.width
            spacing: Style.space(6)

            StatusChip { label: "LEFT"; clickable: true; onActivated: root.placeBeside("left") }
            StatusChip { label: "RIGHT"; clickable: true; onActivated: root.placeBeside("right") }
            StatusChip { label: "ABOVE"; clickable: true; onActivated: root.placeBeside("top") }
            StatusChip { label: "BELOW"; clickable: true; onActivated: root.placeBeside("bottom") }
          }

          Row {
            visible: root.disabledLayoutMonitors().length > 0
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.disabledLayoutMonitors()
              Text {
                required property var modelData
                text: modelData.name + " · off"
                opacity: 0.45
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
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

  component ScalePill: Button {
    id: pill
    required property string scaleValue
    required property int scaleIndex

    text: root.effectiveScale(scaleValue) + "x"
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true

    active: root.activeScaleIndex() === scaleIndex
    hasCursor: root.cursorActive && root.focusSection === "scale" && root.selectedIndex === scaleIndex

    onClicked: root.setScale(scaleValue)
    onHovered: function(isHovered) {
      if (!isHovered || root.reflowingText) return
      root.cursorActive = true
      root.focusSection = "scale"
      root.selectedIndex = pill.scaleIndex
    }
  }

  component StatusChip: Button {
    id: chip
    required property string label
    property bool clickable: false
    property bool on: false
    signal activated()
    text: chip.label
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true
    active: chip.on
    onClicked: if (chip.clickable) chip.activated()
  }
}
