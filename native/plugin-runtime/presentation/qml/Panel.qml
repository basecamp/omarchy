import QtQuick
Item {
  property string moduleName: ""
  property string ipcTarget: ""
  property bool manageIpc: false
  property var settings: ({})
  property var bar: null
  property color barForeground: "#e7e9ee"
  property bool opened: false
  function setting(name, fallback) { var value = settings[name]; return value === undefined ? fallback : value }
  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }
  function switchPanel(direction) {}
}
