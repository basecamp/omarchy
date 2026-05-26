import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.tailscale"

  property bool popupOpen: false
  property string focusSection: "header"
  property int headerIndex: 0
  property int accountIndex: 0
  property int peerIndex: 0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color card: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.055)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showAccounts: tailscale.accounts.length > 1
  readonly property bool showPeers: tailscale.peers.length > 0
  readonly property color iconColor: tailscale.running ? foreground : (tailscale.needsLogin ? urgent : dim)

  function close() { popupOpen = false }

  function openPanel() {
    popupOpen = true
    tailscale.refresh()
  }

  function togglePanel() {
    if (popupOpen) close()
    else openPanel()
  }

  function tooltipText() {
    var lines = ["Tailscale: " + tailscale.statusText]
    if (tailscale.selfIp !== "") lines.push(tailscale.selfName + " · " + tailscale.selfIp)
    if (tailscale.selectedAccountLabel !== "") lines.push(tailscale.selectedAccountLabel)
    if (tailscale.running) lines.push(tailscale.peers.length + " peer" + (tailscale.peers.length === 1 ? "" : "s"))
    return lines.join("\n")
  }

  function selectedPeer() {
    if (tailscale.peers.length === 0) return null
    return tailscale.peers[Math.max(0, Math.min(peerIndex, tailscale.peers.length - 1))]
  }

  function selectedAccount() {
    if (tailscale.accounts.length === 0) return null
    return tailscale.accounts[Math.max(0, Math.min(accountIndex, tailscale.accounts.length - 1))]
  }

  function ensureCursor() {
    if (headerIndex < 0) headerIndex = 0
    if (headerIndex > 1) headerIndex = 1
    if (accountIndex >= tailscale.accounts.length) accountIndex = Math.max(0, tailscale.accounts.length - 1)
    if (peerIndex >= tailscale.peers.length) peerIndex = Math.max(0, tailscale.peers.length - 1)
    if (focusSection === "accounts" && !showAccounts) focusSection = showPeers ? "peers" : "header"
    if (focusSection === "peers" && !showPeers) focusSection = showAccounts ? "accounts" : "header"
  }

  function moveCursor(dx, dy) {
    ensureCursor()
    if (dy !== 0) {
      if (focusSection === "header") {
        if (dy > 0) {
          if (showAccounts) focusSection = "accounts"
          else if (showPeers) focusSection = "peers"
        }
      } else if (focusSection === "accounts") {
        if (dy < 0) {
          if (accountIndex <= 0) focusSection = "header"
          else accountIndex--
        } else {
          if (accountIndex < tailscale.accounts.length - 1) accountIndex++
          else if (showPeers) focusSection = "peers"
        }
      } else if (focusSection === "peers") {
        if (dy < 0) {
          if (peerIndex <= 0) focusSection = showAccounts ? "accounts" : "header"
          else peerIndex--
        } else if (peerIndex < tailscale.peers.length - 1) {
          peerIndex++
        }
      }
    }
    if (dx !== 0 && focusSection === "header") headerIndex = (headerIndex + dx + 2) % 2
    ensureCursor()
    scrollPeerIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") {
      if (headerIndex === 0) tailscale.toggleTailscale()
      else tailscale.refresh()
    } else if (focusSection === "accounts") {
      var account = selectedAccount()
      if (account) tailscale.switchAccount(account.id)
    } else if (focusSection === "peers") {
      tailscale.copyPeerIp(selectedPeer())
    }
  }

  function scrollPeerIntoView() {
    if (focusSection !== "peers" || !peerFlick || !peerColumn) return
    Qt.callLater(function() {
      if (root.focusSection !== "peers" || root.peerIndex < 0 || root.peerIndex >= peerColumn.children.length) return
      var item = peerColumn.children[root.peerIndex]
      if (!item) return
      var margin = Style.space(6)
      var top = item.y
      var bottom = top + item.height
      var viewTop = peerFlick.contentY
      var viewBottom = viewTop + peerFlick.height
      var maxY = Math.max(0, peerFlick.contentHeight - peerFlick.height)
      if (top < viewTop + margin) peerFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) peerFlick.contentY = Math.min(maxY, bottom + margin - peerFlick.height)
    })
  }

  function setPeerCursor(index) {
    focusSection = "peers"
    peerIndex = index
    scrollPeerIntoView()
  }

  function setAccountCursor(index) {
    focusSection = "accounts"
    accountIndex = index
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onPopupOpenChanged: if (popupOpen) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  onPeerIndexChanged: scrollPeerIntoView()
  onShowAccountsChanged: ensureCursor()
  onShowPeersChanged: ensureCursor()

  Main {
    id: tailscale
    settings: root.settings
    onPeersChanged: root.ensureCursor()
    onAccountsChanged: root.ensureCursor()
  }

  Item {
    id: button
    anchors.fill: parent
    implicitWidth: root.bar && root.bar.vertical ? root.bar.barSize : Style.space(26)
    implicitHeight: root.bar && root.bar.vertical ? Style.space(26) : (root.bar ? root.bar.barSize : Style.space(26))

    property var registeredBar: null
    readonly property bool tooltipHovered: mouseArea.containsMouse

    function triggerPress(buttonCode) {
      if (root.bar) root.bar.hideTooltip(button)
      if (buttonCode === Qt.RightButton) tailscale.toggleTailscale()
      else if (buttonCode === Qt.MiddleButton) tailscale.refresh()
      else root.togglePanel()
    }

    function syncClickRegistration() {
      if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(button)
      registeredBar = root.bar
      if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(button)
    }

    Component.onCompleted: syncClickRegistration()
    Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(button)

    Connections {
      target: root
      function onBarChanged() { button.syncClickRegistration() }
    }

    TailscaleIcon {
      anchors.centerIn: parent
      iconSize: Style.space(12)
      color: root.iconColor
      badgeColor: root.urgent
      crossed: !tailscale.running && !tailscale.needsLogin
      warning: tailscale.needsLogin
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(button, root.tooltipText())
      onExited: if (root.bar) root.bar.hideTooltip(button)
      onClicked: function(mouse) { button.triggerPress(mouse.button) }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(580))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") tailscale.refresh()
        else if (t === "t" || t === "T") tailscale.toggleTailscale()
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
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroText.implicitHeight, headerActions.implicitHeight)

            TailscaleIcon {
              id: heroIcon
              iconSize: Style.font.display
              color: root.iconColor
              badgeColor: root.urgent
              crossed: !tailscale.running && !tailscale.needsLogin
              warning: tailscale.needsLogin
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroText
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(12)
              anchors.right: headerActions.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: tailscale.installed ? (tailscale.selfName || "Tailscale") : "Tailscale"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: {
                  var parts = [tailscale.statusText]
                  if (tailscale.selfIp !== "") parts.push(tailscale.selfIp)
                  if (tailscale.running) parts.push(tailscale.peers.length + " peer" + (tailscale.peers.length === 1 ? "" : "s"))
                  return parts.join(" · ").toUpperCase()
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }
            }

            Row {
              id: headerActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(5)

              PanelActionButton {
                id: toggleBtn
                anchors.verticalCenter: parent.verticalCenter
                iconText: "⏻"
                fontSize: Style.font.heading
                size: Style.space(30)
                tooltipText: tailscale.running ? "Disconnect Tailscale" : (tailscale.needsLogin ? "Log in to Tailscale" : "Connect Tailscale")
                foreground: root.foreground
                hoverColor: tailscale.running ? root.urgent : root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.focusSection === "header" && root.headerIndex === 0
                enabled: tailscale.installed && !tailscale.busy
                onHovered: function(h) {
                  if (!h) return
                  root.focusSection = "header"
                  root.headerIndex = 0
                }
                onClicked: tailscale.toggleTailscale()
              }

              PanelActionButton {
                id: refreshBtn
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰑐"
                fontSize: Style.font.heading
                size: Style.space(30)
                tooltipText: "Refresh"
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.focusSection === "header" && root.headerIndex === 1
                enabled: !tailscale.busy
                onHovered: function(h) {
                  if (!h) return
                  root.focusSection = "header"
                  root.headerIndex = 1
                }
                onClicked: tailscale.refresh()
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

          Rectangle {
            visible: !tailscale.installed
            width: parent.width
            implicitHeight: missingText.implicitHeight + Style.space(24)
            color: root.card
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            border.width: Style.normalBorderWidth
            radius: Style.cornerRadius

            Text {
              id: missingText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "Tailscale CLI is not installed or not on PATH."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator {
            visible: root.showAccounts
            foreground: root.foreground
          }

          Column {
            visible: root.showAccounts
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "ACCOUNTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
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
            visible: tailscale.installed
            foreground: root.foreground
          }

          Column {
            visible: tailscale.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "PEERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: tailscale.installed && tailscale.running && tailscale.peers.length === 0
              width: parent.width
              text: "No peers found on this tailnet."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              visible: tailscale.installed && !tailscale.running
              width: parent.width
              text: tailscale.needsLogin ? "Log in to see tailnet peers." : "Turn Tailscale on to see tailnet peers."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Flickable {
              id: peerFlick
              visible: tailscale.peers.length > 0
              width: parent.width
              height: Math.min(peerColumn.implicitHeight, Style.space(340))
              contentWidth: width
              contentHeight: peerColumn.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              Column {
                id: peerColumn
                width: peerFlick.width
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
  }

  component AccountRow: Rectangle {
    id: accountRow
    property var account: null
    property int rowIndex: 0
    readonly property bool selectedAccount: account && account.selected === true
    readonly property bool hasCursor: root.focusSection === "accounts" && root.accountIndex === rowIndex

    implicitHeight: row.implicitHeight + Style.space(12)
    color: hasCursor ? Style.hoverFillFor(root.foreground, root.urgent) : (selectedAccount ? root.card : "transparent")
    border.color: hasCursor ? Style.hoverBorderFor(root.foreground, root.urgent) : "transparent"
    border.width: hasCursor ? Style.hoverBorderWidth : 0
    radius: Style.cornerRadius

    RowLayout {
      id: row
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: accountRow.selectedAccount ? "●" : "○"
        color: accountRow.selectedAccount ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          text: account ? (account.nickname || account.tailnet || account.account || account.id || "Account") : "Account"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: account ? [account.tailnet || "", account.account || ""].filter(function(x) { return String(x) !== "" }).join(" · ") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
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

  component PeerRow: Rectangle {
    id: peerRow
    property var peer: null
    property int rowIndex: 0
    readonly property bool online: peer && peer.Online === true
    readonly property bool hasCursor: root.focusSection === "peers" && root.peerIndex === rowIndex
    readonly property string peerName: peer ? String(peer.HostName || "Unknown") : "Unknown"
    readonly property string peerIp: peer && peer.TailscaleIPs && peer.TailscaleIPs.length > 0 ? String(peer.TailscaleIPs[0]) : ""
    readonly property string peerDns: peer ? String(peer.DNSName || "") : ""

    implicitHeight: Math.max(peerContent.implicitHeight, actions.implicitHeight) + Style.space(12)
    color: hasCursor ? Style.hoverFillFor(root.foreground, root.urgent) : root.card
    border.color: hasCursor ? Style.hoverBorderFor(root.foreground, root.urgent) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
    border.width: hasCursor ? Style.hoverBorderWidth : Style.normalBorderWidth
    radius: Style.cornerRadius
    opacity: online ? 1.0 : 0.62

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
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: {
            var parts = []
            if (peerRow.peerIp !== "") parts.push(peerRow.peerIp)
            if (peerRow.peerDns !== "") parts.push(peerRow.peerDns)
            if (!peerRow.online) parts.push("offline")
            return parts.join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Row {
        id: actions
        spacing: Style.space(2)
        Layout.alignment: Qt.AlignVCenter

        PanelActionButton {
          iconText: "󰆏"
          tooltipText: "Copy IP"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: peerRow.peerIp !== ""
          onClicked: tailscale.copyPeerIp(peerRow.peer)
        }

        PanelActionButton {
          iconText: "󰉿"
          tooltipText: "Copy name"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: peerRow.peerName !== ""
          onClicked: tailscale.copyPeerName(peerRow.peer)
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      z: -1
      onEntered: root.setPeerCursor(peerRow.rowIndex)
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) tailscale.copyPeerName(peerRow.peer)
        else if (mouse.button === Qt.MiddleButton) tailscale.copyPeerDnsName(peerRow.peer)
        else tailscale.copyPeerIp(peerRow.peer)
      }
    }
  }
}
