import QtQuick
import Omarchy.PluginHost 1.0

Item {
  id: root

  required property var surfaceService
  required property string surfaceKey
  required property string generation
  required property int maximumWidth
  required property int maximumHeight
  property int attachAttempts: 0
  readonly property int maximumAttachAttempts: 40

  implicitWidth: maximumWidth
  implicitHeight: maximumHeight

  function attachIfReady() {
    if (remote.connected) {
      attachRetry.stop()
      return
    }
    if (remote.Window.window === null || remote.width <= 0 || remote.height <= 0) return
    if (surfaceService.attach(surfaceKey, remote)) {
      attachRetry.stop()
      return
    }
    if (attachAttempts < maximumAttachAttempts) {
      attachAttempts++
      attachRetry.restart()
    }
  }

  function retryAttach() {
    attachAttempts = 0
    attachIfReady()
  }

  onSurfaceKeyChanged: retryAttach()

  Timer {
    id: attachRetry
    interval: 25
    onTriggered: root.attachIfReady()
  }

  RemotePluginSurface {
    id: remote
    anchors.fill: parent
    Window.onWindowChanged: root.retryAttach()
    onWidthChanged: root.retryAttach()
    onHeightChanged: root.retryAttach()
  }

  Component.onCompleted: retryAttach()
}
