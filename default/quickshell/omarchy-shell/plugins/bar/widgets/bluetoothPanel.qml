import QtQuick
import QtQuick.Controls
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
            tooltipBackground: root.bar.background
            tooltipForeground: root.bar.foreground
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
            tooltipBackground: root.bar.background
            tooltipForeground: root.bar.foreground
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
            tooltipBackground: root.bar.background
            tooltipForeground: root.bar.foreground
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
        DeviceRow {
          required property var modelData
          width: parent.width
          dev: modelData
          isDiscovered: false
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
        DeviceRow {
          required property var modelData
          width: parent.width
          dev: modelData
          isDiscovered: true
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

  // Two-line device row showing name + live status (Connected, Connecting…,
  // Pairing…, Failed). Tracks pending click attempts with a Timer so a
  // connect that drops back to Disconnected within 10s surfaces as "Failed".
  component DeviceRow: Rectangle {
    id: row
    required property var dev
    required property bool isDiscovered

    readonly property bool isConnected: dev && dev.connected
    readonly property int devState: dev && dev.state !== undefined ? dev.state : -1

    // 0 idle, 1 connecting, 2 disconnecting, 3 pairing, 4 failed.
    property int pendingAction: 0
    property string failureReason: ""

    // Heuristic: while pendingAction is set, the connect/pair attempt is
    // expected to land within ~10s. If state stays Disconnected past that, we
    // declare failure. Cleared as soon as state reaches Connected.
    Timer {
      id: failureTimer
      interval: 10000
      repeat: false
      onTriggered: {
        if (row.pendingAction === 1 && !row.isConnected) {
          row.pendingAction = 4
          row.failureReason = "Could not connect"
        } else if (row.pendingAction === 3 && row.dev && !row.dev.paired) {
          row.pendingAction = 4
          row.failureReason = "Pairing failed"
        } else {
          row.pendingAction = 0
          row.failureReason = ""
        }
      }
    }

    Connections {
      target: row.dev || null
      function onConnectedChanged() {
        if (row.isConnected) { row.pendingAction = 0; row.failureReason = "" }
      }
      function onPairedChanged() {
        if (row.dev && row.dev.paired && row.pendingAction === 3) {
          row.pendingAction = 0
        }
      }
    }

    readonly property string statusText: {
      if (!dev) return ""
      if (pendingAction === 4) return failureReason || "Failed"
      if (pendingAction === 1 || devState === 3) return "Connecting\u2026"
      if (pendingAction === 2 || devState === 2) return "Disconnecting\u2026"
      if (pendingAction === 3 || (dev.pairing === true)) return "Pairing\u2026"
      if (isConnected) {
        if (dev.batteryAvailable) return "Connected · " + Math.round(dev.battery * 100) + "%"
        return "Connected"
      }
      if (isDiscovered) return "Available · click to pair"
      return "Paired"
    }

    readonly property color statusColor: {
      if (pendingAction === 4) return root.bar.urgent
      if (isConnected) return root.bar.foreground
      if (pendingAction === 1 || devState === 3 || pendingAction === 3) return root.bar.foreground
      return Qt.darker(root.bar.foreground, 1.5)
    }

    implicitHeight: rowContent.implicitHeight + 12
    radius: 4
    color: rowMouse.containsMouse
      ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.10)
      : (isConnected ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.05) : "transparent")

    Behavior on color { ColorAnimation { duration: 120 } }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      implicitHeight: Math.max(icon.implicitHeight, info.implicitHeight, disconnectBtn.implicitHeight)

      Text {
        id: icon
        text: row.isConnected ? "󰂱" : "󰂯"
        color: row.statusColor
        font.family: root.bar.fontFamily
        font.pixelSize: 16
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      // Explicit close button on any known device. Action depends on state:
      // connected -> disconnect, otherwise -> forget the pairing entirely.
      Rectangle {
        id: disconnectBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        height: 22
        radius: 4
        visible: !row.isDiscovered
        readonly property string action: row.isConnected ? "Disconnect" : "Forget"
        color: disconnectMouse.containsMouse
          ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g, root.bar.urgent.b, 0.20)
          : "transparent"

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
          anchors.centerIn: parent
          text: "󰅙"
          color: disconnectMouse.containsMouse ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.3)
          font.family: root.bar.fontFamily
          font.pixelSize: 14
        }

        MouseArea {
          id: disconnectMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton

          onClicked: {
            if (!row.dev) return
            if (row.isConnected) {
              row.pendingAction = 2
              failureTimer.stop()
              row.dev.disconnect()
            } else if (row.dev.forget) {
              row.dev.forget()
            }
          }
        }

        ToolTip {
          visible: disconnectMouse.containsMouse
          text: disconnectBtn.action
          delay: 400
          padding: 0
          background: Rectangle {
            color: root.bar.background
            border.color: root.bar.foreground
            border.width: 1
            radius: 0
            opacity: 0.97
          }
          contentItem: Text {
            text: disconnectBtn.action
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: 11
            leftPadding: 10
            rightPadding: 10
            topPadding: 6
            bottomPadding: 6
          }
        }
      }

      Column {
        id: info
        spacing: 1
        anchors.left: icon.right
        anchors.leftMargin: 10
        anchors.right: disconnectBtn.visible ? disconnectBtn.left : parent.right
        anchors.rightMargin: disconnectBtn.visible ? 8 : 0
        anchors.verticalCenter: parent.verticalCenter

        Text {
          text: row.dev ? (row.dev.deviceName || row.dev.name || row.dev.address || "Device") : ""
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 12
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          visible: row.statusText !== ""
          text: row.statusText
          color: row.statusColor
          font.family: root.bar.fontFamily
          font.pixelSize: 10
          elide: Text.ElideRight
          width: parent.width
        }
      }
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: row.dev ? Qt.PointingHandCursor : Qt.ArrowCursor

      onClicked: function(mouse) {
        if (!row.dev) return
        if (mouse.button === Qt.RightButton) {
          if (row.dev.forget) row.dev.forget()
          return
        }
        if (row.isDiscovered) {
          row.pendingAction = 3
          row.failureReason = ""
          failureTimer.restart()
          row.dev.pair()
          return
        }
        if (row.isConnected) return  // use the X button to disconnect
        row.pendingAction = 1
        row.failureReason = ""
        failureTimer.restart()
        row.dev.connect()
      }
    }
  }
}
