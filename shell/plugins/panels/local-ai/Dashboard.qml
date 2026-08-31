import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
// Renders purely from one `omarchy-local-ai snapshot` JSON blob. No other input.
Item {
  id: root
  property var shell: null
  property var manifest: null
  property var snap: JSON.parse('{"state":"uninitialized","operation":{},"active":{},"gpus":[],"registry":{},"hardware":{"groups":[]},"models":[],"error":""}')
  property int selectedIndex: 0
  property bool opened: false
  property string parseError: ""
  readonly property string cli: "omarchy-local-ai"
  readonly property var models: snap.models || []
  readonly property var gpus: snap.gpus || []
  readonly property var groups: snap.hardware && snap.hardware.groups ? snap.hardware.groups : []
  readonly property var active: snap.active || ({})
  readonly property var operation: snap.operation || ({})
  readonly property string state: snap.state || "uninitialized"
  readonly property bool busy: ["scanning", "downloading", "starting", "switching", "unloading"].indexOf(state) >= 0
  readonly property bool hasActive: Boolean(active.container); readonly property bool loaded: Boolean(active.apiReady) && hasActive
  readonly property color foreground: Color.foreground
  readonly property color dim: Util.alpha(foreground, 0.55)
  readonly property string fontFamily: Style.font.family
  function open(payloadJson) { opened = true; refresh(); Qt.callLater(function() { keys.forceActiveFocus() }) }
  function close() { opened = false }
  function dismiss() { if (shell && typeof shell.hide === "function") shell.hide("omarchy.local-ai"); else opened = false }
  function refresh() { if (!poll.running) poll.running = true }
  function choose(i) { if (models.length) selectedIndex = Math.max(0, Math.min(models.length - 1, i)) }
  function selected() { return models.length ? models[selectedIndex] : null }
  function act(args) { if (busy || action.running) return; action.command = [cli].concat(args); action.running = true; Qt.callLater(refresh) }
  function primary() {
    var m = selected(); if (!m || m.blocked) return
    if (!m.imageDownloaded || !m.weightsDownloaded) act(["download", m.recipeId])
    else if (loaded && active.recipeId === m.recipeId) return
    else if (loaded) act(["switch", m.recipeId])
    else act(["run", m.recipeId])
  }
  function primaryLabel() {
    var m = selected(); if (!m) return ""
    if (m.blocked) return "Blocked"
    if (!m.imageDownloaded || !m.weightsDownloaded) return m.sizeGb > 0 ? "Download · " + m.sizeGb + " GB" : "Download"
    if (loaded && active.recipeId === m.recipeId) return "Running"
    return loaded ? "Switch" : "Run"
  }
  function progressText() {
    if (!busy) return ""
    var n = operation.name || state
    if (operation.indeterminate) return n + " · " + (operation.detail || "working")
    return n + " · " + (operation.percent || 0) + "%" + (operation.detail ? " · " + operation.detail : "")
  }
  function headline() {
    if (parseError) return parseError
    if (snap.error) return "error · " + snap.error
    if (busy) return progressText()
    if (loaded) return active.name + " · " + active.servedModel + (active.toksPerSec > 0 ? " · " + fmtTps(active.toksPerSec) : "") + (active.ctxTokens > 0 ? " · " + fmtCtx(active.ctxTokens) : "") + " · " + active.endpoint
    return state === "uninitialized" ? "not scanned yet" : state
  }
  function vramText(g) { return (g.usedMiB === null || g.usedMiB === undefined ? "unavailable" : g.usedMiB + " / " + g.totalMiB + " MiB") }
  function fmtCtx(t) { if (!t) return "—"; if (t >= 1048576) return Math.round(t / 1048576) + "M ctx"; if (t >= 1024) return Math.round(t / 1024) + "K ctx"; return t + " ctx" }
  function fmtTps(t) { return t > 0 ? "~" + t + " tok/s" : "—" }
  function capsText(m) { var c = []; if (m.tools) c.push("tools"); if (m.vision) c.push("vision"); if (m.reasoning) c.push("thinking"); return c.length ? c.join(" · ") : "chat" }
  function modelState(m) {
    if (m.blocked) return "blocked"
    if (m.recipeId === active.recipeId) return state
    if (m.recipeId === operation.recipeId && busy) return operation.indeterminate ? operation.name : operation.percent + "%"
    if (m.imageDownloaded && m.weightsDownloaded) return "downloaded"
    if (!m.available) return "unavailable"
    return m.downloadIndeterminate ? "not downloaded" : m.downloadPercent + "% cached"
  }
  Process {
    id: poll
    command: [root.cli, "snapshot"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { try { root.snap = JSON.parse(text); root.parseError = "" } catch (e) { root.parseError = "snapshot unavailable" } } }
  }
  Process { id: action; onExited: root.refresh() }
  Timer { interval: root.busy ? 1000 : 4000; running: root.opened; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-local-ai"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    Rectangle { anchors.fill: parent; color: Util.alpha(Color.background, 0.28) }
    MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.ArrowCursor; onClicked: root.dismiss() }
    BorderSurface {
      id: card
      width: Math.min(Style.space(960), window.width - Style.space(48))
      height: Math.min(Style.space(680), window.height - Style.space(72))
      anchors.centerIn: parent
      color: Util.alpha(Color.background, 0.97)
      radius: Style.cornerRadius
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.spaceReal(1)))
      MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.ArrowCursor; onClicked: {} }
      PanelKeyCatcher {
        id: keys
        anchors.fill: parent
        onMoveRequested: function(dx, dy) { if (dy) root.choose(root.selectedIndex + dy) }
        onActivateRequested: root.primary()
        onCloseRequested: root.dismiss(); onTextKey: function(t) { if (t === "p" && root.loaded) { Quickshell.execDetached([root.cli, "open-agent", "pi"]); root.dismiss() } }
        Column {
          id: body
          anchors.fill: parent
          anchors.margins: Style.space(24)
          spacing: Style.space(14)
          Row {
            id: header
            width: parent.width; spacing: Style.space(16)
            Column {
              width: parent.width * 0.66 - parent.spacing
              Text { width: parent.width; text: "Local AI"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.iconLarge; font.weight: Font.Medium; elide: Text.ElideRight }
              Meta { width: parent.width; text: root.headline() }
            }
            Row {
              width: parent.width * 0.34; spacing: Style.space(16); layoutDirection: Qt.RightToLeft
              Link { text: "Unload"; enabled: root.hasActive; onTriggered: root.act(["unload"]) }
              Link { text: "Open Pi"; enabled: root.loaded; onTriggered: { Quickshell.execDetached([root.cli, "open-agent", "pi"]); root.dismiss() } }
              Link { text: "Scan"; enabled: !root.busy; onTriggered: root.act(["scan"]) }
            }
          }
          Rule {}
          Row {
            id: stats
            width: parent.width; spacing: Style.space(24)
            Repeater {
              model: [{ v: root.gpus.length, l: "GPUs" }, { v: root.models.length, l: "recipes" },
                      { v: (root.snap.registry || {}).total || 0, l: "registry" },
                      { v: Boolean(root.active.apiReady) ? "yes" : "no", l: "api ready" },
                      { v: Boolean(root.active.toolCallReady) ? "yes" : (Boolean(root.active.tools) ? "pending" : "n/a"), l: "tool calls" }]
              Column {
                required property var modelData
                width: (stats.width - stats.spacing * 4) / 5; spacing: Style.space(2)
                Text { width: parent.width; text: modelData.v; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.heading; elide: Text.ElideRight }
                Meta { width: parent.width; text: modelData.l }
              }
            }
          }
          Rule {}
          Row {
            id: panes
            width: parent.width
            height: parent.height - y - footer.height - parent.spacing
            spacing: Style.space(18)
            Column {
              id: side
              width: parent.width * 0.30; spacing: Style.space(8)
              Label { text: "HARDWARE" }
              Repeater {
                model: root.groups
                Column {
                  required property var modelData
                  width: side.width; spacing: Style.space(1)
                  Text { width: parent.width; text: modelData.count + " × " + (modelData.registryName || modelData.product); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight }
                  Meta { width: parent.width; text: Math.round(modelData.memoryBytesEach / 1073741824) + " GB each · " + modelData.backend }
                }
              }
              Label { text: "VRAM"; topPadding: Style.space(6) }
              Repeater {
                model: root.gpus
                Meta { required property var modelData; width: side.width; text: modelData.backend + " " + modelData.index + " · " + root.vramText(modelData) }
              }
              Label { text: "ENDPOINT"; topPadding: Style.space(6) }
              Meta { width: side.width; text: root.active.endpoint || "no endpoint" }
              Meta { width: side.width; text: root.active.container ? root.active.container + " · port " + root.active.port : "no container" }
              Meta { width: side.width; text: "gpus " + (root.active.gpuIndices || []).join(",") }
            }
            Rule { id: divider; width: Math.max(1, Style.spaceReal(1)); height: parent.height }
            Column {
              width: parent.width - side.width - divider.width - parent.spacing * 2
              height: parent.height; spacing: Style.space(6)
              Label { text: "RECIPES" }
              ListView {
                id: list
                width: parent.width; height: parent.height - Style.space(26); clip: true
                model: root.models; currentIndex: root.selectedIndex
                delegate: CursorSurface {
                  required property var modelData; required property int index
                  width: list.width; height: Style.space(40)
                  hasCursor: index === root.selectedIndex; current: modelData.recipeId === root.active.recipeId
                  Row {
                    id: cells
                    anchors.fill: parent; anchors.leftMargin: Style.space(8); anchors.rightMargin: Style.space(8); spacing: Style.space(8)
                    readonly property real usable: width - spacing * 5
                    Cell { width: cells.usable * 0.30; text: modelData.name; color: index === root.selectedIndex ? root.foreground : root.dim }
                    Cell { width: cells.usable * 0.11; text: root.fmtCtx(modelData.ctxTokens) }
                    Cell { width: cells.usable * 0.13; text: root.fmtTps(modelData.toksPerSec) }
                    Cell { width: cells.usable * 0.18; text: root.capsText(modelData) }
                    Cell { width: cells.usable * 0.07; text: modelData.acceleratorCount + "×" }
                    Cell { width: cells.usable * 0.21; text: root.modelState(modelData) }
                  }
                  MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onEntered: root.choose(index); onClicked: root.choose(index); onDoubleClicked: root.primary() }
                }
                ScrollBar.vertical: ScrollBar {}
              }
            }
          }
          Item {
            id: footer
            width: parent.width; height: Style.space(46)
            Rule { width: parent.width; anchors.top: parent.top }
            Meta {
              anchors.left: parent.left; anchors.right: go.left; anchors.rightMargin: Style.space(18)
              anchors.top: parent.top; anchors.topMargin: Style.space(12)
              text: !root.selected() ? "no matching recipe"
                    : root.selected().blocked ? root.selected().recipeId + " · " + (root.selected().reason || "blocked")
                    : root.selected().recipeId + " · " + root.selected().engine + " · " + root.selected().precision + (root.selected().sizeGb > 0 ? " · " + root.selected().sizeGb + " GB" : "") + " · " + root.selected().hardware + (root.selected().available ? "" : " · unavailable")
            }
            Rectangle {
              visible: root.busy && !root.operation.indeterminate
              anchors.left: parent.left; anchors.right: go.left; anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(6)
              height: Math.max(2, Style.spaceReal(2)); color: Util.alpha(root.foreground, 0.16)
              Rectangle { width: parent.width * Math.min(1, (root.operation.percent || 0) / 100); height: parent.height; color: root.foreground }
            }
            Link { id: go; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; enabled: Boolean(root.selected()) && !root.selected().blocked && !root.busy; text: root.busy ? root.progressText() : root.primaryLabel(); onTriggered: root.primary() }
          }
        }
      }
    }
  }
  component Meta: Text { color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight; maximumLineCount: 1 }
  component Label: Text { color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.letterSpacing: Style.spaceReal(0.4) }
  component Cell: Text { anchors.verticalCenter: parent.verticalCenter; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight; maximumLineCount: 1 }
  component Link: Text {
    signal triggered()
    color: root.foreground; opacity: enabled ? 1 : 0.32; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight
    MouseArea { anchors.fill: parent; enabled: parent.enabled; hoverEnabled: true; cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: parent.triggered() }
  }
  component Rule: Rectangle { width: parent ? parent.width : 0; height: Math.max(1, Style.spaceReal(1)); color: Util.alpha(root.foreground, 0.18) }
}
