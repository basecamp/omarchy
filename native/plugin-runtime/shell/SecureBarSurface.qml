import QtQuick
import Omarchy.PluginHost 1.0

Item {
  id: root

  required property var surfaceService
  required property string surfaceKey
  required property string generation
  required property int maximumWidth
  required property int maximumHeight

  implicitWidth: maximumWidth
  implicitHeight: maximumHeight

  function attachIfReady() {
    if (!remote.connected && remote.Window.window !== null && remote.width > 0 && remote.height > 0)
      surfaceService.attach(surfaceKey, remote)
  }

  onSurfaceKeyChanged: attachIfReady()

  RemotePluginSurface {
    id: remote
    anchors.fill: parent
    Window.onWindowChanged: root.attachIfReady()
    onWidthChanged: root.attachIfReady()
    onHeightChanged: root.attachIfReady()
  }

  Component.onCompleted: attachIfReady()
}
