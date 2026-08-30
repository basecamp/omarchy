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
  readonly property bool opened: panelController.open

  screen: host.screenFor(screenName)
  visible: screen !== null && opened
  anchors { top: true; right: true; bottom: true; left: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-plugin-v2-overlay"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // N8 follow-up: project generation-checked HostInputRegionRouter updates into this shell-owned Region; the full-item mask remains until that trusted bridge exists.
  mask: Region { item: remote }

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
    anchors.centerIn: parent
    Component.onCompleted: window.surfaceService.attach(window.surfaceKey, remote)
  }

  Component.onCompleted: panelController.open = initiallyVisible
}
