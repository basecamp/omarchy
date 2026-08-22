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

  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function openDestination(id) {
    if (root.shell) root.shell.toggle(id, "{}")
    root.close()
  }

  PanelWindow {
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 360
    implicitHeight: 420
    WlrLayershell.namespace: "omarchy-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors.bottom: true
    anchors.right: true
    margins.bottom: 48
    margins.right: 12

    Rectangle {
      anchors.fill: parent
      color: Tokens.surface.glass
      radius: Tokens.radius.large
      border.color: Tokens.border.subtle
      border.width: 1

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        Text {
          text: "Settings"
          color: Tokens.text.primary
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
        }

        Text {
          text: "These destinations open the existing system surfaces. A full Settings app lands in a later slice."
          color: Tokens.text.secondary
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: [
            { label: "Display", id: "omarchy.monitor" },
            { label: "Sound", id: "omarchy.audio" },
            { label: "Network", id: "omarchy.network" },
            { label: "Bluetooth", id: "omarchy.bluetooth" },
            { label: "Power", id: "omarchy.power" }
          ]
          delegate: Button {
            Layout.fillWidth: true
            text: modelData.label
            onClicked: root.openDestination(modelData.id)
          }
        }

        Item { Layout.fillHeight: true }
      }
    }

    PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: root.close()
    }
  }
}
