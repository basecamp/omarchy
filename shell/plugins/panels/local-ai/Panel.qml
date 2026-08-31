import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
// Bar icon + keyboard panel. Renders purely from one `omarchy-local-ai snapshot` blob.
Panel {
  id: root
  moduleName: "omarchy.local-ai"
  ipcTarget: "omarchy.local-ai"
  manageIpc: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  property var snap: JSON.parse('{"state":"uninitialized","operation":{},"active":{},"gpus":[],"registry":{},"hardware":{"groups":[]},"models":[],"error":""}')
  readonly property string cli: "omarchy-local-ai"
  readonly property var active: snap.active || ({})
  readonly property var operation: snap.operation || ({})
  readonly property var gpus: snap.gpus || []
  readonly property string state: snap.state || "uninitialized"
  readonly property bool hasActive: Boolean(active.container); readonly property bool loaded: Boolean(active.apiReady) && hasActive
  readonly property bool busy: ["scanning", "downloading", "starting", "switching", "unloading"].indexOf(state) >= 0
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Util.alpha(foreground, 0.55)
  function refresh() { if (!poll.running) poll.running = true }
  function openDashboard() { close(); Quickshell.execDetached(["omarchy-shell", "shell", "summon", "omarchy.local-ai", "{}"]) }
  function act(args, closeAfter) { if (busy || action.running) return; action.command = [cli].concat(args); action.closeAfter = closeAfter; action.running = true }
  function line() {
    if (snap.error) return "error · " + snap.error
    if (busy) return (operation.name || state) + (operation.indeterminate ? " · " + (operation.detail || "working") : " · " + (operation.percent || 0) + "%")
    if (loaded) return active.servedModel + " · " + active.endpoint
    return state
  }
  onOpenedChanged: if (opened) refresh()
  Process {
    id: poll
    command: [root.cli, "snapshot"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { try { root.snap = JSON.parse(text) } catch (e) {} } }
  }
  Process { id: action; property bool closeAfter: false; onExited: { if (closeAfter) root.close(); root.refresh() } }
  Timer { interval: root.opened ? (root.busy ? 1000 : 4000) : 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item { Rectangle { anchors.centerIn: parent; width: Style.space(9); height: width; radius: width / 2; color: root.loaded ? root.foreground : "transparent"; border.width: root.loaded ? 0 : Math.max(1, Style.space(1)); border.color: root.foreground } }
    }
    tooltipText: root.loaded ? "Local AI · " + root.active.name : "Local AI · " + root.state
    onPressed: function(code) { if (code === Qt.RightButton && root.loaded) root.act(["open-agent", "pi"], true); else root.toggle() }
  }
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(260))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)
    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onActivateRequested: root.openDashboard()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(12)
        Column {
          width: parent.width; spacing: Style.space(3)
          Text { width: parent.width; text: root.loaded ? root.active.name : "Local AI"; color: root.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.heading; font.weight: Font.Medium; elide: Text.ElideRight }
          Meta { width: parent.width; text: root.line() }
          Meta { width: parent.width; text: root.loaded ? "api " + (root.active.apiReady ? "ready" : "pending") + " · tools " + (root.active.toolCallReady ? "ready" : root.active.tools ? "pending" : "n/a") + (root.active.toksPerSec > 0 ? " · ~" + root.active.toksPerSec + " tok/s" : "") + (root.active.ctxTokens >= 1024 ? " · " + Math.round(root.active.ctxTokens / 1024) + "K ctx" : "") : (root.snap.models || []).filter(function(m) { return !m.blocked }).length + " runnable recipes" }
        }
        Column {
          width: parent.width; spacing: Style.space(3)
          Repeater {
            model: root.gpus
            Meta { required property var modelData; width: content.width; text: modelData.backend + " " + modelData.index + " · " + (modelData.usedMiB === null || modelData.usedMiB === undefined ? "unavailable" : modelData.usedMiB + " / " + modelData.totalMiB + " MiB") }
          }
        }
        Column {
          width: parent.width; spacing: Style.space(10)
          Link { text: "Open Local AI panel"; onTriggered: root.openDashboard() }
          Rule {}
          Link { text: "Scan"; enabled: !root.busy; onTriggered: root.act(["scan"], false) }
          Link { text: "Open Pi"; enabled: root.loaded; onTriggered: root.act(["open-agent", "pi"], true) }
          Link { text: "Unload"; enabled: root.hasActive; onTriggered: root.act(["unload"], false) }
        }
      }
    }
  }
  component Meta: Text { color: root.dim; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight; maximumLineCount: 1 }
  component Link: Text {
    signal triggered()
    color: root.foreground; opacity: enabled ? 1 : 0.32; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight
    MouseArea { anchors.fill: parent; enabled: parent.enabled; hoverEnabled: true; cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: parent.triggered() }
  }
  component Rule: Rectangle { width: parent ? parent.width : 0; height: Math.max(1, Style.spaceReal(1)); color: Util.alpha(root.foreground, 0.18) }
}
