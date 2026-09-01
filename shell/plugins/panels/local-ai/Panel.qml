import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
// One button for local models. Renders purely from `omarchy-local-ai snapshot`.
Panel {
  id: root
  moduleName: "omarchy.local-ai"
  ipcTarget: "omarchy.local-ai"
  manageIpc: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  property var snap: JSON.parse('{"state":"uninitialized","operation":{},"active":{},"models":[],"recommended":"","share":{},"error":""}')
  readonly property string cli: "omarchy-local-ai"
  readonly property var active: snap.active || ({})
  readonly property var operation: snap.operation || ({})
  readonly property var share: snap.share || ({})
  readonly property string state: snap.state || "uninitialized"
  readonly property var models: {
    var rows = (snap.models || []).filter(function(m) { return m.available && !m.blocked })
    rows.sort(function(a, b) { return (b.recipeId === snap.recommended) - (a.recipeId === snap.recommended) })
    return rows.slice(0, 5)
  }
  readonly property bool hasActive: Boolean(active.container); readonly property bool loaded: Boolean(active.apiReady) && hasActive
  readonly property bool busy: ["scanning", "downloading", "starting", "switching", "unloading"].indexOf(state) >= 0
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Util.alpha(foreground, 0.55)
  function refresh() { if (!poll.running) poll.running = true }
  function act(args, closeAfter) { if (busy || action.running) return; action.command = [cli].concat(args); action.closeAfter = closeAfter; action.running = true }
  function line() {
    if (snap.error) return "error · " + snap.error
    if (busy) return (operation.name || state) + (operation.indeterminate ? " · " + (operation.detail || "working") : " · " + (operation.percent || 0) + "%")
    if (loaded) return active.endpoint + (share.active && share.dns ? " · shared on " + share.dns : "")
    if (models.length) return models.length + (models.length === 1 ? " model runs" : " models run") + " on this hardware"
    return state === "uninitialized" ? "not scanned yet" : state
  }
  function rowText(m) {
    var s = m.name
    if (loaded && active.recipeId === m.recipeId) return s + " · running"
    if (m.recipeId === snap.recommended) s += " · recommended"
    if (!m.imageDownloaded || !m.weightsDownloaded) s += m.sizeGb > 0 ? " · " + m.sizeGb + " GB" : " · download"
    return s
  }
  function loadModel(m) { if (loaded && active.recipeId === m.recipeId) return; act(["load", m.recipeId], false) }
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
    onPressed: function(code) { if (code === Qt.RightButton && root.loaded) root.act(["open-agent"], true); else root.toggle() }
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
      onActivateRequested: { if (root.loaded) root.act(["open-agent"], true); else if (root.models.length) root.loadModel(root.models[0]); else root.act(["scan"], false) }
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
        }
        Column {
          width: parent.width; spacing: Style.space(6)
          Repeater {
            model: root.models
            Link { required property var modelData; width: content.width; text: root.rowText(modelData); enabled: !root.busy && !(root.loaded && root.active.recipeId === modelData.recipeId); onTriggered: root.loadModel(modelData) }
          }
        }
        Column {
          width: parent.width; spacing: Style.space(10)
          Rule {}
          Link { text: "Open agent"; enabled: root.loaded; onTriggered: root.act(["open-agent"], true) }
          Link { visible: Boolean(root.share.available); text: root.share.active ? "Stop sharing on Tailscale" : "Share on Tailscale"; enabled: root.loaded && !root.busy; onTriggered: root.act(["share"], false) }
          Link { text: "Unload"; enabled: root.hasActive && !root.busy; onTriggered: root.act(["unload"], false) }
          Link { text: "Scan"; enabled: !root.busy; onTriggered: root.act(["scan"], false) }
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
