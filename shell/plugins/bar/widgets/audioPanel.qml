import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "audioPanel"
  property var settings: ({})

  property bool popupOpen: false

  function closePopout() { popupOpen = false }

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []

  readonly property var candidateSinks: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream) list.push(n)
    }
    return list
  }

  readonly property var candidateSources: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && !n.isSink && !n.isStream && n.audio) {
        var name = n.name || ""
        if (name === "quickshell") continue
        list.push(n)
      }
    }
    return list
  }

  readonly property var candidateStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && isPlaybackStream(n)) list.push(n)
    }
    return list
  }

  property var sinkAvailability: ({})
  property bool sinkAvailabilityLoaded: false

  // Identify true playback streams without reading node.properties here:
  // PwNode.properties is invalid until the node is bound, and reading it while
  // capture streams are appearing (for example, when Voxtype starts recording)
  // can destabilize Quickshell's Pipewire service. Quickshell versions differ
  // in how `type` is exposed (media.class, enum name, or numeric enum), but
  // playback streams consistently accept audio input from clients and publish
  // `isSink: true`; capture streams publish as stream sources.
  function isPlaybackStream(node) {
    if (!node || !node.isStream) return false
    if (node.isSink === true) return true

    var mediaClass = String(node.type || "")
    return mediaClass.indexOf("Stream/Output/Audio") !== -1
      || mediaClass.indexOf("AudioOutStream") !== -1
      || mediaClass.indexOf("Output") !== -1
  }

  readonly property var audioSinks: {
    var list = []
    for (var i = 0; i < candidateSinks.length; i++)
      if (candidateSinks[i].audio && sinkAvailable(candidateSinks[i])) list.push(candidateSinks[i])
    return list
  }

  readonly property var audioSources: candidateSources

  readonly property var audioStreams: {
    var list = []
    for (var i = 0; i < candidateStreams.length; i++)
      if (candidateStreams[i].audio) list.push(candidateStreams[i])
    return list
  }

  readonly property real outputVolume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool outputMuted: sink && sink.audio ? sink.audio.muted : false
  readonly property real inputVolume: source && source.audio ? source.audio.volume : 0
  readonly property bool inputMuted: source && source.audio ? source.audio.muted : false

  // Single cursor model shared by keyboard and mouse. Sections:
  //   "output"  — output slider + sink device list
  //   "input"   — input slider + source device list
  //   "streams" — per-app playback streams
  // selectedIndex semantics within a section:
  //   -1            → on the slider row (h/l adjusts volume, m/Enter mute)
  //   0..N-1        → on the Nth device/stream row
  // Visuals derive from hasCursor/current via CursorSurface, never
  // from containsMouse — that's what keeps the highlight unique across
  // keyboard + mouse like wifi does.
  property string focusSection: "output"
  property int selectedIndex: -1
  property bool cursorActive: false

  readonly property color hoverFill: bar
    ? Style.hoverFillFor(bar.foreground, Color.accent)
    : "transparent"
  readonly property color selectedFill: bar
    ? Style.selectedFillFor(bar.foreground, Color.accent)
    : "transparent"

  function sectionCount(section) {
    if (section === "output") return audioSinks.length
    if (section === "input") return audioSources.length
    if (section === "streams") return audioStreams.length
    return 0
  }

  function sectionVisible(section) {
    if (section === "output") return true
    if (section === "input") return audioSources.length > 0 || !!source
    if (section === "streams") return audioStreams.length > 0
    return false
  }

  function sectionHasSlider(section) {
    if (section === "output") return true
    if (section === "input") return !!source
    return false  // stream rows carry their own sliders inline; not a section-level slider
  }

  // Order of visible sections, recomputed reactively so dropping a section
  // (e.g. no input devices) doesn't leave the cursor pointing at it.
  readonly property var visibleSections: {
    var list = []
    if (sectionVisible("output")) list.push("output")
    if (sectionVisible("input")) list.push("input")
    if (sectionVisible("streams")) list.push("streams")
    return list
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) { focusSection = sections[0]; selectedIndex = sectionHasSlider(focusSection) ? -1 : 0; return }

    var idx = selectedIndex
    var max = sectionCount(focusSection) - 1  // last device index
    var hasSlider = sectionHasSlider(focusSection)
    var floor = hasSlider ? -1 : 0  // -1 = slider row

    if (delta > 0) {
      if (idx < max) { selectedIndex = idx + 1; return }
      // Fall through to next section.
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
      }
    } else {
      if (idx > floor) { selectedIndex = idx - 1; return }
      // Escape upward.
      if (sIdx > 0) {
        focusSection = sections[sIdx - 1]
        var prevMax = sectionCount(focusSection) - 1
        selectedIndex = prevMax >= 0 ? prevMax : (sectionHasSlider(focusSection) ? -1 : 0)
      }
    }
  }

  // Adjust the slider associated with the focused section. Output and
  // input sliders are real volume controls; on stream rows h/l adjusts
  // that stream's volume (so keyboard parity with the inline slider).
  // For device rows (selectedIndex >= 0 in output/input) h/l is a no-op
  // — the cursor is on a discrete row, not on the slider, and silently
  // moving the global slider would surprise the user.
  function adjustVolume(delta) {
    if (focusSection === "output" && selectedIndex === -1) {
      setOutputVolume(outputVolume + delta)
      return
    }
    if (focusSection === "input" && selectedIndex === -1) {
      setInputVolume(inputVolume + delta)
      return
    }
    if (focusSection === "streams" && selectedIndex >= 0 && selectedIndex < audioStreams.length) {
      var s = audioStreams[selectedIndex]
      if (s && s.audio) s.audio.volume = Math.max(0, Math.min(1.5, s.audio.volume + delta))
    }
  }

  // Enter/Space: activate whatever the cursor is on.
  function activateCursor() {
    if (focusSection === "output") {
      if (selectedIndex === -1) { toggleOutputMute(); return }
      var sink = audioSinks[selectedIndex]
      if (sink) setDefaultSink(sink)
      return
    }
    if (focusSection === "input") {
      if (selectedIndex === -1) { toggleInputMute(); return }
      var src = audioSources[selectedIndex]
      if (src) setDefaultSource(src)
      return
    }
    if (focusSection === "streams" && selectedIndex >= 0) {
      var st = audioStreams[selectedIndex]
      if (st && st.audio) st.audio.muted = !st.audio.muted
    }
  }

  onPopupOpenChanged: {
    if (popupOpen) {
      focusSection = "output"
      selectedIndex = -1  // first keyboard cursor reveal starts on the output slider
      cursorActive = false
      Qt.callLater(function() {
        resetScroll()
        if (keyCatcher) keyCatcher.forceActiveFocus()
      })
    }
  }

  // Clamp / repair the cursor whenever any list refreshes underneath us.
  onAudioSinksChanged: clampCursor()
  onAudioSourcesChanged: clampCursor()
  onAudioStreamsChanged: clampCursor()

  // Keep the keyboard-focused row inside the visible viewport of the
  // ScrollView. Each cursor target (slider rows, SinkRow, SourceRow,
  // StreamRow) calls this when it gains hasCursor. Without it, j/k can
  // walk the selection off-screen — wifi uses ListView.positionViewAtIndex
  // for this; we don't have that affordance with a multi-section Column.
  function resetScroll() {
    if (!scrollArea) return
    var flick = scrollArea.contentItem
    if (flick && flick.contentY !== undefined) flick.contentY = 0
  }

  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var margin = 6
    var maxY = Math.max(0, (flick.contentHeight || 0) - flick.height)
    if (maxY <= Style.space(24) || (root.focusSection === "output" && root.selectedIndex === -1)) {
      flick.contentY = 0
      return
    }
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    if (top < viewTop + margin) flick.contentY = Math.max(0, Math.min(maxY, top - margin))
    else if (bottom > viewBottom - margin)
      flick.contentY = Math.max(0, Math.min(maxY, bottom + margin - flick.height))
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = visibleSections[0]
      selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
      return
    }
    var count = sectionCount(focusSection)
    var hasSlider = sectionHasSlider(focusSection)
    var floor = hasSlider ? -1 : 0
    if (selectedIndex > count - 1) selectedIndex = Math.max(floor, count - 1)
    if (selectedIndex < floor) selectedIndex = floor
  }

  function outputIcon() {
    // Match the old Waybar pulseaudio glyph set. The Material Design speaker
    // icons render visually smaller in JetBrainsMono Nerd Font.
    if (!sink || !sink.audio) return ""
    if (outputMuted) return ""
    var v = outputVolume
    if (v >= 0.67) return ""
    if (v >= 0.34) return ""
    if (v > 0) return ""
    return ""
  }

  function inputIcon() {
    if (!source || !source.audio) return "󰍭"
    return inputMuted ? "󰍭" : "󰍬"
  }

  function setOutputVolume(v) {
    if (!sink || !sink.audio) return
    sink.audio.volume = Math.max(0, Math.min(1, v))
  }

  function setInputVolume(v) {
    if (!source || !source.audio) return
    source.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleOutputMute() {
    if (sink && sink.audio) sink.audio.muted = !sink.audio.muted
  }

  function toggleInputMute() {
    if (source && source.audio) source.audio.muted = !source.audio.muted
  }

  function setDefaultSink(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSink = node
    if (root.bar && node.id !== undefined && node.name) {
      var idArg = Util.shellQuote(String(node.id))
      var nameArg = Util.shellQuote(String(node.name))
      root.bar.run("wpctl set-default " + idArg + " 2>/dev/null || true; "
        + "pactl set-default-sink " + nameArg + " 2>/dev/null || true; "
        + "pactl list short sink-inputs 2>/dev/null | awk '{ print $1 }' | while read -r input; do "
        + "pactl move-sink-input \"$input\" " + nameArg + " 2>/dev/null || true; done")
    }
  }

  function setDefaultSource(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSource = node
    if (root.bar && node.id !== undefined && node.name) {
      var idArg = Util.shellQuote(String(node.id))
      var nameArg = Util.shellQuote(String(node.name))
      root.bar.run("wpctl set-default " + idArg + " 2>/dev/null || true; "
        + "pactl set-default-source " + nameArg + " 2>/dev/null || true; "
        + "pactl list short source-outputs 2>/dev/null | awk '{ print $1 }' | while read -r output; do "
        + "pactl move-source-output \"$output\" " + nameArg + " 2>/dev/null || true; done")
    }
  }

  function sinkAvailable(node) {
    if (!node || !node.name || !sinkAvailabilityLoaded) return true
    var name = String(node.name)
    return sinkAvailability[name] !== false
  }

  function updateSinkAvailability(raw) {
    var next = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      if (parts.length >= 2) next[parts[0]] = parts[1] !== "0"
    }
    sinkAvailability = next
    sinkAvailabilityLoaded = true
  }

  function friendlyDeviceLabel(text) {
    var label = String(text || "").trim()
    label = label.replace(/^sof-soundwire\s+/i, "")
    label = label.replace(/^built-?in audio\s+/i, "")
    label = label.replace(/\s+Output$/i, "")
    label = label.replace(/\s+Input$/i, "")
    label = label.replace(/\bMicrophones\b/g, "Microphone")
    return label
  }

  function nodeLabel(node) {
    if (!node) return "Unknown"
    var p = nodeProps(node)
    var nickname = friendlyDeviceLabel(node.nickname || node.nick || p["node.nick"] || p["device.profile.description"] || "")
    if (nickname) return nickname
    return friendlyDeviceLabel(node.description || p["node.description"] || node.name || "Unknown")
  }

  function nodeProps(node) {
    return node && node.ready && node.properties ? node.properties : {}
  }

  function sinkGlyph(node) {
    if (!node) return "󰓃"
    var p = nodeProps(node)
    var blob = String([
      node.name, node.description, node.nickname,
      p["device.icon-name"] || "",
      p["device.product.name"] || ""
    ].join(" ")).toLowerCase()
    if (blob.indexOf("headphone") !== -1 || blob.indexOf("headset") !== -1) return "󰋋"
    if (blob.indexOf("bluetooth") !== -1) return "󰂯"
    if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1) return "󰍹"
    return "󰓃"
  }

  function sourceGlyph(node) {
    if (!node) return "󰍬"
    var p = nodeProps(node)
    var blob = String([
      node.name, node.description, node.nickname,
      p["device.icon-name"] || ""
    ].join(" ")).toLowerCase()
    if (blob.indexOf("headset") !== -1) return "󰋋"
    if (blob.indexOf("bluetooth") !== -1) return "󰂯"
    if (blob.indexOf("webcam") !== -1 || blob.indexOf("camera") !== -1) return "󰄀"
    return "󰍬"
  }

  function streamLabel(node) {
    if (!node) return "Stream"
    var p = nodeProps(node)
    return p["application.name"] || node.description || p["media.name"] || p["node.name"] || node.name || "Stream"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  PwObjectTracker { objects: root.candidateSinks }
  PwObjectTracker { objects: root.candidateSources }
  PwObjectTracker { objects: root.audioStreams }

  Process {
    id: sinkAvailabilityProc
    command: ["bash", "-lc", `
pactl list sinks 2>/dev/null | python3 -c '
import re
import sys

for block in re.split(r"(?m)^Sink #", sys.stdin.read())[1:]:
    name = re.search(r"(?m)^\\s*Name:\\s*(\\S+)", block)
    if not name:
        continue

    ports = []
    in_ports = False
    for line in block.splitlines():
        if line.strip() == "Ports:":
            in_ports = True
            continue
        if in_ports and line.startswith("\\tActive Port:"):
            in_ports = False
        if in_ports and line.startswith("\\t\\t"):
            ports.append(line)

    available = not ports or any("not available" not in port for port in ports)
    print("%s\\t%d" % (name.group(1), 1 if available else 0))
'
`]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateSinkAvailability(text)
    }
  }

  Timer {
    interval: 5000
    running: root.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!sinkAvailabilityProc.running) sinkAvailabilityProc.running = true
  }

  // Lets a Hyprland keybind summon the panel without a click. Mirrors the
  // networkPanel IpcHandler pattern; KeyboardPanel grants Exclusive focus
  // at map-time so j/k/h/l work the moment the panel appears.
  IpcHandler {
    target: "audioPanel"
    function toggle(): void {
      if (root.popupOpen) root.closePopout()
      else root.popupOpen = true
    }
    function show(): void { if (!root.popupOpen) root.popupOpen = true }
    function hide(): void { root.closePopout() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.outputIcon()
    fontSize: Style.font.body
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleOutputMute()
      else root.popupOpen = !root.popupOpen
    }

    onWheelMoved: function(delta) {
      var step = 0.05
      root.setOutputVolume(root.outputVolume + (delta > 0 ? step : -step))
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: panel.fittedContentWidth(Style.space(370))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.adjustVolume(dx * 0.05)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.closePopout()
      onTextKey: function(t) {
        // 'm' mutes whatever the cursor is on: focused section's slider
        // for output/input, the focused stream for streams.
        if (t === "m" || t === "M") {
          if (!root.cursorActive) return
          if (root.focusSection === "streams" && root.selectedIndex >= 0
              && root.selectedIndex < root.audioStreams.length) {
            var s = root.audioStreams[root.selectedIndex]
            if (s && s.audio) s.audio.muted = !s.audio.muted
          } else if (root.focusSection === "input") {
            root.toggleInputMute()
          } else {
            root.toggleOutputMute()
          }
        }
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---- Output ----
          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                text: "Output"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: root.sink ? "· " + root.nodeLabel(root.sink) : ""
                color: Qt.darker(root.bar.foreground, 1.8)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                width: parent.width - Style.space(70)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            // Output slider row — itself a cursor target (selectedIndex === -1
            // when focusSection === "output"). h/l adjust the value via
            // root.adjustVolume; m / Enter toggle mute.
            CursorSurface {
              id: outputSliderRow
              width: parent.width
              height: outputSliderInner.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "output" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(outputSliderRow)
              foreground: root.bar.foreground
              outline: true

              Row {
                id: outputSliderInner
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(8)

                Text {
                  id: outputIconText
                  text: root.outputIcon()
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.heading
                  width: Style.space(22)
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: root.outputMuted ? 0.5 : 1.0

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleOutputMute()
                  }
                }

                PanelSlider {
                  id: outputSlider
                  bar: root.bar
                  width: parent.width - outputIconText.width - outputPercent.width - Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  minimum: 0
                  maximum: 1
                  step: 0.05
                  value: root.outputVolume
                  opacity: root.outputMuted ? 0.5 : 1.0
                  enabled: !!root.sink

                  onMoved: function(v) { root.setOutputVolume(v) }
                }

                Text {
                  id: outputPercent
                  text: Math.round((outputSlider.dragging ? outputSlider.liveValue : root.outputVolume) * 100) + "%"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  width: Style.space(36)
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: root.outputMuted ? 0.5 : 1.0
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                propagateComposedEvents: true
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.focusSection = "output"
                  root.selectedIndex = -1
                }
              }
            }

            Repeater {
              model: root.audioSinks

              SinkRow {
                required property var modelData
                required property int index
                width: panelColumn.width
                node: modelData
                rowIndex: index
              }
            }
          }

          // ---- Input ----
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.audioSources.length > 0 || !!root.source

            Row {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                text: "Input"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: root.source ? "· " + root.nodeLabel(root.source) : ""
                color: Qt.darker(root.bar.foreground, 1.8)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                width: parent.width - Style.space(56)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: inputSliderRow
              visible: !!root.source
              width: parent.width
              height: inputSliderInner.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "input" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(inputSliderRow)
              foreground: root.bar.foreground
              outline: true

              Row {
                id: inputSliderInner
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(8)

                Text {
                  id: inputIconText
                  text: root.inputIcon()
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.heading
                  width: Style.space(22)
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: root.inputMuted ? 0.5 : 1.0

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleInputMute()
                  }
                }

                PanelSlider {
                  id: inputSlider
                  bar: root.bar
                  width: parent.width - inputIconText.width - inputPercent.width - Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  minimum: 0
                  maximum: 1
                  step: 0.05
                  value: root.inputVolume
                  opacity: root.inputMuted ? 0.5 : 1.0
                  enabled: !!root.source

                  onMoved: function(v) { root.setInputVolume(v) }
                }

                Text {
                  id: inputPercent
                  text: Math.round((inputSlider.dragging ? inputSlider.liveValue : root.inputVolume) * 100) + "%"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  width: Style.space(36)
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: root.inputMuted ? 0.5 : 1.0
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                propagateComposedEvents: true
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.focusSection = "input"
                  root.selectedIndex = -1
                }
              }
            }

            Repeater {
              model: root.audioSources

              SourceRow {
                required property var modelData
                required property int index
                width: panelColumn.width
                node: modelData
                rowIndex: index
              }
            }
          }

          // ---- Per-app streams ----
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.audioStreams.length > 0

            PanelSectionHeader {
              text: "Playing"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
            }

            Repeater {
              model: root.audioStreams

              StreamRow {
                required property var modelData
                required property int index
                width: panelColumn.width
                node: modelData
                rowIndex: index
              }
            }
          }
        }
      }
    }
  }

  // ---- Reusable inline components ----

  // Output device row — cursor target inside the "output" section. Mouse
  // hover updates the panel cursor at the root; visuals come entirely
  // from hasCursor/current via CursorSurface, never from containsMouse.
  component SinkRow: CursorSurface {
    id: sinkRow
    required property var node
    required property int rowIndex

    readonly property bool isActive: root.sink && node && root.sink.id === node.id
    hasCursor: root.cursorActive && root.focusSection === "output" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(sinkRow)
    current: isActive
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: sinkInner.implicitHeight + Style.spacing.xl

    Row {
      id: sinkInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: root.sinkGlyph(sinkRow.node)
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: root.nodeLabel(sinkRow.node)
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(14) - Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: sinkRow.isActive ? "󰄬" : ""
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
        root.focusSection = "output"
        root.selectedIndex = sinkRow.rowIndex
      }
      onClicked: root.setDefaultSink(sinkRow.node)
    }
  }

  // Input device row — sibling of SinkRow for the "input" section.
  component SourceRow: CursorSurface {
    id: sourceRow
    required property var node
    required property int rowIndex

    readonly property bool isActive: root.source && node && root.source.id === node.id
    hasCursor: root.cursorActive && root.focusSection === "input" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(sourceRow)
    current: isActive
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: sourceInner.implicitHeight + Style.spacing.xl

    Row {
      id: sourceInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: root.sourceGlyph(sourceRow.node)
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: root.nodeLabel(sourceRow.node)
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(14) - Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: sourceRow.isActive ? "󰄬" : ""
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
        root.focusSection = "input"
        root.selectedIndex = sourceRow.rowIndex
      }
      onClicked: root.setDefaultSource(sourceRow.node)
    }
  }

  // Per-app stream row — cursor target inside the "streams" section.
  // The stream has its own slider inline, so h/l from the keyboard
  // adjusts THIS stream's volume (not the global output) when the cursor
  // sits on this row. Enter/Space mutes the stream.
  component StreamRow: CursorSurface {
    id: streamRow
    required property var node
    required property int rowIndex

    readonly property real streamVolume: node && node.audio ? node.audio.volume : 0
    readonly property bool streamMuted: node && node.audio ? node.audio.muted : false

    hasCursor: root.cursorActive && root.focusSection === "streams" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(streamRow)
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: streamColumn.implicitHeight + Style.spacing.rowGap

    Column {
      id: streamColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(6)

        Text {
          id: streamMuteIcon
          text: streamRow.streamMuted ? "󰝟" : "󰕾"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          width: Style.space(14)
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
          opacity: streamRow.streamMuted ? 0.5 : 1.0

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (streamRow.node && streamRow.node.audio)
                streamRow.node.audio.muted = !streamRow.node.audio.muted
            }
          }
        }

        Text {
          text: root.streamLabel(streamRow.node)
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          width: parent.width - streamMuteIcon.width - streamPct.width - Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: streamPct
          text: Math.round(streamRow.streamVolume * 100) + "%"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          width: Style.space(36)
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      PanelSlider {
        bar: root.bar
        width: parent.width
        minimum: 0
        maximum: 1.5
        step: 0.05
        value: streamRow.streamVolume
        opacity: streamRow.streamMuted ? 0.5 : 1.0

        onMoved: function(v) {
          if (streamRow.node && streamRow.node.audio) streamRow.node.audio.volume = v
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      propagateComposedEvents: true
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "streams"
        root.selectedIndex = streamRow.rowIndex
      }
    }
  }
}
