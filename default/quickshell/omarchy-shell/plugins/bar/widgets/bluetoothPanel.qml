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
      spacing: 10

      // Header: title left, on/off toggle right.
      Item {
        width: parent.width
        height: titleText.implicitHeight

        Text {
          id: titleText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Bluetooth"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 13
          font.bold: true
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4

          Common.PillButton {
            iconText: "󰂳"
            tooltipText: !root.adapter ? "" : !root.adapter.enabled ? "Bluetooth is off"
              : root.adapter.discovering ? "Stop scanning" : "Scan for devices"
            foreground: root.bar.foreground
            horizontalPadding: 6
            verticalPadding: 4
            iconSize: 14
            enabled: root.adapter !== null && root.adapter.enabled
            opacity: enabled ? 1 : 0.4
            active: root.adapter && root.adapter.discovering
            onClicked: if (root.adapter) root.adapter.discovering = !root.adapter.discovering
          }

          Common.PillButton {
            iconText: "󱁤"
            tooltipText: "Open Impala (TUI)"
            foreground: root.bar.foreground
            horizontalPadding: 6
            verticalPadding: 4
            iconSize: 14
            onClicked: { root.bar.run("omarchy-launch-bluetooth"); root.popupOpen = false }
          }

          Common.PillButton {
            iconText: root.adapter && root.adapter.enabled ? "󰂯" : "󰂲"
            text: root.adapter && root.adapter.enabled ? "On" : "Off"
            tooltipText: root.adapter && root.adapter.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on"
            foreground: root.bar.foreground
            horizontalPadding: 10
            verticalPadding: 4
            active: root.adapter && root.adapter.enabled
            onClicked: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
          }
        }
      }

      // Paired / known devices.
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
          tooltipText: modelData && modelData.connected ? "Click to disconnect · right-click to forget"
                                                       : "Click to connect · right-click to forget"
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

      // Discovered (unpaired) devices, only shown while scanning.
      Text {
        visible: root.adapter && root.adapter.discovering && root.discoveredDevices.length > 0
        text: "Discovered"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: 10
        font.bold: true
      }

      Repeater {
        model: root.adapter && root.adapter.discovering ? root.discoveredDevices : []

        Common.PillButton {
          required property var modelData

          width: parent.width
          iconText: "󰂯"
          text: modelData ? (modelData.deviceName || modelData.name || modelData.address || "Unknown") : ""
          tooltipText: "Click to pair and connect"
          foreground: Qt.darker(root.bar.foreground, 1.2)
          horizontalPadding: 10
          verticalPadding: 6

          onClicked: {
            if (!modelData) return
            modelData.pair()
          }
        }
      }

      Text {
        visible: root.knownDevices.length === 0
                 && (!root.adapter || !root.adapter.discovering || root.discoveredDevices.length === 0)
        text: !root.adapter ? "No Bluetooth adapter"
            : !root.adapter.enabled ? "Turn Bluetooth on to scan"
            : root.adapter.discovering ? "Scanning for devices…"
            : "No paired devices. Tap the scan icon to find new ones."
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        width: parent.width
      }
    }
  }
}
