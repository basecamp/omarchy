import QtQuick
import Quickshell
import Quickshell.Wayland
import Omarchy.PluginHost 1.0
import qs.Ui

PanelWindow {
  id: window

  required property var host
  required property var surfaceService
  required property string surfaceKey
  required property string generation
  required property string screenName
  required property bool initiallyVisible
  required property int maximumWidth
  required property int maximumHeight
  required property bool dynamicInputRegions
  readonly property bool opened: panelController.open

  function attachIfReady() {
    if (!remote.connected && remote.Window.window !== null && remote.width > 0 && remote.height > 0)
      surfaceService.attach(surfaceKey, remote)
  }

  onSurfaceKeyChanged: attachIfReady()

  screen: host.screenFor(screenName)
  visible: screen !== null && opened
  anchors { top: true; right: true; bottom: true; left: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-plugin-v2-overlay"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: TrustedSurfaceInputMask {
    surface: remote
    dynamicInputRegions: window.dynamicInputRegions
  }

  PanelController { id: panelController }

  Connections {
    target: window.surfaceService
    function onOpenRequested(sourceSurface, targetSurface, generation) {
      if (targetSurface === window.surfaceKey && generation === window.generation) panelController.show()
    }
    function onToggleRequested(sourceSurface, targetSurface, generation) {
      if (targetSurface === window.surfaceKey && generation === window.generation) panelController.toggle()
    }
    function onDismissRequested(sourceSurface, targetSurface, generation) {
      if (targetSurface === window.surfaceKey && generation === window.generation) panelController.hide()
    }
  }

  RemotePluginSurface {
    id: remote
    width: Math.min(window.maximumWidth, window.width)
    height: Math.min(window.maximumHeight, window.height)
    // Keep the shell-owned placement integral. Fractional centering would
    // otherwise make an exact trusted region impossible to project without
    // rounding it wider or narrower than the admitted rectangle.
    x: Math.floor((window.width - width) / 2)
    y: Math.floor((window.height - height) / 2)
    Window.onWindowChanged: window.attachIfReady()
    onWidthChanged: window.attachIfReady()
    onHeightChanged: window.attachIfReady()
  }

  Component.onCompleted: {
    panelController.open = initiallyVisible
    attachIfReady()
  }
}
