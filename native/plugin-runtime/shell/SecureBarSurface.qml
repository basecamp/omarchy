import QtQuick
import Omarchy.PluginHost 1.0

Item {
  id: root

  required property var surfaceService
  required property string surfaceKey
  required property string generation
  required property int maximumWidth
  required property int maximumHeight
  property var bar: null
  property int attachAttempts: 0
  readonly property int maximumAttachAttempts: 40
  // Native RemotePluginSurface owns exact pointer/touch routing into the
  // sandbox. The bar must not cover it with its ordinary click/reorder layer.
  readonly property bool routesOwnPointerInput: true
  readonly property bool barReady: bar !== null
    && bar !== undefined
    && typeof bar.vertical === "boolean"
    && typeof bar.barSize === "number"
    && isFinite(bar.barSize)
    && bar.barSize > 0
    && typeof bar.statusSlot === "number"
    && isFinite(bar.statusSlot)
    && bar.statusSlot > 0

  // The manifest is an upper bound, not a request for a wide custom slot.
  // Match ordinary status icons along the bar and retain shell-owned thickness
  // across it, so secure plugins participate in the native bar layout.
  implicitWidth: !barReady ? 0 : Math.min(maximumWidth, bar.vertical ? bar.barSize : bar.statusSlot)
  implicitHeight: !barReady ? 0 : Math.min(maximumHeight, bar.vertical ? bar.statusSlot : bar.barSize)

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
