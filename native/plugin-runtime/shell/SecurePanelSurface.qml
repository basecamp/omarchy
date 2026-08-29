import QtQuick
import Quickshell
import Quickshell.Wayland
import Omarchy.PluginHost 1.0
import qs.Ui

PanelWindow {
  id: window

  required property var host
  required property var surfaceService
  required property var declaration
  readonly property bool opened: panelController.open

  screen: host.screenFor(declaration.screenName)
  visible: screen !== null && opened
  anchors { top: true; right: true; bottom: true }
  implicitWidth: Math.min(declaration.maximumWidth, screen ? screen.width : declaration.maximumWidth)
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-plugin-v2-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  mask: Region { item: remote }

  PanelController { id: panelController }

  Connections {
    target: window.surfaceService
    function onOpenRequested(sourceSurface, targetSurface, generation) {
      if (targetSurface === window.declaration.surfaceKey) panelController.show()
    }
    function onToggleRequested(sourceSurface, targetSurface, generation) {
      if (targetSurface === window.declaration.surfaceKey) panelController.toggle()
    }
    function onDismissRequested(sourceSurface, targetSurface, generation) {
      if (targetSurface === window.declaration.surfaceKey) panelController.hide()
    }
  }

  RemotePluginSurface {
    id: remote
    anchors.fill: parent
    Component.onCompleted: window.surfaceService.attach(window.declaration.surfaceKey, remote)
  }

  Component.onCompleted: panelController.open = declaration.visible === true
}
