import QtQuick
import Quickshell
import Quickshell.Io

// Owns the open/close lifecycle for a bar panel widget. Wraps the
// repetitive popupOpen + closePopout + toggle/show/hide IpcHandler triplet
// so each panel just declares one of these and binds its WidgetButton +
// KeyboardPanel to the exposed `open` property.
//
// Usage:
//   PanelController { id: ctrl; ipcTarget: "audioPanel" }
//
//   WidgetButton { onPressed: ctrl.toggle() }
//   KeyboardPanel { open: ctrl.open; owner: ctrl; focusTarget: keyCatcher }
//
// The bar popout coordinator uses `owner` as a registry key, so each
// PanelController instance doubles as that key. KeyboardPanel calls
// `owner.closePopout()` when another panel grabs the slot.
//
// Set `manageIpc: false` when the panel needs to declare its own IpcHandler
// for additional methods on the same target (monitorPanel adds brightness +
// state). Quickshell only honors one IpcHandler per target, so the panel's
// handler must then also delegate toggle/show/hide to this controller.
QtObject {
  id: root

  // IPC target name. The bar pairs this with the bar widget's filename so a
  // Hyprland keybind (`omarchy-shell <target> toggle`) summons the panel.
  property string ipcTarget: ""
  property bool manageIpc: true

  property bool open: false

  function toggle() { open = !open }
  function show() { if (!open) open = true }
  function hide() { open = false }
  function closePopout() { open = false }

  property IpcHandler _ipc: manageIpc ? ipcComponent.createObject(root) : null

  property Component ipcComponent: Component {
    IpcHandler {
      target: root.ipcTarget
      function toggle(): void { root.toggle() }
      function show(): void { root.show() }
      function hide(): void { root.hide() }
    }
  }
}
