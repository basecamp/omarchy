import QtQuick
import Quickshell.Io

// Base item for shell panels. Panels are not bar widgets, but the bar may host
// or toggle them and injects the same ambient context while doing so. The base
// owns the shared IPC-backed open/close lifecycle; panel implementations own
// their button behavior, keyboard navigation, and content.
Item {
  id: root

  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})
  property string ipcTarget: ""
  property bool manageIpc: true
  property alias controller: panelController
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false

  readonly property bool opened: panelController.open

  function open() { panelController.show() }
  function close() { panelController.hide() }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }
  function toggle() { opened ? close() : open() }

  // Read a single value from this panel's inline shell.json entry, with a
  // fallback for missing/null values. Matches BarWidget.setting().
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  PanelController {
    id: panelController
  }

  property IpcHandler _ipc: manageIpc ? ipcComponent.createObject(root) : null

  property Component ipcComponent: Component {
    IpcHandler {
      target: root.ipcTarget
      function open(): void { root.open() }
      function close(): void { root.close() }
      function show(): void { root.open() }
      function hide(): void { root.close() }
      function toggle(): void { root.toggle() }
    }
  }
}
