import QtQuick
import Quickshell
import Quickshell.Wayland
import Omarchy.PluginHost 1.0
import qs.Commons
import qs.Ui

PanelWindow {
  id: window

  required property var host
  required property var surfaceService
  required property string surfaceKey
  required property string generation
  required property bool initiallyVisible
  required property int maximumWidth
  required property int maximumHeight
  required property bool dynamicInputRegions
  readonly property bool opened: panelController.open
  property var assignedScreen: null
  property string lastIntentSequence: "0"
  readonly property var bar: host && host.shell ? host.shell.bar : null
  readonly property string barPosition: bar ? String(bar.position || "top") : "top"
  readonly property int barInset: bar && !bar.barHidden
    ? Math.max(0, Number(bar.barSize || 0)) : 0
  readonly property int panelGap: Style.space(8)

  onOpenedChanged: {
    console.info("omarchy-plugin-security stage=qml-panel-state decision="
      + (opened ? "opened" : "closed")
      + " surface=" + surfaceKey
      + " generation=" + generation
      + " input-sequence=" + lastIntentSequence)
    if (bar) {
      if (opened) bar.requestPopout(window)
      else bar.releasePopout(window)
    }
  }

  function close() { panelController.hide() }

  function attachIfReady() {
    if (!remote.connected && remote.Window.window !== null && remote.width > 0 && remote.height > 0)
      surfaceService.attach(surfaceKey, remote)
  }

  onSurfaceKeyChanged: attachIfReady()

  function showOnChosenScreen(sourceSurface, requestedOutput) {
    assignedScreen = host.screenForIntent(sourceSurface || "", requestedOutput || "")
    if (assignedScreen !== null) panelController.show()
  }

  function toggleOnChosenScreen(sourceSurface, requestedOutput) {
    if (opened) {
      panelController.hide()
    } else {
      showOnChosenScreen(sourceSurface, requestedOutput)
    }
  }

  function handleIntent(action, sourceSurface, targetSurface, intentGeneration, inputSequence, requestedOutput) {
    if (targetSurface !== surfaceKey || intentGeneration !== generation) return

    lastIntentSequence = inputSequence
    console.info("omarchy-plugin-security stage=qml-panel-signal decision=matched"
      + " action=" + action + " source=" + sourceSurface
      + " target=" + targetSurface + " generation=" + intentGeneration
      + " input-sequence=" + inputSequence)

    if (action === "open") {
      showOnChosenScreen(sourceSurface, requestedOutput)
    } else if (action === "toggle") {
      toggleOnChosenScreen(sourceSurface, requestedOutput)
    } else if (action === "dismiss") {
      panelController.hide()
    }
  }

  screen: assignedScreen
  // showOnChosenScreen() assigns the target before opening. Do not read the
  // PanelWindow screen back through visible: Quickshell's screen selection
  // itself participates in window visibility and that creates a binding loop.
  visible: opened
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-plugin-v2-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  // The trusted host owns dismissal. Keep the bar strip click-through so the
  // same icon can close the panel and another icon can replace it directly.
  // Input admitted to the remote item remains constrained by that item's
  // authenticated worker regions; the rest reaches dismissArea instead.
  mask: Region {
    x: window.barPosition === "left" ? window.barInset : 0
    y: window.barPosition === "top" ? window.barInset : 0
    width: Math.max(0, window.width
      - ((window.barPosition === "left" || window.barPosition === "right")
        ? window.barInset : 0))
    height: Math.max(0, window.height
      - ((window.barPosition === "top" || window.barPosition === "bottom")
        ? window.barInset : 0))
  }

  PanelController { id: panelController }

  Connections {
    target: window.surfaceService
    function onOpenRequested(sourceSurface, targetSurface, generation, inputSequence, requestedOutput) {
      window.handleIntent("open", sourceSurface, targetSurface, generation, inputSequence, requestedOutput)
    }
    function onToggleRequested(sourceSurface, targetSurface, generation, inputSequence, requestedOutput) {
      window.handleIntent("toggle", sourceSurface, targetSurface, generation, inputSequence, requestedOutput)
    }
    function onDismissRequested(sourceSurface, targetSurface, generation, inputSequence) {
      window.handleIntent("dismiss", sourceSurface, targetSurface, generation, inputSequence)
    }
  }

  MouseArea {
    id: dismissArea
    anchors.fill: parent
    enabled: window.opened
    acceptedButtons: Qt.AllButtons
    onPressed: panelController.hide()
  }

  RemotePluginSurface {
    id: remote
    x: window.barPosition === "left"
      ? window.barInset + window.panelGap
      : window.width - width - (window.barPosition === "right"
        ? window.barInset + window.panelGap : window.panelGap)
    y: window.barPosition === "bottom"
      ? window.height - window.barInset - window.panelGap - height
      : (window.barPosition === "top" ? window.barInset : 0) + window.panelGap
    width: Math.min(window.maximumWidth,
      Math.max(0, window.width - window.barInset - window.panelGap))
    height: Math.min(window.maximumHeight,
      Math.max(0, window.height - window.barInset - window.panelGap))
    Window.onWindowChanged: window.attachIfReady()
    onWidthChanged: window.attachIfReady()
    onHeightChanged: window.attachIfReady()
  }

  // A click on another output is outside this panel too. These trusted,
  // transparent surfaces never forward input to the plugin.
  Variants {
    model: window.opened ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        required property var modelData

        screen: modelData
        visible: window.opened && !!window.screen
          && modelData.name !== window.screen.name
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-plugin-v2-panel-dismiss"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onPressed: panelController.hide()
        }
      }
    }
  }

  Component.onCompleted: {
    if (initiallyVisible) showOnChosenScreen("", "")
    attachIfReady()
  }
}
