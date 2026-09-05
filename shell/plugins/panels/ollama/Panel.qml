import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Live Ollama stats: context-window usage, decode and ingest speeds, and
// time-to-first-token for the locally loaded Ollama model.
//
// All numbers come from omarchy-ollama-context-watch, a user service that
// tails ollama's journal and keeps a small JSON snapshot current. Ollama does
// not enforce OLLAMA_CONTEXT_LENGTH as a hard ceiling: under VRAM pressure it
// silently truncates a prompt to whatever it can free and says so only in a
// WARN line, so the truncation state here is the whole reason this exists.
Panel {
  id: root
  moduleName: "omarchy.ollama-stats"
  ipcTarget: "omarchy.ollama-stats"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || (root.home + "/.local/state"))
    + "/omarchy/ollama-context-watch/state.json"

  // NOT `data`: every Item already has a default property by that name — the
  // list its children are assigned into. Shadowing it parses fine and logs
  // nothing, and the widget's own button silently never becomes a child.
  property var snapshot: null
  property bool cursorActive: false
  property double nowMs: Date.now()

  readonly property bool hasState: snapshot !== null
  readonly property string model: hasState ? String(snapshot.modelLoaded || "") : ""
  readonly property bool hasModel: model !== ""
  readonly property int configuredMax: hasState ? Number(snapshot.configuredMax || 0) : 0
  readonly property string phase: hasState ? String(snapshot.phase || "idle") : "idle"
  readonly property bool truncated: hasState && snapshot.truncated === true
  readonly property var truncatedDetail: hasState ? (snapshot.truncatedDetail || null) : null

  // While a prompt is being ingested the journal reports progress token by
  // token, so the bar counts up live instead of jumping at the end. Once
  // settled, show the session PEAK: the single slot genuinely shrinks when a
  // request on another conversation lineage lands, and re-painting that would
  // make the meter bounce around — the peak only moves up while the model
  // stays loaded. The peak also stays on screen during prefill: a fresh
  // request starts its progress at 0, which would otherwise make the meter
  // briefly collapse from the session peak.
  readonly property int tokens: {
    if (!hasState) return -1
    var peak = snapshot.contextPeak
    if (phase === "prefill" && snapshot.prefillProgress) {
      var progress = Number(snapshot.prefillProgress.nTokens || 0)
      if (peak != null && peak !== undefined && progress < peak) return Number(peak)
      return progress
    }
    if (peak != null && peak !== undefined) return Number(peak)
    var last = (snapshot.contextPos != null ? snapshot.contextPos : snapshot.lastPromptTokens)
    return last === null || last === undefined ? -1 : Number(last)
  }

  readonly property real percent: tokens >= 0 && configuredMax > 0 ? tokens / configuredMax : -1
  readonly property bool alarming: truncated || percent >= 0.9

  // Decode speed: the in-flight tg_3s while a generation is running, and the
  // previous run's whole-run average once it has finished.
  readonly property real liveTokSec: hasState && snapshot.liveTokensPerSec !== null && snapshot.liveTokensPerSec !== undefined
    ? Number(snapshot.liveTokensPerSec) : -1
  readonly property real lastTokSec: hasState && snapshot.lastTokensPerSec !== null && snapshot.lastTokensPerSec !== undefined
    ? Number(snapshot.lastTokensPerSec) : -1
  readonly property real maxTokSec: hasState && snapshot.maxTokensPerSec !== null && snapshot.maxTokensPerSec !== undefined
    ? Number(snapshot.maxTokensPerSec) : -1
  readonly property bool decoding: liveTokSec >= 0

  // Ingest (prefill) speed: live while the prompt is being read (journal
  // progress-line deltas), the whole-prefill average once it has finished.
  readonly property real livePrefillTokSec: hasState && snapshot.livePrefillTokensPerSec !== null && snapshot.livePrefillTokensPerSec !== undefined
    ? Number(snapshot.livePrefillTokensPerSec) : -1
  readonly property real lastPrefillTokSec: hasState && snapshot.lastPrefillTokensPerSec !== null && snapshot.lastPrefillTokensPerSec !== undefined
    ? Number(snapshot.lastPrefillTokensPerSec) : -1
  readonly property real maxPrefillTokSec: hasState && snapshot.maxPrefillTokensPerSec !== null && snapshot.maxPrefillTokensPerSec !== undefined
    ? Number(snapshot.maxPrefillTokensPerSec) : -1
  readonly property bool prefilling: phase === "prefill"
  readonly property real prefillSpeed: prefilling
    ? (livePrefillTokSec >= 0 ? livePrefillTokSec : lastPrefillTokSec) : -1

  // Time to first token: the prompt-eval line closes prefill out, so the
  // wall-clock gap between the request start and that line is the TTFT.
  readonly property real ttftLastMs: hasState && snapshot.ttftLastMs !== null && snapshot.ttftLastMs !== undefined
    ? Number(snapshot.ttftLastMs) : -1
  readonly property real ttftBestMs: hasState && snapshot.ttftBestMs !== null && snapshot.ttftBestMs !== undefined
    ? Number(snapshot.ttftBestMs) : -1
  readonly property real ttftWorstMs: hasState && snapshot.ttftWorstMs !== null && snapshot.ttftWorstMs !== undefined
    ? Number(snapshot.ttftWorstMs) : -1
  readonly property real ttftAvgMs: hasState && snapshot.ttftAvgMs !== null && snapshot.ttftAvgMs !== undefined
    ? Number(snapshot.ttftAvgMs) : -1
  readonly property real ttftMedianMs: hasState && snapshot.ttftMedianMs !== null && snapshot.ttftMedianMs !== undefined
    ? Number(snapshot.ttftMedianMs) : -1
  readonly property bool hasTtft: ttftLastMs >= 0

  // ---- GPU placement (load-time facts) and utilisation (sampled at 2 Hz) ----
  readonly property var layers: hasState ? (snapshot.layers || null) : null
  readonly property string processor: hasState ? String(snapshot.processor || "") : ""
  readonly property real modelBufferMiB: hasState ? Number(snapshot.modelBufferMiB || 0) : 0
  readonly property var gpu: hasState ? (snapshot.gpu || null) : null
  readonly property bool hasGpu: gpu !== null

  readonly property real gpuUtil: hasGpu && gpu.util !== null ? Number(gpu.util) / 100 : -1
  readonly property real vramUsed: hasGpu ? Number(gpu.memUsed || 0) : 0
  readonly property real vramTotal: hasGpu ? Number(gpu.memTotal || 0) : 0
  readonly property real vramPercent: vramTotal > 0 ? vramUsed / vramTotal : -1
  // A model that did not fit lands partly on the CPU, and that costs far more
  // than a full context does — worth the same alarm colour.
  readonly property bool partialOffload: layers !== null && Number(layers.offloaded) < Number(layers.total)

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function fmt(n) {
    var value = Number(n)
    if (!isFinite(value)) return "—"
    return value.toLocaleString(Qt.locale(), "f", 0)
  }

  // One decimal below 10% so a prompt being ingested visibly climbs instead of
  // sitting on "0%" for the first twenty thousand tokens.
  function percentText(p) {
    if (!(p >= 0)) return "—"
    var pct = p * 100
    return (pct < 10 ? pct.toFixed(1) : Math.round(pct)) + "%"
  }

  function phaseText() {
    if (truncated) return "Truncated"
    if (!hasModel) return "No model loaded"
    if (phase === "prefill") return "Reading prompt"
    if (phase === "generating") return "Generating"
    return "Idle"
  }

  function gib(mib) {
    var value = Number(mib)
    if (!isFinite(value) || value <= 0) return "—"
    return (value / 1024).toFixed(1) + " GiB"
  }

  function layersText() {
    if (!layers) return "—"
    return layers.offloaded + " / " + layers.total
  }

  function tokSecText(v) { return Math.round(v) + " tok/s" }

  // Prefill runs at hundreds–thousands of tokens/second, a completely
  // different regime from decode — label it explicitly so the number isn't
  // mistaken for decode speed.
  function prefillSpeedText(v) { return "prefill " + Math.round(v) + " t/s" }

  function prefillValueText(v) { return Math.round(v) + " t/s" }

  // TTFT is always shown as seconds with one decimal — 2560 ms reads "2.6 s",
  // 256 ms reads "0.3 s" — so the readout stays comparable across requests.
  function secText(v) {
    var value = Number(v)
    if (!isFinite(value) || value < 0) return "—"
    return (value / 1000).toFixed(1) + " s"
  }

  function barText() {
    var context = truncated ? "󰓅 !" : "󰓅 " + percentText(percent)
    if (prefilling) {
      // While a prompt is being ingested the GPU is pinned anyway, and the
      // ingest rate is the interesting number — same trade-off as decoding.
      if (prefillSpeed >= 0) return context + "  󰢮 " + prefillSpeedText(prefillSpeed)
      return context
    }
    if (decoding) {
      // While a generation is in flight the speed is the interesting number —
      // the GPU is pinned at 100% anyway — and it updates more often.
      return context + "  󰢮 " + tokSecText(liveTokSec)
    }
    if (gpuUtil < 0) return context
    // Right-padded to a constant width: this redraws twice a second, and an
    // 9%→10% width change would shove every widget beside it in the bar.
    var util = Math.round(gpuUtil * 100) + "%"
    return context + "  󰢮 " + ("   " + util).slice(-4)
  }

  function tooltipText() {
    if (!hasState) return "Ollama context watcher is not running"
    var lines = []
    if (truncated && truncatedDetail)
      lines.push("Prompt truncated to " + fmt(truncatedDetail.new) + " of "
        + fmt(truncatedDetail.prompt) + " tokens — reload the model")
    else if (!hasModel)
      lines.push("No model loaded")
    else
      lines.push(model + " · " + fmt(tokens) + " / " + fmt(configuredMax)
        + " tokens (" + percentText(percent) + ") · " + phaseText()
        + " · session peak")
    if (decoding) lines.push("Decoding at " + tokSecText(liveTokSec))
    else if (lastTokSec >= 0) lines.push("Last generation " + tokSecText(lastTokSec) + " average")
    if (prefilling && prefillSpeed >= 0) lines.push("Ingesting " + prefillSpeedText(prefillSpeed))
    else if (lastPrefillTokSec >= 0) lines.push("Last prefill " + prefillValueText(lastPrefillTokSec) + " average")
    if (hasTtft) lines.push("TTFT " + secText(ttftLastMs) + " · best " + secText(ttftBestMs)
      + " · worst " + secText(ttftWorstMs) + " · avg " + secText(ttftAvgMs)
      + " · med " + secText(ttftMedianMs))
    if (layers) lines.push("Layers on GPU " + layersText() + (processor !== "" ? " · " + processor : ""))
    if (hasGpu) lines.push("GPU " + Math.round(gpuUtil * 100) + "% · VRAM "
      + gib(vramUsed) + " / " + gib(vramTotal))
    return lines.join("\n")
  }

  function updatedText() {
    if (!hasState || !snapshot.updatedAt) return ""
    var ms = new Date(String(snapshot.updatedAt)).getTime()
    if (!isFinite(ms)) return ""
    var seconds = Math.max(0, Math.round((root.nowMs - ms) / 1000))
    if (seconds < 5) return "Updated just now"
    if (seconds < 90) return "Updated " + seconds + "s ago"
    if (seconds < 5400) return "Updated " + Math.round(seconds / 60) + "m ago"
    return "Updated " + Math.round(seconds / 3600) + "h ago"
  }

  // Unloading is what actually clears the stale prompt-cache entries behind a
  // truncation; the next request reloads the model with a clean window.
  function reloadModel() {
    if (!hasModel || reloadProc.running) return
    reloadProc.command = ["ollama", "stop", root.model]
    reloadProc.running = true
  }

  function parseState(text) {
    try {
      root.snapshot = JSON.parse(text)
    } catch (error) {
      root.snapshot = null
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    stateFile.reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseState(text())
    onLoadFailed: root.snapshot = null
  }

  // The watcher replaces the file rather than rewriting it in place, which can
  // cost the inotify watch its target. A short poll on top of watchChanges is
  // what makes the count actually climb in real time.
  Timer {
    interval: root.opened ? 200 : 500
    running: true
    repeat: true
    onTriggered: stateFile.reload()
  }

  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Process {
    id: reloadProc
    onExited: stateFile.reload()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function reload(): string { root.reloadModel(); return root.hasModel ? "stopping " + root.model : "no model loaded" }
    function usage(): string { return root.tooltipText() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText()
    active: root.alarming
    tooltipText: root.tooltipText()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.reloadModel()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onActivateRequested: root.reloadModel()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.reloadModel() }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: root.hasModel ? root.model : "Ollama"
          meta: root.phaseText()
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: "󰓅"
              color: root.alarming ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        // ---------- Truncation warning ----------
        BorderSurface {
          visible: root.truncated
          width: parent.width
          implicitHeight: truncText.implicitHeight + Style.spacing.xl * 2
          color: root.alpha(root.urgent, 0.10)
          borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
          radius: Style.cornerRadius

          Text {
            id: truncText
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            text: root.truncatedDetail
              ? "Cache pressure cut the usable window to " + root.fmt(root.truncatedDetail.new)
                + " tokens — the last prompt asked for " + root.fmt(root.truncatedDetail.prompt)
                + ". Reload the model to clear it."
              : "The last prompt was silently truncated."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---------- Context window ----------
        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            width: parent.width
            text: "CONTEXT WINDOW"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(usedLabel.implicitHeight, usedValue.implicitHeight)

            Text {
              id: usedLabel
              textFormat: Text.PlainText
              text: root.phase === "prefill" ? "Reading" : "Peak used"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: usedValue
              textFormat: Text.PlainText
              text: root.percentText(root.percent)
              color: root.alarming ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Meter {
            width: parent.width
            value: root.percent
            alarming: root.alarming
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.configuredMax > 0
              ? root.fmt(root.tokens) + " of " + root.fmt(root.configuredMax) + " tokens"
              : "No model loaded — the window is reported by the running model."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---------- Latency ----------
        PanelSeparator {
          visible: ttftSection.visible
          foreground: root.foreground
        }

        Column {
          id: ttftSection
          visible: root.hasTtft
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            width: parent.width
            text: "TIME TO FIRST TOKEN"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Row {
              width: parent.width

              Text {
                text: "Last"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width / 5
              }
              Text {
                text: "Best"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width / 5
              }
              Text {
                text: "Worst"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width / 5
              }
              Text {
                text: "Avg"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width / 5
              }
              Text {
                text: "Med"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width / 5
              }
            }

            Row {
              width: parent.width

              Text {
                text: root.secText(root.ttftLastMs)
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                width: parent.width / 5
              }
              Text {
                text: root.secText(root.ttftBestMs)
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                width: parent.width / 5
              }
              Text {
                text: root.secText(root.ttftWorstMs)
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                width: parent.width / 5
              }
              Text {
                text: root.secText(root.ttftAvgMs)
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                width: parent.width / 5
              }
              Text {
                text: root.secText(root.ttftMedianMs)
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                width: parent.width / 5
              }
            }
          }
        }

        // ---------- GPU ----------
        PanelSeparator {
          visible: gpuSection.visible
          foreground: root.foreground
        }

        Column {
          id: gpuSection
          visible: root.hasGpu || root.layers !== null
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            width: parent.width
            text: "GPU"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

           StatRow {
             visible: root.gpuUtil >= 0 || root.prefilling
             width: parent.width
             label: root.decoding ? "Decode (live)"
               : root.prefilling ? "Ingest (live)" : "Utilisation"
             value: root.decoding ? root.tokSecText(root.liveTokSec)
               : root.prefilling ? (root.livePrefillTokSec >= 0 ? root.prefillValueText(root.livePrefillTokSec) : "—")
               : Math.round(root.gpuUtil * 100) + "%"
             ratio: root.decoding
               ? (root.maxTokSec > 0 ? root.liveTokSec / root.maxTokSec : -1)
               : root.prefilling
                 ? (root.maxPrefillTokSec > 0 && root.livePrefillTokSec > 0 ? root.livePrefillTokSec / root.maxPrefillTokSec : -1)
                 : root.gpuUtil
           }

           StatRow {
             visible: root.lastPrefillTokSec >= 0
             width: parent.width
             label: "Last prefill"
             value: root.prefillValueText(root.lastPrefillTokSec) + " average"
             // Bar sized against the fastest ingest speed seen this load.
             ratio: root.maxPrefillTokSec > 0 ? root.lastPrefillTokSec / root.maxPrefillTokSec : -1
           }

           StatRow {
             visible: !root.decoding && root.lastTokSec >= 0
             width: parent.width
             label: "Last generation"
             value: root.tokSecText(root.lastTokSec) + " average"
             ratio: root.maxTokSec > 0 ? root.lastTokSec / root.maxTokSec : -1
           }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: {
              var parts = []
              if (root.vramPercent >= 0)
                parts.push("VRAM " + root.gib(root.vramUsed) + " / " + root.gib(root.vramTotal))
              if (root.layers !== null)
                parts.push("layers " + root.layersText() + " on GPU")
              return parts.join(" · ")
            }
            // Full VRAM or a partial offload means truncation / slow decode —
            // the same alarm colours the meter rows used to carry.
            color: (root.partialOffload || root.vramPercent >= 0.95) ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: {
              var parts = []
              if (root.processor !== "") parts.push(root.processor)
              if (root.modelBufferMiB > 0) parts.push("weights " + root.gib(root.modelBufferMiB))
              if (root.hasGpu && root.gpu.temp !== null) parts.push(root.gpu.temp + " °C")
              if (root.hasGpu && root.gpu.power !== null) parts.push(Math.round(root.gpu.power) + " W")
              return parts.join(" · ")
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: root.partialOffload
            width: parent.width
            text: "Part of this model is running on the CPU — expect it to be several times slower."
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---------- Reload ----------
        PanelSeparator { foreground: root.foreground }

        Button {
          width: parent.width
          text: reloadProc.running ? "Reloading…" : "Reload model"
          bordered: true
          opacity: root.hasModel && !reloadProc.running ? 1 : 0.45
          hasCursor: root.cursorActive
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.reloadModel()
          onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
        }

        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          width: parent.width
          text: root.hasState ? root.updatedText() : "Watcher not running: omarchy-ollama-context-watch.service"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  // Label, value, and a meter underneath — the shape every GPU figure takes.
  component StatRow: Column {
    id: statRow
    property string label: ""
    property string value: ""
    property real ratio: -1
    property bool alarming: false

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(statLabel.implicitHeight, statValue.implicitHeight)

      Text {
        id: statLabel
        textFormat: Text.PlainText
        text: statRow.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: statValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: statValue
        textFormat: Text.PlainText
        text: statRow.value
        color: statRow.alarming ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: statRow.ratio
      alarming: statRow.alarming
    }
  }

  // Rounded track showing how much of the window the current prompt fills.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }
  }
}
