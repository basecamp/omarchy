import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
// One model, four buttons. Renders purely from `omarchy-local-ai snapshot`.
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
  readonly property var rec: (snap.models || []).filter(function(m) { return m.recipeId === snap.recommended })[0] || null
  readonly property bool hasActive: Boolean(active.container); readonly property bool loaded: Boolean(active.apiReady) && hasActive
  readonly property bool busy: ["scanning", "downloading", "starting", "switching", "unloading"].indexOf(state) >= 0
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Util.alpha(foreground, 0.55)
  function refresh() { if (!poll.running) poll.running = true }
  function act(args, closeAfter) { if (busy || action.running) return; action.command = [cli].concat(args); action.closeAfter = closeAfter; action.running = true }
  function title() { return loaded ? active.name : (rec ? rec.name : "Local AI") }
  property int spin: 0
  function status() {
    if (snap.error) return snap.error
    if (busy) return ["|", "/", "-", "\\"][spin] + " " + (operation.name || state) + (operation.indeterminate ? "" : " · " + (operation.percent || 0) + "%")
    return ""
  }
  function loadLabel() {
    if (!rec) return "Load"
    return (!rec.imageDownloaded || !rec.weightsDownloaded) && rec.sizeGb > 0 ? "Load · " + rec.sizeGb + " GB" : "Load"
  }
  onOpenedChanged: if (opened) { refresh(); if (state === "uninitialized") act(["scan"], false) }
  Process {
    id: poll
    command: [root.cli, "snapshot"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { if (text.length > 262144) return; try { root.snap = JSON.parse(text) } catch (e) {} } }
  }
  Process { id: action; property bool closeAfter: false; onExited: { if (closeAfter) root.close(); root.refresh() } }
  Timer { interval: root.opened ? (root.busy ? 1000 : 4000) : 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  Timer { interval: 140; running: root.busy && root.opened; repeat: true; onTriggered: root.spin = (root.spin + 1) % 4 }
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        Rectangle {
          anchors.centerIn: parent; width: Style.space(9); height: width; radius: width / 2
          color: root.loaded ? root.foreground : "transparent"
          border.width: root.loaded ? 0 : Math.max(1, Style.space(1))
          border.color: root.state === "error" ? (root.bar ? root.bar.urgent : root.foreground) : root.foreground
          SequentialAnimation on opacity {
            running: root.busy; loops: Animation.Infinite; alwaysRunToEnd: true
            NumberAnimation { to: 0.25; duration: 500 } NumberAnimation { to: 1; duration: 500 }
          }
        }
      }
    }
    tooltipText: "Local AI · " + root.title()
    onPressed: function(code) { if (code === Qt.RightButton && root.loaded) root.act(["open-agent"], true); else root.toggle() }
  }
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(200))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)
    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onActivateRequested: { if (root.loaded) root.act(["open-agent"], true); else if (root.rec) root.act(["load", root.rec.recipeId], false) }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)
        Text { width: parent.width; textFormat: Text.PlainText; text: root.title(); color: root.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.heading; font.weight: Font.Medium; elide: Text.ElideRight }
        Text { width: parent.width; textFormat: Text.PlainText; visible: root.status() !== ""; text: root.status(); color: root.dim; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight; maximumLineCount: 1 }
        Link { visible: !root.loaded; enabled: !root.busy && Boolean(root.rec); text: root.loadLabel(); onTriggered: root.act(["load", root.rec.recipeId], false) }
        Link { visible: root.loaded; text: "Open agent"; onTriggered: root.act(["open-agent"], true) }
        Link { visible: root.loaded && Boolean(root.share.available); enabled: !root.busy; text: root.share.active ? "Stop sharing" : "Share on Tailscale"; onTriggered: root.act(["share"], false) }
        Link { visible: root.hasActive; enabled: !root.busy; text: "Unload"; onTriggered: root.act(["unload"], false) }
      }
    }
  }
  component Link: Text {
    signal triggered()
    textFormat: Text.PlainText
    color: root.foreground; opacity: enabled ? 1 : 0.32; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight
    MouseArea { anchors.fill: parent; enabled: parent.enabled; hoverEnabled: true; cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: parent.triggered() }
  }
}
