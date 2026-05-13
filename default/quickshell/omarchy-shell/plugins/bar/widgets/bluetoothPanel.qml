import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "bluetoothPanel"
  property var settings: ({})

  property bool popupOpen: false

  function closePopout() { popupOpen = false }

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []

  readonly property var connectedDevices: {
    var list = []
    for (var i = 0; i < devices.length; i++)
      if (devices[i] && devices[i].connected) list.push(devices[i])
    return list
  }

  readonly property var knownDevices: {
    var list = []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (d && (d.paired || d.connected || d.bonded || d.trusted)) list.push(d)
    }
    list.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      return (a.name || a.deviceName || "").localeCompare(b.name || b.deviceName || "")
    })
    return list
  }

  readonly property string icon: {
    if (!adapter) return ""
    if (!adapter.enabled) return "󰂲"
    if (connectedDevices.length > 0) return "󰂱"
    return "󰂯"
  }

  visible: adapter !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    horizontalMargin: 8.5
    tooltipText: root.adapter ? (root.adapter.enabled ? "Bluetooth: " + root.connectedDevices.length + " connected" : "Bluetooth off") : ""

    onPressed: function(b) {
      if (b === Qt.RightButton && root.adapter) root.adapter.enabled = !root.adapter.enabled
      else if (b === Qt.MiddleButton) root.bar.run("omarchy-launch-bluetooth")
      else root.popupOpen = !root.popupOpen
    }
  }

  Common.PopupCard {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: 320
    contentHeight: column.implicitHeight + 28

    Column {
      id: column
      anchors.fill: parent
      spacing: 8

      Row {
        width: parent.width
        spacing: 8

        Text {
          text: "Bluetooth"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 13
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }

        Item { width: parent.width - 200; height: 1 }

        Common.PillButton {
          iconText: root.adapter && root.adapter.enabled ? "󰂯" : "󰂲"
          text: root.adapter && root.adapter.enabled ? "On" : "Off"
          foreground: root.bar.foreground
          horizontalPadding: 8
          verticalPadding: 4
          active: root.adapter && root.adapter.enabled
          onClicked: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
        }

        Common.PillButton {
          iconText: "󰂳"
          foreground: root.bar.foreground
          horizontalPadding: 8
          verticalPadding: 4
          enabled: root.adapter !== null && root.adapter.enabled
          opacity: enabled ? 1 : 0.4
          active: root.adapter && root.adapter.discovering
          onClicked: if (root.adapter) root.adapter.discovering = !root.adapter.discovering
        }
      }

      Repeater {
        model: root.knownDevices

        Common.PillButton {
          required property var modelData

          width: parent.width
          iconText: modelData && modelData.connected ? "󰂱" : "󰂯"
          text: {
            var label = modelData ? (modelData.deviceName || modelData.name || modelData.address || "Device") : ""
            if (modelData && modelData.batteryAvailable) label += "  " + Math.round(modelData.battery * 100) + "%"
            return label
          }
          foreground: root.bar.foreground
          horizontalPadding: 10
          verticalPadding: 6
          active: modelData && modelData.connected

          onClicked: {
            if (!modelData) return
            if (modelData.connected) modelData.disconnect()
            else modelData.connect()
          }
          onRightClicked: if (modelData) modelData.forget()
        }
      }

      Text {
        visible: root.knownDevices.length === 0
        text: root.adapter && root.adapter.enabled ? "Scanning for devices…" : "Turn Bluetooth on to scan"
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: 11
      }
    }
  }
}
