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

  onOpenedChanged: console.info(
    "omarchy-plugin-security stage=qml-panel-state decision="
      + (opened ? "opened" : "closed")
      + " surface=" + surfaceKey
      + " generation=" + generation
      + " input-sequence=" + lastIntentSequence)

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
    top: window.barPosition !== "bottom"
    bottom: window.barPosition === "bottom"
    left: window.barPosition === "left"
    right: window.barPosition !== "left"
  }
  margins {
    top: window.barPosition === "top" ? window.barInset + window.panelGap
      : window.barPosition !== "bottom" ? window.panelGap : 0
    bottom: window.barPosition === "bottom" ? window.barInset + window.panelGap : 0
    left: window.barPosition === "left" ? window.barInset + window.panelGap : 0
    right: window.barPosition === "right" ? window.barInset + window.panelGap
      : window.barPosition !== "left" ? window.panelGap : 0
  }
  implicitWidth: Math.min(maximumWidth, screen ? screen.width : maximumWidth)
  implicitHeight: Math.min(maximumHeight, screen ? screen.height : maximumHeight)
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-plugin-v2-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  mask: TrustedSurfaceInputMask {
    surface: remote
    dynamicInputRegions: window.dynamicInputRegions
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

  RemotePluginSurface {
    id: remote
    anchors.fill: parent
    Window.onWindowChanged: window.attachIfReady()
    onWidthChanged: window.attachIfReady()
    onHeightChanged: window.attachIfReady()
  }

  Component.onCompleted: {
    if (initiallyVisible) showOnChosenScreen("", "")
    attachIfReady()
  }
}
