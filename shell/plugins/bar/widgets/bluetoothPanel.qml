import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.Ui
import qs.Commons

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "bluetoothPanel"
  property var settings: ({})

  property bool popupOpen: false

  // Address -> true while we are waiting for a click-initiated pair to land
  // so we can chain trust + connect at root scope. Doing this in the row's
  // Connections is racy: the discovered Repeater destroys the delegate the
  // moment `paired` flips, before the row's handler reliably fires.
  property var pendingPairAddresses: ({})

  function closePopout() { popupOpen = false }

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
    for (var i = 0; i < devices.length; i++)
      if (devices[i] && devices[i].connected && hasHumanName(devices[i])) list.push(devices[i])
    return list
  }

  readonly property var knownDevices: {
    var list = []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (d && hasHumanName(d) && (d.paired || d.connected || d.bonded || d.trusted)) list.push(d)
    }
    list.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      return deviceLabel(a).localeCompare(deviceLabel(b))
    })
    return list
  }

  readonly property var discoveredDevices: {
    var list = []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (!d || !hasHumanName(d)) continue
      if (d.paired || d.connected || d.bonded || d.trusted) continue
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

  // Single cursor model shared by keyboard and mouse. Sections:
  //   "header"     — 2 action pills (scan, toggle); h/l moves between
  //                  them, Enter activates.
  //   "known"      — paired/known device rows; Enter toggles connect.
  //   "discovered" — unpaired devices visible while scanning; Enter pairs.
  // Visuals always come from CursorSurface (hasCursor / current),
  // never from containsMouse. Mouse hover updates root cursor state too,
  // guaranteeing one highlight on screen.
  property string focusSection: "header"
  property int selectedIndex: 1  // default = toggle pill
  readonly property int headerPillCount: 2

  // Stable identity for the focused known device. The known list is sorted
  // (connected-first, then alphabetical) so activating a device can shift
  // its index. We track the BlueZ address here so the cursor follows the
  // same device across reorders rather than the slot it used to occupy.
  property string focusedKnownAddress: ""

  readonly property color hoverFill: bar
    ? Qt.rgba(bar.foreground.r, bar.foreground.g, bar.foreground.b, 0.08)
    : "transparent"
  readonly property color selectedFill: bar
    ? Qt.rgba(bar.foreground.r, bar.foreground.g, bar.foreground.b, 0.18)
    : "transparent"

  function sectionCount(section) {
    if (section === "header") return headerPillCount
    if (section === "known") return knownDevices.length
    if (section === "discovered") return discoveredDevices.length
    return 0
  }

  function sectionVisible(section) {
    if (section === "header") return true
    if (section === "known") return knownDevices.length > 0
    if (section === "discovered") return adapter && adapter.discovering && discoveredDevices.length > 0
    return false
  }

  readonly property var visibleSections: {
    var list = ["header"]
    if (sectionVisible("known")) list.push("known")
    if (sectionVisible("discovered")) list.push("discovered")
    return list
  }

  // j/k navigates between sections row-by-row. The header is treated as a
  // SINGLE row (its pills sit on one horizontal line), so j/k from devices
  // jumps to/from the header as a unit, and h/l moves between the three
  // pills inside it. This matches wifi's DNS-pill behaviour.
  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) { focusSection = sections[0]; selectedIndex = 0; return }

    var idx = selectedIndex
    var inHeader = focusSection === "header"
    var max = inHeader ? 0 : sectionCount(focusSection) - 1

    if (delta > 0) {
      if (!inHeader && idx < max) { selectedIndex = idx + 1; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        // Entering the header from below shouldn't happen (header is first),
        // but other entries start at 0.
        selectedIndex = 0
      }
    } else {
      if (!inHeader && idx > 0) { selectedIndex = idx - 1; return }
      if (sIdx > 0) {
        focusSection = sections[sIdx - 1]
        // Entering the header always lands on the toggle pill — the most
        // common action and consistent with the on-open default. h/l from
        // there moves to scan.
        selectedIndex = focusSection === "header" ? 1 : sectionCount(focusSection) - 1
      }
    }
  }

  // h/l: only meaningful in the header. In device sections it's a no-op
  // — j/k is the canonical row navigator there.
  function moveCursorH(delta) {
    if (focusSection !== "header") return
    var next = selectedIndex + delta
    if (next < 0) next = 0
    if (next > headerPillCount - 1) next = headerPillCount - 1
    selectedIndex = next
  }

  function activateCursor() {
    if (focusSection === "header") {
      if (selectedIndex === 0) {
        if (adapter && adapter.enabled) adapter.discovering = !adapter.discovering
      } else if (selectedIndex === 1) {
        if (adapter) adapter.enabled = !adapter.enabled
      }
      return
    }
    if (focusSection === "known") {
      var dev = knownDevices[selectedIndex]
      if (!dev) return
      if (!dev.trusted) dev.trusted = true
      if (dev.connected) dev.disconnect()
      else dev.connect()
      return
    }
    if (focusSection === "discovered") {
      var d = discoveredDevices[selectedIndex]
      if (!d) return
      pendingPairAddresses[d.address] = true
      d.pair()
    }
  }

  // 'x' on a known row mirrors the row's X button: connected device
  // disconnects, everything else forgets the pairing. Mismatching this
  // (e.g. forgetting a connected device) is destructive — the X button
  // tooltip says "Disconnect" for connected rows, and the keybind has
  // to agree.
  function deleteSelected() {
    if (focusSection !== "known") return
    var dev = knownDevices[selectedIndex]
    if (!dev) return
    if (dev.connected) dev.disconnect()
    else if (dev.forget) dev.forget()
  }

  onPopupOpenChanged: {
    if (popupOpen) {
      if (adapter && adapter.enabled && !adapter.discovering) adapter.discovering = true
      if (knownDevices.length > 0) { focusSection = "known"; selectedIndex = 0 }
      else { focusSection = "header"; selectedIndex = 1 }
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }
  }

  // When `selectedIndex` changes inside the known section, remember which
  // address it points at. Updates from re-resolution (below) are idempotent
  // because we end up setting the same address.
  onSelectedIndexChanged: {
    if (focusSection !== "known") return
    if (selectedIndex < 0 || selectedIndex >= knownDevices.length) return
    var d = knownDevices[selectedIndex]
    focusedKnownAddress = d ? (d.address || "") : ""
  }

  onFocusSectionChanged: {
    if (focusSection !== "known") focusedKnownAddress = ""
  }

  onKnownDevicesChanged: {
    // Try to follow the device by address before clamping. If we can't find
    // the address (e.g. it was forgotten), fall through to clampCursor()
    // which will pull selectedIndex back into range.
    if (focusSection === "known" && focusedKnownAddress !== "") {
      for (var i = 0; i < knownDevices.length; i++) {
        if (knownDevices[i] && knownDevices[i].address === focusedKnownAddress) {
          if (selectedIndex !== i) selectedIndex = i
          clampCursor()
          return
        }
      }
    }
    clampCursor()
  }
  onDiscoveredDevicesChanged: clampCursor()
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
    if (!sections || !sections.length) return
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
      if (root.popupOpen && root.adapter && root.adapter.enabled && !root.adapter.discovering)
        root.adapter.discovering = true
    }
  }

  // Non-visual lifecycle watchers, one per device. Survives popup open/close
  // and the discovered-known transition that destroys row delegates.
  Repeater {
    model: root.devices
    Item {
      required property var modelData
      visible: false
      Connections {
        target: modelData || null
        function onPairedChanged() {
          var d = modelData
          if (!d || !d.paired) return
          if (!root.pendingPairAddresses[d.address]) return
          delete root.pendingPairAddresses[d.address]
          // BlueZ pair() does not auto-trust or auto-connect. Without
          // trusted, the daemon may drop the entry shortly after pairing,
          // which makes a freshly-paired device flash "Connected" and then
          // vanish from the model.
          d.trusted = true
          if (!d.connected) d.connect()
        }
      }
    }
  }

  // Lets a Hyprland keybind summon the panel without a click.
  IpcHandler {
    target: "bluetoothPanel"
    function toggle(): void {
      if (root.popupOpen) root.closePopout()
      else root.popupOpen = true
    }
    function show(): void { if (!root.popupOpen) root.popupOpen = true }
    function hide(): void { root.closePopout() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    onPressed: function(b) {
      if (b === Qt.RightButton && root.adapter) root.adapter.enabled = !root.adapter.enabled
      else if (b === Qt.MiddleButton) root.bar.run("omarchy-launch-bluetooth")
      else root.popupOpen = !root.popupOpen
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: 320
    contentHeight: column.implicitHeight + 28

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.closePopout()
      onDeleteRequested: root.deleteSelected()

      Column {
        id: column
        anchors.fill: parent
        spacing: 10

        // Header: title left, on/off toggle + actions right.
        Item {
          width: parent.width
          height: titleText.implicitHeight

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            PanelSectionHeader {
              id: titleText
              text: "Bluetooth"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "· " + (root.adapter && root.adapter.enabled ? "On" : "Off")
              color: Qt.darker(root.bar.foreground, 1.8)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            HeaderPill {
              pillIndex: 0
              property real scanRotation: 0
              iconText: "󰑐"
              iconRotation: root.adapter && root.adapter.discovering ? scanRotation : 0
              tooltipText: !root.adapter ? "" : !root.adapter.enabled ? "Bluetooth is off"
                : root.adapter.discovering ? "Stop scanning" : "Scan for devices"
              pillEnabled: root.adapter !== null && root.adapter.enabled
              onActivated: if (root.adapter) root.adapter.discovering = !root.adapter.discovering

              NumberAnimation on scanRotation {
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
                running: root.adapter && root.adapter.discovering
              }
            }

            HeaderPill {
              pillIndex: 1
              iconText: root.adapter && root.adapter.enabled ? "󰂲" : "󰂯"
              tooltipText: root.adapter && root.adapter.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on"
              onActivated: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
            }
          }
        }

        // Scrollable device list — capped so a noisy neighborhood doesn't
        // grow the popup past the screen.
        Flickable {
          id: deviceFlick
          width: parent.width
          height: Math.min(deviceList.implicitHeight, 400)
          contentWidth: width
          contentHeight: deviceList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: deviceList
            width: parent.width
            spacing: 10

            // Paired / known devices.
            Repeater {
              model: root.knownDevices
              DeviceRow {
                required property var modelData
                required property int index
                width: deviceList.width
                dev: modelData
                rowIndex: index
                isDiscovered: false
              }
            }

            // Discovered (unpaired) devices, only shown while scanning.
            PanelSectionHeader {
              visible: root.adapter && root.adapter.discovering && root.discoveredDevices.length > 0
              text: "Discovered"
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
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              width: deviceList.width
            }
          }
        }
      }
    }
  }

  // Header pill: a Button bound into the panel's "header" cursor
  // section. Button collapses what used to be a Button subclass +
  // overlay MouseArea into one component; we keep the pillIndex / activated
  // shim here so the three header pill instantiations stay readable.
  component HeaderPill: Button {
    id: pill
    required property int pillIndex
    property bool pillEnabled: true
    signal activated()

    tooltipBackground: root.bar.background
    tooltipForeground: root.bar.foreground
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: 6
    verticalPadding: 4
    iconSize: 14
    enabled: pillEnabled
    opacity: pillEnabled ? 1 : 0.4

    hasCursor: root.focusSection === "header" && root.selectedIndex === pillIndex

    onClicked: pill.activated()
    onHovered: function(isHovered) {
      if (!isHovered) return
      root.focusSection = "header"
      root.selectedIndex = pill.pillIndex
    }
  }

  // Two-line device row showing name + live status (Connected, Connecting,
  // Pairing, Failed). Tracks pending click attempts with a Timer so a
  // connect that drops back to Disconnected within 10s surfaces as "Failed".
  // Now a cursor target: hasCursor binds to root state, mouse hover updates
  // root state. The X button on the right is a PanelActionButton.
  component DeviceRow: CursorSurface {
    id: row
    required property var dev
    required property int rowIndex
    required property bool isDiscovered

    readonly property bool isConnected: dev && dev.connected
    readonly property int devState: dev && dev.state !== undefined ? dev.state : -1
    readonly property string sectionName: isDiscovered ? "discovered" : "known"

    hasCursor: root.focusSection === sectionName && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(row)
    current: isConnected
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

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
      if (pendingAction === 1 || devState === 3) return "Connecting…"
      if (pendingAction === 2 || devState === 2) return "Disconnecting…"
      if (pendingAction === 3 || (dev.pairing === true)) return "Pairing…"
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

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: row.dev ? Qt.PointingHandCursor : Qt.ArrowCursor

      onContainsMouseChanged: if (containsMouse) {
        root.focusSection = row.sectionName
        root.selectedIndex = row.rowIndex
      }

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
          root.pendingPairAddresses[row.dev.address] = true
          row.dev.pair()
          return
        }
        if (!row.dev.trusted) row.dev.trusted = true
        if (row.isConnected) return  // use the X button to disconnect
        row.pendingAction = 1
        row.failureReason = ""
        failureTimer.restart()
        row.dev.connect()
      }
    }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      implicitHeight: Math.max(deviceIcon.implicitHeight, info.implicitHeight, disconnectBtn.implicitHeight)

      Text {
        id: deviceIcon
        text: row.isConnected ? "󰂱" : "󰂯"
        color: row.statusColor
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.heading
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      // Explicit close button on any known device. Action depends on state:
      // connected -> disconnect, otherwise -> forget the pairing entirely.
      PanelActionButton {
        id: disconnectBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: !row.isDiscovered
        iconText: "󰅙"
        tooltipText: row.isConnected ? "Disconnect" : "Forget"
        foreground: root.bar.foreground
        hoverColor: root.bar.urgent
        panelBackground: root.bar.background
        fontFamily: root.bar.fontFamily
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

      Column {
        id: info
        spacing: 1
        anchors.left: deviceIcon.right
        anchors.leftMargin: 10
        anchors.right: disconnectBtn.visible ? disconnectBtn.left : parent.right
        anchors.rightMargin: disconnectBtn.visible ? 8 : 0
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
    }
  }
}
