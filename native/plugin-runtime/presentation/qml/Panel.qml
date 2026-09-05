import QtQuick

Item {
  property string moduleName: ""
  property string surfaceTarget: ""
  property var bar: null
  property var settings: runtime.settings
  property bool opened: true

  visible: opened
  width: 720
  height: 720

  function open() {
    opened = true
  }

  function close() {
    opened = false
    if (surfaceTarget !== "") runtime.requestSurfaceIntent(surfaceTarget, "dismiss")
  }

  function toggle() {
    if (surfaceTarget !== "") runtime.requestSurfaceIntent(surfaceTarget, "toggle")
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
}
