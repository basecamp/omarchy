import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.tailscale"
  ipcTarget: "omarchy.tailscale"
  manageIpc: false

  property string focusSection: "header"
  property int headerIndex: 0
  property int accountIndex: 0
  property int peerIndex: 0
  property int exitNodeIndex: 0
  property int mullvadRegionIndex: 0
  property bool cursorActive: false
  property bool copyMenuOpen: false
  property bool mullvadPickerOpen: false
  property string mullvadQuery: ""
  property int phraseIndex: 0
  readonly property var activePhrases: [
    "Encrypting connections",
    "Sending secrets",
    "Guarding wires",
    "Braiding packets",
    "Polishing tunnels",
    "Hiding routes",
    "Sealing ports",
    "Sorting tailnets",
    "Shuffling keys",
    "Watching machines"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showConnections: tailscale.accounts.length > 1 || tailscale.accountsAccessDenied
  readonly property bool showPeers: tailscale.active && tailscale.peers.length > 0
  readonly property var recentMullvadRegions: settings.recentMullvadRegions instanceof Array ? settings.recentMullvadRegions : (settings.recentMullvadCountries instanceof Array ? settings.recentMullvadCountries : [])
  readonly property var recentMullvadExitNodes: recentMullvadNodes()
  readonly property var exitNodes: displayExitNodes()
  readonly property bool showExitNodes: tailscale.active && (exitNodes.length > 0 || tailscale.mullvadRegions.length > 0)
  readonly property var filteredMullvadRegions: filteredMullvadRegionNodes()
  readonly property color iconColor: tailscale.active ? foreground : dim
  readonly property color barIconColor: tailscale.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  function selectedPeer() {
    if (tailscale.peers.length === 0) return null
    return tailscale.peers[Math.max(0, Math.min(peerIndex, tailscale.peers.length - 1))]
  }

  function selectedExitNode() {
    if (exitNodes.length === 0) return null
    return exitNodes[Math.max(0, Math.min(exitNodeIndex, exitNodes.length - 1))]
  }

  function selectedMullvadRegion() {
    if (filteredMullvadRegions.length === 0) return null
    return filteredMullvadRegions[Math.max(0, Math.min(mullvadRegionIndex, filteredMullvadRegions.length - 1))]
  }

  function displayExitNodes() {
    var nodes = []
    for (var i = 0; i < tailscale.tailnetExitNodes.length; i++) nodes.push(tailscale.tailnetExitNodes[i])
    for (var j = 0; j < recentMullvadExitNodes.length; j++) nodes.push(recentMullvadExitNodes[j])
    if (tailscale.mullvadRegions.length > 0) nodes.push({ id: "mullvad:add", AddMullvad: true, DisplayName: "Choose Mullvad region" })
    return nodes
  }

  function recentMullvadNodes() {
    var nodes = []
    var seen = {}
    for (var a = 0; a < tailscale.mullvadRegions.length && nodes.length < 5; a++) {
      var active = tailscale.mullvadRegions[a]
      var activeKey = mullvadRegionKey(active)
      if (active.ExitNode === true && activeKey !== "" && !seen[activeKey]) {
        nodes.push(active)
        seen[activeKey] = true
      }
    }
    for (var i = 0; i < recentMullvadRegions.length && nodes.length < 5; i++) {
      var region = String(recentMullvadRegions[i] || "")
      if (region === "" || seen[region]) continue
      var node = mullvadRegionNode(region)
      if (node) {
        nodes.push(node)
        seen[region] = true
      }
    }
    return nodes
  }

  function mullvadRegionKey(node) {
    if (!node) return ""
    var country = String(node.Country || "")
    var city = String(node.City || "")
    if (country === "" || city === "") return ""
    return country + "\n" + city
  }

  function mullvadRegionNode(region) {
    for (var i = 0; i < tailscale.mullvadRegions.length; i++) {
      var node = tailscale.mullvadRegions[i]
      if (mullvadRegionKey(node) === String(region || "")) return node
      if (String(node.Country || "") === String(region || "")) return node
    }
    return null
  }

  function filteredMullvadRegionNodes() {
    var query = String(mullvadQuery || "").trim().toLowerCase()
    var result = []
    for (var i = 0; i < tailscale.mullvadRegions.length; i++) {
      var node = tailscale.mullvadRegions[i]
      var label = (String(node.City || "") + " " + String(node.Country || "")).toLowerCase()
      if (query === "" || label.indexOf(query) !== -1) result.push(node)
    }
    return result
  }

  function mullvadRegionTitle(peer) {
    if (!peer) return "Unknown"
    var city = String(peer.City || "").trim()
    var country = String(peer.Country || "").trim()
    if (city === "" || city === "Any") return country || String(peer.DisplayName || "Unknown")
    return city
  }

  function mullvadRegionSubtitle(peer) {
    if (!peer) return ""
    return String(peer.Country || "").trim()
  }

  function persistRecentMullvad(region) {
    var name = String(region || "")
    if (name === "") return
    var next = [name]
    for (var i = 0; i < recentMullvadRegions.length && next.length < 5; i++) {
      var existing = String(recentMullvadRegions[i] || "")
      if (existing !== "" && existing !== name && next.indexOf(existing) === -1) next.push(existing)
    }
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.recentMullvadRegions = next
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function chooseExitNode(peer) {
    if (!peer) return
    if (peer.AddMullvad === true) {
      mullvadPickerOpen = !mullvadPickerOpen
      mullvadRegionIndex = 0
      if (mullvadPickerOpen) Qt.callLater(function() { if (mullvadSearch) mullvadSearch.forceActiveFocus() })
      return
    }
    if (peer.Mullvad === true) persistRecentMullvad(mullvadRegionKey(peer))
    tailscale.setExitNode(peer)
    mullvadPickerOpen = false
  }

  function selectedAccount() {
    if (tailscale.accounts.length === 0) return null
    return tailscale.accounts[Math.max(0, Math.min(accountIndex, tailscale.accounts.length - 1))]
  }

  function ensureCursor() {
    if (headerIndex < 0) headerIndex = 0
    if (headerIndex > 0) headerIndex = 0
    if (accountIndex >= tailscale.accounts.length) accountIndex = Math.max(0, tailscale.accounts.length - 1)
    if (peerIndex >= tailscale.peers.length) peerIndex = Math.max(0, tailscale.peers.length - 1)
    if (exitNodeIndex >= exitNodes.length) exitNodeIndex = Math.max(0, exitNodes.length - 1)
    if (mullvadRegionIndex >= filteredMullvadRegions.length) mullvadRegionIndex = Math.max(0, filteredMullvadRegions.length - 1)
    if (focusSection === "auth" && !tailscale.accountsAccessDenied) focusSection = tailscale.accounts.length > 1 ? "accounts" : (showExitNodes ? "exitNodes" : (showPeers ? "peers" : "header"))
    if (focusSection === "accounts" && tailscale.accounts.length <= 1) focusSection = tailscale.accountsAccessDenied ? "auth" : (showExitNodes ? "exitNodes" : (showPeers ? "peers" : "header"))
    if (focusSection === "peers" && !showPeers) focusSection = showExitNodes ? "exitNodes" : (tailscale.accountsAccessDenied ? "auth" : (tailscale.accounts.length > 1 ? "accounts" : "header"))
    if (focusSection === "exitNodes" && !showExitNodes) focusSection = showPeers ? "peers" : (tailscale.accountsAccessDenied ? "auth" : (tailscale.accounts.length > 1 ? "accounts" : "header"))
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy !== 0) {
      if (focusSection === "header") {
        if (dy > 0) {
          if (tailscale.accountsAccessDenied) focusSection = "auth"
          else if (tailscale.accounts.length > 1) focusSection = "accounts"
          else if (showExitNodes) focusSection = "exitNodes"
          else if (showPeers) focusSection = "peers"
        }
      } else if (focusSection === "auth") {
        if (dy < 0) focusSection = "header"
        else if (tailscale.accounts.length > 1) focusSection = "accounts"
        else if (showExitNodes) focusSection = "exitNodes"
        else if (showPeers) focusSection = "peers"
      } else if (focusSection === "accounts") {
        if (dy < 0) {
          if (accountIndex <= 0) focusSection = tailscale.accountsAccessDenied ? "auth" : "header"
          else accountIndex--
        } else {
          if (accountIndex < tailscale.accounts.length - 1) accountIndex++
          else if (showExitNodes) focusSection = "exitNodes"
          else if (showPeers) focusSection = "peers"
        }
      } else if (focusSection === "peers") {
        if (dy < 0) {
          if (peerIndex <= 0) focusSection = showExitNodes ? "exitNodes" : (tailscale.accounts.length > 1 ? "accounts" : (tailscale.accountsAccessDenied ? "auth" : "header"))
          else peerIndex--
        } else if (peerIndex < tailscale.peers.length - 1) {
          peerIndex++
        }
      } else if (focusSection === "exitNodes") {
        if (dy < 0) {
          if (exitNodeIndex <= 0) focusSection = tailscale.accounts.length > 1 ? "accounts" : (tailscale.accountsAccessDenied ? "auth" : "header")
          else exitNodeIndex--
        } else if (exitNodeIndex < exitNodes.length - 1) {
          exitNodeIndex++
        } else if (showPeers) {
          focusSection = "peers"
        }
      }
    }
    ensureCursor()
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") {
      tailscale.toggleTailscale()
    } else if (focusSection === "auth") {
      tailscale.authorizeTailscaleOperator()
    } else if (focusSection === "accounts") {
      var account = selectedAccount()
      if (account) tailscale.switchAccount(account.id)
    } else if (focusSection === "peers") {
      openSelectedPeerCopyMenu()
    } else if (focusSection === "exitNodes") {
      chooseExitNode(selectedExitNode())
    }
  }

  function moveMullvadRegionCursor(delta) {
    if (filteredMullvadRegions.length === 0) return
    cursorActive = true
    mullvadRegionIndex = Math.max(0, Math.min(filteredMullvadRegions.length - 1, mullvadRegionIndex + delta))
    scrollMullvadRegionCursorIntoView()
  }

  function activateMullvadRegionCursor() {
    var region = selectedMullvadRegion()
    if (region) chooseExitNode(region)
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "peers" && peerColumn && peerIndex >= 0 && peerIndex < peerColumn.children.length) scrollItemIntoView(peerColumn.children[peerIndex])
    else if (focusSection === "exitNodes" && exitNodeColumn && exitNodeIndex >= 0 && exitNodeIndex < exitNodeColumn.children.length) scrollItemIntoView(exitNodeColumn.children[exitNodeIndex])
  }

  function scrollMullvadRegionCursorIntoView() {
    if (mullvadRegionColumn && mullvadRegionIndex >= 0 && mullvadRegionIndex < mullvadRegionColumn.children.length) scrollItemIntoView(mullvadRegionColumn.children[mullvadRegionIndex])
  }

  function setPeerCursor(index) {
    cursorActive = true
    focusSection = "peers"
    peerIndex = index
    scrollCursorIntoView()
  }

  function openSelectedPeerCopyMenu() {
    if (!peerColumn || peerIndex < 0 || peerIndex >= peerColumn.children.length) return
    var item = peerColumn.children[peerIndex]
    if (item && item.openCopyMenu) item.openCopyMenu()
  }

  function setExitNodeCursor(index) {
    cursorActive = true
    focusSection = "exitNodes"
    exitNodeIndex = index
    scrollCursorIntoView()
  }

  function setAccountCursor(index) {
    cursorActive = true
    focusSection = "accounts"
    accountIndex = index
  }

  function setAuthCursor() {
    cursorActive = true
    focusSection = "auth"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    tailscale.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onPeerIndexChanged: scrollCursorIntoView()
  onExitNodeIndexChanged: scrollCursorIntoView()
  onMullvadRegionIndexChanged: if (mullvadPickerOpen) scrollMullvadRegionCursorIntoView()
  onShowConnectionsChanged: ensureCursor()
  onShowPeersChanged: ensureCursor()
  onShowExitNodesChanged: ensureCursor()
  onFilteredMullvadRegionsChanged: ensureCursor()

  Service {
    id: tailscale
    settings: root.settings
  }

  Connections {
    target: tailscale
    function onPeersChanged() { root.ensureCursor() }
    function onAccountsChanged() { root.ensureCursor() }
    function onAccountsAccessDeniedChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { tailscale.refresh(); return "ok" }
    function up(): string { tailscale.loginOrUp(); return "ok" }
    function down(): string { tailscale.down(); return "ok" }
    function status(): string { return tailscale.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        TailscaleIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          badgeColor: root.urgent
          crossed: !tailscale.active && !tailscale.needsLogin
          warning: tailscale.needsLogin
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) tailscale.toggleTailscale()
      else if (buttonCode === Qt.MiddleButton) tailscale.refresh()
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.copyMenuOpen
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") tailscale.toggleTailscale()
        else if (t === "c" || t === "C") tailscale.copyPeerIp(root.selectedPeer())
        else if (t === "n" || t === "N") tailscale.copyPeerName(root.selectedPeer())
        else if (t === "d" || t === "D") tailscale.copyPeerDnsName(root.selectedPeer())
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight

            PanelHero {
              id: hero
              width: parent.width
              title: tailscale.installed ? (tailscale.selfName || "Tailscale") : "Tailscale"
              meta: tailscale.active ? root.heroPhraseText : "Tailscale is disconnected"
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: tailscale.active ? 1.0 : 0.5
              iconComponent: Component {
                Item {
                  implicitWidth: icon.implicitWidth
                  implicitHeight: icon.implicitHeight

                  TailscaleIcon {
                    id: icon
                    iconSize: Style.font.display
                    color: root.iconColor
                    badgeColor: root.urgent
                    crossed: !tailscale.active && !tailscale.needsLogin
                    warning: tailscale.needsLogin
                    anchors.centerIn: parent
                  }

                  MouseArea {
                    id: heroIconMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: tailscale.installed && !tailscale.busy
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onContainsMouseChanged: if (containsMouse) {
                      root.focusSection = "header"
                      root.headerIndex = 0
                    }
                    onClicked: tailscale.toggleTailscale()
                  }

                  PanelToolTip {
                    visible: heroIconMouse.containsMouse
                    text: tailscale.active ? "Turn Tailscale off" : (tailscale.needsLogin ? "Authorize this device" : "Turn Tailscale on")
                    fontFamily: root.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: tailscale.actionStatus !== "" || tailscale.lastError !== ""
            width: parent.width
            text: tailscale.actionStatus !== "" ? tailscale.actionStatus : tailscale.lastError
            color: tailscale.lastError !== "" && tailscale.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          CursorSurface {
            visible: !tailscale.installed
            width: parent.width
            implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: missingText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "Tailscale CLI is not installed or not on PATH."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator {
            visible: root.showConnections
            foreground: root.foreground
          }

          Column {
            visible: root.showConnections
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "CONNECTIONS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            AuthRow {
              visible: tailscale.accountsAccessDenied
              width: parent.width
            }

            Repeater {
              model: tailscale.accounts
              AccountRow {
                required property var modelData
                required property int index
                width: parent.width
                account: modelData
                rowIndex: index
              }
            }
          }

          PanelSeparator {
            visible: root.showExitNodes
            foreground: root.foreground
          }

          Column {
            visible: root.showExitNodes
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "EXIT NODES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: exitNodeColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.exitNodes
                ExitNodeRow {
                  required property var modelData
                  required property int index
                  width: exitNodeColumn.width
                  peer: modelData
                  rowIndex: index
                }
              }

              Column {
                visible: root.mullvadPickerOpen
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: mullvadSearch
                  width: parent.width
                  foreground: root.foreground
                  placeholderText: "Search regions"
                  text: root.mullvadQuery
                  onTextChanged: {
                    root.mullvadQuery = text
                    root.mullvadRegionIndex = 0
                  }
                  onAccepted: {
                    root.activateMullvadRegionCursor()
                  }
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Down || event.text === "j") {
                      root.moveMullvadRegionCursor(1)
                      event.accepted = true
                      return
                    }
                    if (event.key === Qt.Key_Up || event.text === "k") {
                      root.moveMullvadRegionCursor(-1)
                      event.accepted = true
                      return
                    }
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      root.activateMullvadRegionCursor()
                      event.accepted = true
                      return
                    }
                    if (event.key === Qt.Key_Escape) {
                      root.mullvadPickerOpen = false
                      keyCatcher.forceActiveFocus()
                      event.accepted = true
                    }
                  }
                }

                Text {
                  visible: root.filteredMullvadRegions.length === 0
                  width: parent.width
                  text: "No Mullvad regions found."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  horizontalAlignment: Text.AlignHCenter
                }

                Column {
                  id: mullvadRegionColumn
                  width: parent.width
                  spacing: Style.space(6)

                  Repeater {
                    model: root.filteredMullvadRegions
                    MullvadRegionRow {
                      required property var modelData
                      required property int index
                      width: parent.width
                      peer: modelData
                      rowIndex: index
                    }
                  }
                }
              }
            }
          }

          PanelSeparator {
            visible: tailscale.installed && tailscale.active
            foreground: root.foreground
          }

          Column {
            visible: tailscale.installed && tailscale.active
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "MACHINES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: tailscale.installed && tailscale.active && tailscale.peers.length === 0
              width: parent.width
              text: "No machines found on this tailnet."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: peerColumn
              visible: root.showPeers
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: tailscale.peers
                PeerRow {
                  required property var modelData
                  required property int index
                  width: peerColumn.width
                  peer: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && tailscale.active
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  component AuthRow: CursorSurface {
    id: authRow

    hasCursor: root.cursorActive && root.focusSection === "auth"
    foreground: root.foreground

    implicitHeight: row.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: tailscale.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !tailscale.busy
      onEntered: root.setAuthCursor()
      onClicked: tailscale.authorizeTailscaleOperator()
    }

    RowLayout {
      id: row
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: "󰒃"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: "Authorize Tailscale operator"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: "Allow this user to operate this Tailscale profile"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

    }
  }

  component AccountRow: CursorSurface {
    id: accountRow
    property var account: null
    property int rowIndex: 0
    readonly property bool selectedAccount: account && account.selected === true
    readonly property bool switchingAccount: account && tailscale.switchingAccountId === String(account.id || "")
    readonly property string accountText: account ? tailscale.accountLabel(account) : "Account"

    hasCursor: root.cursorActive && root.focusSection === "accounts" && root.accountIndex === rowIndex
    current: selectedAccount
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

    implicitHeight: accountInner.implicitHeight + Style.spacing.xl

    Row {
      id: accountInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        id: accountGlyph
        text: ""
        color: accountRow.selectedAccount || accountRow.switchingAccount ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
        opacity: accountRow.switchingAccount ? 0.45 : 1.0

        SequentialAnimation on opacity {
          running: accountRow.switchingAccount
          NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 0.45; duration: 420; easing.type: Easing.InOutQuad }
          loops: Animation.Infinite
        }
      }

      Text {
        text: accountRow.accountText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: accountRow.selectedAccount
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setAccountCursor(accountRow.rowIndex)
      onClicked: if (accountRow.account) tailscale.switchAccount(accountRow.account.id)
    }
  }

  component PeerRow: CursorSurface {
    id: peerRow
    property var peer: null
    property int rowIndex: 0
    readonly property string peerName: peer ? String(peer.DisplayName || peer.HostName || "Unknown") : "Unknown"
    readonly property string peerIp: peer && peer.TailscaleIPs && peer.TailscaleIPs.length > 0 ? String(peer.TailscaleIPs[0]) : ""
    readonly property string peerIpv6: {
      if (!peer || !peer.TailscaleIPv6 || peer.TailscaleIPv6.length === 0) return ""
      return String(peer.TailscaleIPv6[0] || "")
    }
    readonly property string peerDns: peer ? String(peer.DNSName || "") : ""
    readonly property var copyOptions: {
      var options = []
      if (peerName !== "") options.push({ kind: "name", label: peerName })
      if (peerDns !== "") options.push({ kind: "dns", label: peerDns })
      if (peerIpv6 !== "") options.push({ kind: "ipv6", label: peerIpv6 })
      if (peerIp !== "") options.push({ kind: "ip", label: peerIp })
      return options
    }
    property int copyIndex: 0

    hasCursor: root.cursorActive && root.focusSection === "peers" && root.peerIndex === rowIndex
    foreground: root.foreground

    implicitHeight: Math.max(peerContent.implicitHeight, copyButton.implicitHeight) + Style.spacing.rowPaddingX

    function clampCopyIndex() {
      copyIndex = Math.max(0, Math.min(copyIndex, copyOptions.length - 1))
    }

    function openCopyMenu() {
      if (copyOptions.length === 0) return
      clampCopyIndex()
      copyPopup.open()
    }

    function moveCopyCursor(delta) {
      if (copyOptions.length === 0) return
      copyIndex = Math.max(0, Math.min(copyOptions.length - 1, copyIndex + delta))
    }

    function copyOption(kind) {
      if (kind === "name") tailscale.copyPeerName(peer)
      else if (kind === "dns") tailscale.copyPeerDnsName(peer)
      else if (kind === "ipv6") tailscale.copyToClipboard(peerIpv6, peerName + " IPv6")
      else if (kind === "ip") tailscale.copyPeerIp(peer)
      copyPopup.close()
    }

    function copyCurrentOption() {
      clampCopyIndex()
      if (copyOptions.length === 0) return
      copyOption(copyOptions[copyIndex].kind)
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      cursorShape: Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse) root.setPeerCursor(peerRow.rowIndex)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: tailscale.osIcon(peer ? peer.OS : "")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: peerContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: peerRow.peerName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: {
            var parts = []
            if (peerRow.peerIp !== "") parts.push(peerRow.peerIp)
            if (peerRow.peerDns !== "") parts.push(peerRow.peerDns)
            return parts.join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        id: copyButton
        iconText: "󰆏"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: peerRow.peerIp !== "" || peerRow.peerName !== "" || peerRow.peerDns !== "" || peerRow.peerIpv6 !== ""
        Layout.alignment: Qt.AlignVCenter
        onClicked: peerRow.openCopyMenu()
      }

      Popup {
        id: copyPopup
        x: copyButton.x + copyButton.width - width
        y: copyButton.y + copyButton.height + Style.space(4)
        width: Style.space(280)
        padding: 0
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        function handleKey(event) {
          if (event.key === Qt.Key_Escape) {
            close()
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Down || event.text === "j") {
            peerRow.moveCopyCursor(1)
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Up || event.text === "k") {
            peerRow.moveCopyCursor(-1)
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            peerRow.copyCurrentOption()
            event.accepted = true
          }
        }
        onOpenedChanged: {
          root.copyMenuOpen = opened
          if (opened) {
            peerRow.clampCopyIndex()
            Qt.callLater(function() { copyPopupContent.forceActiveFocus() })
          } else if (root.opened) {
            Qt.callLater(function() { keyCatcher.forceActiveFocus() })
          }
        }
        background: BorderSurface {
          color: Color.background
          borderSpec: Border.flat(root.dim, 1)
          radius: Style.cornerRadius
        }

        contentItem: Column {
          id: copyPopupContent
          width: parent.width
          focus: true
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) { copyPopup.handleKey(event) }

          Repeater {
            model: peerRow.copyOptions
            CopyChoice {
              required property var modelData
              required property int index
              width: parent.width
              label: String(modelData.label || "")
              selected: peerRow.copyIndex === index
              onHovered: peerRow.copyIndex = index
              onChosen: peerRow.copyOption(String(modelData.kind || ""))
            }
          }
        }
      }
    }
  }

  component CopyChoice: CursorSurface {
    id: copyChoice
    signal chosen()
    signal hovered()
    property string label: ""
    property bool selected: false

    visible: enabled
    foreground: root.foreground
    hasCursor: selected
    implicitHeight: Style.space(48)
    radius: 0

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: copyChoice.hovered()
      onClicked: copyChoice.chosen()
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(10)

      Text {
        Layout.fillWidth: true
        text: copyChoice.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        text: "󰆏"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component ExitNodeRow: CursorSurface {
    id: exitNodeRow
    property var peer: null
    property int rowIndex: 0
    readonly property bool addMullvad: peer && peer.AddMullvad === true
    readonly property bool activeExitNode: peer && peer.ExitNode === true
    readonly property bool settingExitNode: peer && tailscale.settingExitNodeId === String(peer.id || "")
    readonly property string peerName: peer ? String(peer.DisplayName || peer.HostName || "Unknown") : "Unknown"
    readonly property string actionTooltip: addMullvad ? "" : (activeExitNode ? "Disconnect" : "Connect")

    hasCursor: root.cursorActive && root.focusSection === "exitNodes" && root.exitNodeIndex === rowIndex
    current: activeExitNode || settingExitNode || (addMullvad && root.mullvadPickerOpen)
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

    implicitHeight: exitNodeInner.implicitHeight + Style.spacing.xl

    Row {
      id: exitNodeInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        id: exitNodeGlyph
        text: exitNodeRow.addMullvad ? "+" : (peer && peer.Mullvad === true ? "󰖂" : "󱇢")
        color: exitNodeRow.activeExitNode || exitNodeRow.settingExitNode || exitNodeRow.addMullvad ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter

        NumberAnimation on rotation {
          running: exitNodeRow.settingExitNode
          from: 0
          to: 360
          duration: 900
          loops: Animation.Infinite
        }

        onRotationChanged: if (!exitNodeRow.settingExitNode && rotation !== 0) rotation = 0
      }

      Text {
        text: exitNodeRow.peerName
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: exitNodeRow.activeExitNode
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: exitNodeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setExitNodeCursor(exitNodeRow.rowIndex)
      onClicked: root.chooseExitNode(exitNodeRow.peer)
    }

    PanelToolTip {
      visible: exitNodeRow.actionTooltip !== "" && exitNodeMouse.containsMouse
      text: exitNodeRow.actionTooltip
      fontFamily: root.fontFamily
    }
  }

  component MullvadRegionRow: CursorSurface {
    id: regionRow

    property var peer: null
    property int rowIndex: 0
    readonly property string regionName: root.mullvadRegionTitle(peer)
    readonly property string regionDetail: root.mullvadRegionSubtitle(peer)
    readonly property bool activeExitNode: peer && peer.ExitNode === true
    readonly property bool settingExitNode: peer && tailscale.settingExitNodeId === String(peer.id || "")
    readonly property bool selectedRegion: root.mullvadPickerOpen && root.mullvadRegionIndex === rowIndex
    readonly property string actionTooltip: activeExitNode ? "Disconnect" : "Connect"

    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    current: activeExitNode || settingExitNode || selectedRegion
    implicitHeight: row.implicitHeight + Style.spacing.lg

    Row {
      id: row
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: "󰖂"
        color: regionRow.current ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(30)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: regionRow.regionName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: regionRow.activeExitNode
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: regionRow.regionDetail
          visible: text !== ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      id: regionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.mullvadRegionIndex = regionRow.rowIndex
      onClicked: root.chooseExitNode(regionRow.peer)
    }

    PanelToolTip {
      visible: regionMouse.containsMouse
      text: regionRow.actionTooltip
      fontFamily: root.fontFamily
    }
  }
}
