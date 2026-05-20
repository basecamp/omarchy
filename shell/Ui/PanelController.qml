import QtQuick
// Stores the open state for a shell panel. Panel owns the public lifecycle
// methods and IPC wiring; this object only keeps state separate from the
// panel implementation's own properties.
//
// Usage:
//   PanelController { id: panelController }
QtObject {
  id: root

  property bool open: false

  function toggle() { open = !open }
  function show() { if (!open) open = true }
  function hide() { open = false }
}
