import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string target: "active"

  readonly property var windowService: shell ? shell.windowService : null

  function open(payloadJson) {
    root.target = "active"
    try {
      var payload = JSON.parse(payloadJson || "{}")
      if (payload && payload.address) root.target = String(payload.address)
    } catch (e) {
    }
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function pick(side) {
    if (!windowService || typeof windowService.snapTo !== "function")
      return
    windowService.snapTo(root.target, side)
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide("omarchy.ultimate-snap-chooser")
  }

  function saveLayout() {
    if (!windowService || typeof windowService.saveLayout !== "function")
      return
    windowService.saveLayout()
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide("omarchy.ultimate-snap-chooser")
  }

  function restoreLayout() {
    if (!windowService || typeof windowService.restoreLayout !== "function")
      return
    windowService.restoreLayout()
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide("omarchy.ultimate-snap-chooser")
  }

  Loader {
    active: root.opened
    sourceComponent: PanelWindow {
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "omarchy-snap-chooser"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    MouseArea {
      anchors.fill: parent
      onClicked: {
        root.close()
        if (root.shell) root.shell.hide("omarchy.ultimate-snap-chooser")
      }
    }

    Rectangle {
      anchors.centerIn: parent
      width: 420
      height: 340
      color: Tokens.surface.glass
      radius: Tokens.radius.large
      border.color: Tokens.border.subtle
      border.width: 1

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        Text {
          width: parent.width
          text: "Snap"
          color: Tokens.text.primary
          font.pixelSize: Style.font.body
          font.family: "sans-serif"
        }

        Row {
          spacing: 8
          Repeater {
            model: [
              { side: "l", label: "Left" },
              { side: "max", label: "Maximize" },
              { side: "r", label: "Right" }
            ]
            delegate: SnapCell {
              width: 124
              height: 56
              label: modelData.label
              onPicked: root.pick(modelData.side)
            }
          }
        }

        Grid {
          columns: 2
          columnSpacing: 8
          rowSpacing: 8
          Repeater {
            model: [
              { side: "tl", label: "Top left" },
              { side: "tr", label: "Top right" },
              { side: "bl", label: "Bottom left" },
              { side: "br", label: "Bottom right" }
            ]
            delegate: SnapCell {
              width: 190
              height: 64
              label: modelData.label
              onPicked: root.pick(modelData.side)
            }
          }
        }

        Row {
          spacing: 8
          Repeater {
            model: [
              { label: "Save layout", action: "save" },
              { label: "Restore layout", action: "restore" }
            ]
            delegate: SnapCell {
              width: 190
              height: 40
              label: modelData.label
              onPicked: {
                if (modelData.action === "save") root.saveLayout()
                else root.restoreLayout()
              }
            }
          }
        }
      }
    }
    }
  }
}
