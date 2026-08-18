import QtQuick

// Registers the painted portion of a plugin panel as a capture target.
// Layer-shell panels often span the full output with a transparent backdrop,
// so compositor window geometry cannot describe the card the user sees.
QtObject {
  id: root

  required property var shell
  required property var window
  required property Item item
  required property string targetId
  property bool active: true
  property var registeredShell: null

  function syncRegistration() {
    if (registeredShell === shell) return
    if (registeredShell && registeredShell.unregisterCaptureTarget)
      registeredShell.unregisterCaptureTarget(root)
    registeredShell = shell
    if (registeredShell && registeredShell.registerCaptureTarget)
      registeredShell.registerCaptureTarget(root)
  }

  function captureGeometry() {
    if (!active || !window || !window.screen || !item || !item.visible || item.width <= 0 || item.height <= 0) return null
    var points = [
      item.mapToItem(null, 0, 0),
      item.mapToItem(null, item.width, 0),
      item.mapToItem(null, 0, item.height),
      item.mapToItem(null, item.width, item.height)
    ]
    var left = points[0].x
    var top = points[0].y
    var right = points[0].x
    var bottom = points[0].y
    for (var i = 1; i < points.length; i++) {
      left = Math.min(left, points[i].x)
      top = Math.min(top, points[i].y)
      right = Math.max(right, points[i].x)
      bottom = Math.max(bottom, points[i].y)
    }
    return {
      id: targetId,
      screen: String(window.screen.name || ""),
      x: Math.round(window.screen.x + left),
      y: Math.round(window.screen.y + top),
      width: Math.round(right - left),
      height: Math.round(bottom - top),
      visible: true
    }
  }

  onShellChanged: syncRegistration()
  Component.onCompleted: syncRegistration()
  Component.onDestruction: {
    if (registeredShell && registeredShell.unregisterCaptureTarget)
      registeredShell.unregisterCaptureTarget(root)
  }
}
