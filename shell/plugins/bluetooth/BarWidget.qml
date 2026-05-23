import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "omarchy.bluetooth"
  ipcTarget: "omarchy.bluetooth"

  // Address -> "connecting" | "disconnecting" | "forgetting".
  // The actual Bluetooth sequencing lives in bin/omarchy-bluetooth-device;
  // this map only keeps the panel responsive while BlueZ catches up.
  property var pendingActions: ({})

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []

  function deviceLabel(device) {
    if (!device) return ""
    return String(device.deviceName || device.name || "").trim()
  }

  function isUuidLike(value) {
    var text = (value || "").trim()
    if (text === "") return false
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)
      || /^[0-9a-f]{32}$/i.test(text)
      || /^0x[0-9a-f]{4,32}$/i.test(text)
      || /^0000[0-9a-f]{4}-0000-1000-8000-00805f9b34fb$/i.test(text)
  }

  function isAddressLike(value) {
    var text = (value || "").trim()
    return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(text)
  }

  function hasHumanName(device) {
    var label = deviceLabel(device)
    return label !== "" && !isUuidLike(label) && !isAddressLike(label)
  }

  readonly property var connectedDevices: {
    var list = []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (d && d.connected && hasHumanName(d)) list.push(d)
    }
    list.sort(function(a, b) {
      return deviceLabel(a).localeCompare(deviceLabel(b))
    })
    return list
  }

  readonly property var knownDevices: {
    var list = []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (d && hasHumanName(d) && !d.connected && (d.paired || d.bonded || d.trusted)) list.push(d)
    }
    list.sort(function(a, b) {
      return deviceLabel(a).localeCompare(deviceLabel(b))
    })
    return list
  }

  readonly property var discoveredDevices: {
    var list = []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (!d || !hasHumanName(d)) continue
      if (d.connected || d.paired || d.bonded || d.trusted) continue
      list.push(d)
    }
    list.sort(function(a, b) {
      return deviceLabel(a).localeCompare(deviceLabel(b))
    })
    return list
  }

  readonly property string icon: {
    if (!adapter) return ""
    if (!adapter.enabled) return "󰂲"
    if (connectedDevices.length > 0) return "󰂱"
    return "󰂯"
  }

  property int phraseIndex: 0
  readonly property var activePhrases: [
    "Untangling wires",
    "Streaming vikings",
    "Pairing mysteries",
    "Herding headsets",
    "Taming radios",
    "Summoning speakers",
    "Wrangling codecs",
    "Polishing packets"
  ]
  readonly property bool rotatingPhrases: adapter && adapter.enabled
  readonly property string heroStatusText: {
    if (!adapter) return "No adapter"
    if (!adapter.enabled) return "Bluetooth off"
    return activePhrases[phraseIndex % activePhrases.length]
  }

  // Single cursor model shared by keyboard and mouse. Sections:
  //   "connected"  — currently connected devices; Enter disconnects.
  //   "known"      — remembered devices; Enter connects.
  //   "discovered" — unremembered devices visible while scanning; Enter connects.
  // Visuals always come from CursorSurface (hasCursor / current),
  // never from containsMouse. Mouse hover updates root cursor state too,
  // guaranteeing one highlight on screen.
  property string focusSection: "connected"
  property int selectedIndex: 0
  property bool actionFocused: false
  property bool cursorActive: false

  // Stable identity for the focused device. Devices move between sections as
  // they connect, disconnect, pair, or get forgotten, so follow the BlueZ
  // address across section changes instead of preserving a stale row index.
  property string focusedDeviceAddress: ""

  readonly property color hoverFill: bar
    ? Style.hoverFillFor(bar.foreground, Color.accent)
    : "transparent"
  readonly property color selectedFill: bar
    ? Style.selectedFillFor(bar.foreground, Color.accent)
    : "transparent"

  function sectionCount(section) {
    if (section === "connected") return connectedDevices.length
    if (section === "known") return knownDevices.length
    if (section === "discovered") return discoveredDevices.length
    return 0
  }

  function sectionVisible(section) {
    if (section === "connected") return connectedDevices.length > 0
    if (section === "known") return knownDevices.length > 0
    if (section === "discovered") return adapter && adapter.discovering && discoveredDevices.length > 0
    return false
  }

  readonly property var visibleSections: {
    var list = []
    if (sectionVisible("connected")) list.push("connected")
    if (sectionVisible("known")) list.push("known")
    if (sectionVisible("discovered")) list.push("discovered")
    return list
  }

  function devicesForSection(section) {
    if (section === "connected") return connectedDevices
    if (section === "known") return knownDevices
    if (section === "discovered") return discoveredDevices
    return []
  }

  function deviceAt(section, index) {
    var list = devicesForSection(section)
    return index >= 0 && index < list.length ? list[index] : null
  }

  function cloneMap(map) {
    var next = ({})
    for (var key in map) next[key] = map[key]
    return next
  }

  function pendingAction(address) {
    return address && pendingActions[address] ? pendingActions[address] : ""
  }

  function setPendingAction(address, action) {
    if (!address) return
    var next = cloneMap(pendingActions)
    if (action) next[address] = action
    else delete next[address]
    pendingActions = next
    if (action) pendingTimeout.restart()
  }

  function deviceCommand(action, address) {
    var command = root.bar && root.bar.omarchyPath
      ? root.bar.omarchyPath + "/bin/omarchy-bluetooth-device"
      : "omarchy-bluetooth-device"
    return [command, action, address]
  }

  function runDeviceAction(device, action, pending) {
    if (!device || !device.address) return
    setPendingAction(device.address, pending)
    Quickshell.execDetached(deviceCommand(action, device.address))
  }

  function connectDevice(device) {
    if (!device || device.connected) return
    if (device.paired || device.bonded || device.trusted) runDeviceAction(device, "connect", "connecting")
    else runDeviceAction(device, "pair", "connecting")
  }

  function disconnectDevice(device) {
    if (!device || !device.address) return
    if (!device.connected) return
    setPendingAction(device.address, "disconnecting")
    if (device.disconnect) device.disconnect()
    Quickshell.execDetached(deviceCommand("disconnect", device.address))
  }

  function forgetDevice(device) {
    if (!device || !device.address) return
    runDeviceAction(device, "forget", "forgetting")
  }

  function syncPendingActions() {
    var next = cloneMap(pendingActions)
    var changed = false

    for (var address in next) {
      var action = next[address]
      var found = null

      for (var i = 0; i < devices.length; i++) {
        var d = devices[i]
        if (d && d.address === address) {
          found = d
          break
        }
      }

      if ((action === "connecting" && found && found.connected)
          || (action === "disconnecting" && found && !found.connected)
          || (action === "forgetting" && (!found || (!found.paired && !found.bonded && !found.trusted)))) {
        delete next[address]
        changed = true
      }
    }

    if (changed) pendingActions = next
  }

  // j/k navigates between device sections row-by-row.
  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) { focusSection = sections[0]; selectedIndex = 0; actionFocused = false; return }

    var idx = selectedIndex
    var max = sectionCount(focusSection) - 1

    if (delta > 0) {
      if (idx < max) { selectedIndex = idx + 1; actionFocused = false; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = 0
        actionFocused = false
      }
    } else {
      if (idx > 0) { selectedIndex = idx - 1; actionFocused = false; return }
      if (sIdx > 0) {
        focusSection = sections[sIdx - 1]
        selectedIndex = sectionCount(focusSection) - 1
        actionFocused = false
      }
    }
  }

  function moveCursorH(delta) {
    if (!cursorActive) { cursorActive = true; return }
    if (focusSection !== "known") return
    var dev = deviceAt(focusSection, selectedIndex)
    if (!dev || dev.connected) return
    if (delta > 0) actionFocused = true
    else if (delta < 0) actionFocused = false
  }

  function activateCursor() {
    if (actionFocused) {
      deleteSelected()
      return
    }

    if (focusSection === "connected" || focusSection === "known") {
      var dev = deviceAt(focusSection, selectedIndex)
      if (!dev) return
      if (dev.connected) disconnectDevice(dev)
      else connectDevice(dev)
      return
    }
    if (focusSection === "discovered") {
      var d = discoveredDevices[selectedIndex]
      if (!d) return
      connectDevice(d)
    }
  }

  // 'x' forgets remembered devices. Connected rows toggle connection via
  // Enter/click, so the destructive forget action is intentionally unavailable
  // while connected.
  function deleteSelected() {
    if (focusSection !== "known") return
    var dev = deviceAt(focusSection, selectedIndex)
    if (!dev) return
    forgetDevice(dev)
  }

  onOpenedChanged: {
    if (opened) {
      if (adapter && adapter.enabled && !adapter.discovering) adapter.discovering = true
      if (connectedDevices.length > 0) { focusSection = "connected"; selectedIndex = 0 }
      else if (knownDevices.length > 0) { focusSection = "known"; selectedIndex = 0 }
      else if (discoveredDevices.length > 0) { focusSection = "discovered"; selectedIndex = 0 }
      actionFocused = false
      cursorActive = false
    }
  }

  function updateFocusedAddress() {
    var d = deviceAt(focusSection, selectedIndex)
    focusedDeviceAddress = d ? (d.address || "") : ""
  }

  function reselectFocusedDevice() {
    if (focusedDeviceAddress === "") {
      clampCursor()
      return
    }

    var sections = ["connected", "known", "discovered"]
    for (var s = 0; s < sections.length; s++) {
      var section = sections[s]
      if (!sectionVisible(section)) continue
      var list = devicesForSection(section)
      for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].address === focusedDeviceAddress) {
          focusSection = section
          selectedIndex = i
          clampCursor()
          return
        }
      }
    }

    clampCursor()
  }

  onSelectedIndexChanged: updateFocusedAddress()
  onFocusSectionChanged: updateFocusedAddress()
  onConnectedDevicesChanged: { reselectFocusedDevice(); syncPendingActions() }
  onKnownDevicesChanged: { reselectFocusedDevice(); syncPendingActions() }
  onDiscoveredDevicesChanged: { reselectFocusedDevice(); syncPendingActions() }
  onVisibleSectionsChanged: clampCursor()

  // Keep the keyboard-focused row inside the visible viewport of the device
  // Flickable. Each DeviceRow calls this when it gains hasCursor. Without
  // it, j/k can walk the selection off-screen in a long device list.
  function ensureCursorVisible(item) {
    if (!item || !deviceFlick) return
    var pt = item.mapToItem(deviceFlick.contentItem, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = deviceFlick.contentY
    var viewBottom = viewTop + deviceFlick.height
    var margin = 6
    if (top < viewTop + margin) deviceFlick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      deviceFlick.contentY = bottom + margin - deviceFlick.height
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) {
      selectedIndex = 0
      return
    }
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = 0
      return
    }
    var count = sectionCount(focusSection)
    if (count === 0) {
      // Section emptied out — bounce to the previous visible one.
      var sIdx = sections.indexOf(focusSection)
      focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
      selectedIndex = Math.max(0, sectionCount(focusSection) - 1)
      return
    }
    if (selectedIndex > count - 1) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  visible: adapter !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Connections {
    target: root.adapter || null
    function onEnabledChanged() {
      if (root.opened && root.adapter && root.adapter.enabled && !root.adapter.discovering)
        root.adapter.discovering = true
    }
  }

  Timer {
    id: pendingTimeout
    interval: 20000
    repeat: false
    onTriggered: root.pendingActions = ({})
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        heroStatus.opacity = 1.0
      }
    }
  }

  function toggleBluetooth() {
    if (!adapter) return
    adapter.enabled = !adapter.enabled
    if (adapter.enabled) Qt.callLater(function() {
      if (root.adapter) root.adapter.discovering = true
    })
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleBluetooth()
      else if (b === Qt.MiddleButton) root.bar.run("omarchy-launch-bluetooth")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onDeleteRequested: if (root.cursorActive) root.deleteSelected()

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        // ---------- Hero: Bluetooth icon · status ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            opacity: root.adapter && root.adapter.enabled ? 1.0 : 0.5

            MouseArea {
              id: heroIconMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.adapter ? Qt.PointingHandCursor : Qt.ArrowCursor
              enabled: !!root.adapter
              onClicked: root.toggleBluetooth()
            }

            PanelToolTip {
              visible: heroIconMouse.containsMouse
              text: root.adapter && root.adapter.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on"
              fontFamily: root.bar.fontFamily
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Bluetooth"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              text: root.heroStatusText.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        // Scrollable device list — capped so a noisy neighborhood doesn't
        // grow the popup past the screen.
        Flickable {
          id: deviceFlick
          width: parent.width
          height: Math.min(deviceList.implicitHeight, Style.space(400))
          contentWidth: width
          contentHeight: deviceList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: deviceList
            width: parent.width
            spacing: Style.space(10)

            // Connected devices.
            PanelSectionHeader {
              visible: root.connectedDevices.length > 0
              text: "CONNECTED"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.connectedDevices
              DeviceRow {
                required property var modelData
                required property int index
                width: deviceList.width
                dev: modelData
                rowIndex: index
                sectionName: "connected"
                isDiscovered: false
              }
            }

            // Remembered devices.
            PanelSectionHeader {
              visible: root.knownDevices.length > 0
              text: "PAIRED"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.knownDevices
              DeviceRow {
                required property var modelData
                required property int index
                width: deviceList.width
                dev: modelData
                rowIndex: index
                sectionName: "known"
                isDiscovered: false
              }
            }

            // Discovered (unpaired) devices, only shown while scanning.
            PanelSectionHeader {
              visible: root.adapter && root.adapter.discovering && root.discoveredDevices.length > 0
              text: "AVAILABLE"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.adapter && root.adapter.discovering ? root.discoveredDevices : []
              DeviceRow {
                required property var modelData
                required property int index
                width: deviceList.width
                dev: modelData
                rowIndex: index
                sectionName: "discovered"
                isDiscovered: true
              }
            }

            Text {
              visible: root.connectedDevices.length === 0
                       && root.knownDevices.length === 0
                       && (!root.adapter || !root.adapter.discovering || root.discoveredDevices.length === 0)
              text: !root.adapter ? "No Bluetooth adapter"
                  : !root.adapter.enabled ? "Turn Bluetooth on to scan"
                  : root.adapter.discovering ? "Scanning for devices…"
                  : "No paired devices. Reopen this panel to scan again."
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              width: deviceList.width
            }
          }
        }
      }
    }
  }

  // Two-line device row showing name + live status. Pending state is owned
  // by the panel so it survives rows moving between sections.
  component DeviceRow: CursorSurface {
    id: row
    required property var dev
    required property int rowIndex
    required property string sectionName
    required property bool isDiscovered

    readonly property bool isConnected: dev && dev.connected
    readonly property int devState: dev && dev.state !== undefined ? dev.state : -1
    readonly property string action: root.pendingAction(dev ? dev.address : "")
    readonly property string actionTooltip: {
      if (!dev) return ""
      if (isConnected) return "Disconnect"
      if (isDiscovered) return "Pair"
      return "Connect"
    }

    readonly property bool rowSelected: root.cursorActive && root.focusSection === sectionName && root.selectedIndex === rowIndex
    readonly property bool forgetAvailable: sectionName === "known" && !isConnected && !isDiscovered
    readonly property bool showForgetButton: forgetAvailable && (rowMouse.containsMouse || rowSelected)

    hasCursor: rowSelected && !root.actionFocused
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(row)
    current: isConnected
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

    readonly property string statusText: {
      if (!dev) return ""
      if (action === "forgetting") return "Forgetting…"
      if (action === "disconnecting" || devState === 2) return "Disconnecting…"
      if (isConnected) {
        if (dev.batteryAvailable) return Math.round(dev.battery * 100) + "%"
        return sectionName === "connected" ? "" : "Connected"
      }
      if (action === "connecting" || devState === 3 || dev.pairing === true) return "Connecting…"
      if (isDiscovered) return ""
      return ""
    }

    readonly property color statusColor: {
      if (isConnected) return root.bar.foreground
      if (action !== "" || devState === 3 || dev.pairing === true) return root.bar.foreground
      return Qt.darker(root.bar.foreground, 1.5)
    }

    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: row.dev ? Qt.PointingHandCursor : Qt.ArrowCursor

      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = row.sectionName
        root.selectedIndex = row.rowIndex
        root.actionFocused = false
      }

      onClicked: function(mouse) {
        if (!row.dev) return
        if (mouse.button === Qt.RightButton) {
          if (row.isConnected) root.disconnectDevice(row.dev)
          else if (!row.isDiscovered) root.forgetDevice(row.dev)
          return
        }
        if (row.isConnected) root.disconnectDevice(row.dev)
        else root.connectDevice(row.dev)
      }
    }

    PanelToolTip {
      visible: row.actionTooltip !== "" && rowMouse.containsMouse && !root.actionFocused
      text: row.actionTooltip
      fontFamily: root.bar.fontFamily
    }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(deviceIcon.implicitHeight, info.implicitHeight, forgetBtn.implicitHeight)

      Text {
        id: deviceIcon
        text: row.isConnected ? "󰂱" : "󰂯"
        color: row.statusColor
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.heading
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        id: info
        spacing: Style.space(1)
        anchors.left: deviceIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: forgetBtn.visible ? forgetBtn.left : parent.right
        anchors.rightMargin: forgetBtn.visible ? Style.space(8) : 0
        anchors.verticalCenter: parent.verticalCenter

        Text {
          text: root.deviceLabel(row.dev) || "Device"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          visible: row.statusText !== ""
          text: row.statusText
          color: row.statusColor
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }

      PanelActionButton {
        id: forgetBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: row.showForgetButton
        iconText: "󰅙"
        tooltipText: "Forget"
        foreground: root.bar.foreground
        hoverColor: root.bar.foreground
        fontFamily: root.bar.fontFamily
        hasCursor: row.rowSelected && root.actionFocused
        onHovered: function(isHovered) {
          if (!isHovered) {
            if (rowMouse.containsMouse) root.actionFocused = false
            return
          }
          root.cursorActive = true
          root.focusSection = row.sectionName
          root.selectedIndex = row.rowIndex
          root.actionFocused = true
        }
        onClicked: {
          if (!row.dev) return
          root.forgetDevice(row.dev)
        }
      }
    }
  }
}
