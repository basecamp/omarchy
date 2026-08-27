import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.netbird"
  ipcTarget: "omarchy.netbird"
  manageIpc: false

  property string focusSection: "header"
  property int noticeIndex: 0
  property int profileIndex: 0
  property int routeIndex: 0
  property int peerIndex: 0
  property bool cursorActive: false
  property bool suppressCursorScroll: false
  property bool copyMenuOpen: false
  property int phraseIndex: 0
  readonly property var activePhrases: [
    "Meshing peers",
    "Holding tunnels",
    "Punching through NAT",
    "Trading keys",
    "Watching the network",
    "Keeping routes warm",
    "Guarding wires",
    "Counting hops"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Things worth interrupting the user about, in the order they block usage: a
  // daemon that is not running beats DNS that resolves the wrong way.
  readonly property var notices: {
    var list = []
    if (netbird.daemonInactive) {
      list.push({
        kind: "daemon",
        glyph: "󰙧",
        title: "Start the NetBird daemon",
        subtitle: "netbird.service is not running",
        actionable: true
      })
    }
    if (netbird.permissionDenied) {
      list.push({
        kind: "permission",
        glyph: "󰌾",
        title: "Cannot reach the NetBird daemon",
        subtitle: "This user has no access to the daemon socket",
        actionable: false
      })
    }
    if (netbird.dnsOverride !== "") {
      list.push({
        kind: "dns",
        glyph: "󰇖",
        title: "System DNS is set to " + netbird.dnsOverride,
        subtitle: "That can override the DNS NetBird serves · hand it back to DHCP",
        actionable: true
      })
    }
    return list
  }

  // Each list section folds away; its header stays, carrying the summary.
  property var collapsedSections: Model.defaultCollapsedSections()

  function sectionCollapsed(name) {
    return collapsedSections[name] === true
  }

  function toggleSectionCollapsed(name) {
    var next = {}
    for (var key in collapsedSections) next[key] = collapsedSections[key]
    next[name] = !(next[name] === true)
    collapsedSections = next

    // Collapsing the section the cursor sits in would otherwise leave it
    // steering rows nobody can see.
    ensureCursor()
    saveCollapsed()
  }

  function saveCollapsed() {
    collapsedFile.setText(JSON.stringify(Model.collapsedSectionsFile(collapsedSections), null, 2) + "\n")
  }

  property FileView collapsedFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/netbird.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.collapsedSections = Model.parseCollapsedSections(text())
    // First run: no file yet. Defaults apply only here, so a stored choice wins.
    onLoadFailed: root.collapsedSections = Model.defaultCollapsedSections()
  }

  // The first read can race shell startup (see the weather panel); one delayed
  // reload self-corrects.
  Timer {
    interval: 1500
    running: true
    onTriggered: root.collapsedFile.reload()
  }

  readonly property bool showNotices: notices.length > 0
  readonly property bool hasProfiles: netbird.profiles.length > 1
  readonly property bool hasRoutes: netbird.active && netbird.routes.length > 0
  readonly property bool hasPeers: netbird.active && netbird.peers.length > 0
  readonly property bool showProfiles: hasProfiles && !sectionCollapsed("profiles")
  readonly property bool showRoutes: hasRoutes && !sectionCollapsed("routes")
  readonly property bool showPeers: hasPeers && !sectionCollapsed("peers")

  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && netbird.installed
  readonly property color iconColor: netbird.active ? foreground : dim
  readonly property string toggleHint: netbird.active ? "Disconnect NetBird" : (netbird.needsLogin ? "Log in to NetBird" : "Connect NetBird")
  readonly property color barIconColor: netbird.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  // Cursor movement runs off this list, so a section that disappears cannot
  // strand the cursor.
  function sections() {
    var list = ["header"]
    if (showNotices) list.push("notices")
    // Headings are cursor stops of their own — the keyboard's only way back
    // into a folded section.
    if (hasProfiles) {
      list.push("profilesHeader")
      if (showProfiles) list.push("profiles")
    }
    if (hasRoutes) {
      list.push("routesHeader")
      if (showRoutes) list.push("routes")
    }
    if (netbird.installed && netbird.active) {
      list.push("peersHeader")
      if (showPeers) list.push("peers")
    }
    return list
  }

  // "profilesHeader" → "profiles"; a row section names itself.
  function collapsibleSectionFor(name) {
    if (name.length > 6 && name.indexOf("Header") === name.length - 6) return name.slice(0, -6)
    if (name === "profiles" || name === "routes" || name === "peers") return name
    return ""
  }

  function sectionLength(name) {
    if (name === "header") return 1
    if (name === "notices") return notices.length
    if (name === "profilesHeader" || name === "routesHeader" || name === "peersHeader") return 1
    if (name === "profiles") return netbird.profiles.length
    if (name === "routes") return netbird.routes.length
    if (name === "peers") return netbird.peers.length
    return 0
  }

  function sectionIndex(name) {
    if (name === "notices") return noticeIndex
    if (name === "profiles") return profileIndex
    if (name === "routes") return routeIndex
    if (name === "peers") return peerIndex
    return 0
  }

  function setSectionIndex(name, value) {
    var length = sectionLength(name)
    var clamped = Math.max(0, Math.min(value, length - 1))
    if (name === "notices") noticeIndex = clamped
    else if (name === "profiles") profileIndex = clamped
    else if (name === "routes") routeIndex = clamped
    else if (name === "peers") peerIndex = clamped
  }

  function selectedPeer() {
    if (netbird.peers.length === 0) return null
    return netbird.peers[Math.max(0, Math.min(peerIndex, netbird.peers.length - 1))]
  }

  // Copy keys act only while the peer list is the focused, visible section.
  function copyTargetPeer() {
    if (focusSection !== "peers" || !showPeers) return null
    return selectedPeer()
  }

  function selectedRoute() {
    if (netbird.routes.length === 0) return null
    return netbird.routes[Math.max(0, Math.min(routeIndex, netbird.routes.length - 1))]
  }

  function selectedProfile() {
    if (netbird.profiles.length === 0) return null
    return netbird.profiles[Math.max(0, Math.min(profileIndex, netbird.profiles.length - 1))]
  }

  function selectedNotice() {
    if (notices.length === 0) return null
    return notices[Math.max(0, Math.min(noticeIndex, notices.length - 1))]
  }

  function ensureCursor() {
    var available = sections()
    if (available.indexOf(focusSection) === -1) {
      // A folded section's heading is still on screen; land there, not the hero.
      var fallback = collapsibleSectionFor(focusSection)
      focusSection = fallback !== "" && available.indexOf(fallback + "Header") !== -1
        ? fallback + "Header"
        : available[0]
    }
    for (var i = 0; i < available.length; i++) setSectionIndex(available[i], sectionIndex(available[i]))
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) {
      if (dx === 0) return
      // Left folds, right unfolds, from the heading or anywhere in its rows.
      var name = collapsibleSectionFor(focusSection)
      if (name === "") return
      var folded = sectionCollapsed(name)
      if (dx < 0 && !folded) {
        focusSection = name + "Header"
        toggleSectionCollapsed(name)
      } else if (dx > 0 && folded) {
        toggleSectionCollapsed(name)
      }
      return
    }

    var available = sections()
    var at = available.indexOf(focusSection)
    if (at === -1) at = 0

    var index = sectionIndex(focusSection)
    var length = sectionLength(focusSection)

    if (dy > 0) {
      if (index < length - 1) setSectionIndex(focusSection, index + 1)
      else if (at < available.length - 1) {
        focusSection = available[at + 1]
        setSectionIndex(focusSection, 0)
      }
    } else {
      if (index > 0) setSectionIndex(focusSection, index - 1)
      else if (at > 0) {
        focusSection = available[at - 1]
        setSectionIndex(focusSection, sectionLength(focusSection) - 1)
      }
    }

    ensureCursor()
    scrollCursorIntoView()
  }

  function setSectionHeaderCursor(name) {
    cursorActive = true
    focusSection = name + "Header"
  }

  function activateCursor() {
    ensureCursor()
    var collapsible = collapsibleSectionFor(focusSection)
    if (focusSection === "header") {
      netbird.toggleNetbird()
    } else if (collapsible !== "" && focusSection === collapsible + "Header") {
      toggleSectionCollapsed(collapsible)
    } else if (focusSection === "notices") {
      activateNotice(selectedNotice())
    } else if (focusSection === "profiles") {
      var profile = selectedProfile()
      if (profile) netbird.switchProfile(profile.name)
    } else if (focusSection === "routes") {
      netbird.toggleRoute(selectedRoute())
    } else if (focusSection === "peers") {
      openSelectedPeerCopyMenu()
    }
  }

  function activateNotice(notice) {
    if (!notice || notice.actionable !== true) return
    if (notice.kind === "daemon") netbird.startDaemon()
    else if (notice.kind === "dns") netbird.useDhcpDns()
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
    // Hover must not scroll: a fold reflows rows under the stationary pointer,
    // and the hover that follows would yank the view. Only deliberate movement
    // scrolls.
    if (suppressCursorScroll) return
    if (focusSection === "peers" && peerColumn && peerIndex >= 0 && peerIndex < peerColumn.children.length) scrollItemIntoView(peerColumn.children[peerIndex])
    else if (focusSection === "routes" && routeColumn && routeIndex >= 0 && routeIndex < routeColumn.children.length) scrollItemIntoView(routeColumn.children[routeIndex])
  }

  function setPeerCursor(index) {
    cursorActive = true
    suppressCursorScroll = true
    focusSection = "peers"
    peerIndex = index
    suppressCursorScroll = false
  }

  function setRouteCursor(index) {
    cursorActive = true
    suppressCursorScroll = true
    focusSection = "routes"
    routeIndex = index
    suppressCursorScroll = false
  }

  function setProfileCursor(index) {
    cursorActive = true
    focusSection = "profiles"
    profileIndex = index
  }

  function setNoticeCursor(index) {
    cursorActive = true
    focusSection = "notices"
    noticeIndex = index
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
  }

  function openSelectedPeerCopyMenu() {
    if (!peerColumn || peerIndex < 0 || peerIndex >= peerColumn.children.length) return
    var item = peerColumn.children[peerIndex]
    if (item && item.openCopyMenu) item.openCopyMenu()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    netbird.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onPeerIndexChanged: scrollCursorIntoView()
  onRouteIndexChanged: scrollCursorIntoView()
  onShowNoticesChanged: ensureCursor()
  onShowProfilesChanged: ensureCursor()
  onShowRoutesChanged: ensureCursor()
  onShowPeersChanged: ensureCursor()

  Service {
    id: netbird
    settings: root.settings
  }

  Connections {
    target: netbird
    function onPeersChanged() { root.ensureCursor() }
    function onRoutesChanged() { root.ensureCursor() }
    function onProfilesChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { netbird.refresh(); return "ok" }
    function up(): string { netbird.loginOrUp(); return "ok" }
    function down(): string { netbird.down(); return "ok" }
    function toggleNetbird(): string { netbird.toggleNetbird(); return "ok" }
    function status(): string { return netbird.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        NetbirdIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          badgeColor: root.urgent
          crossed: !netbird.active && !netbird.needsLogin
          warning: netbird.needsLogin
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) netbird.toggleNetbird()
      else if (buttonCode === Qt.MiddleButton) netbird.refresh()
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
        if (t === "t" || t === "T") netbird.toggleNetbird()
        else if (t === "c" || t === "C") netbird.copyPeerIp(root.copyTargetPeer())
        else if (t === "n" || t === "N") netbird.copyPeerName(root.copyTargetPeer())
        else if (t === "d" || t === "D") netbird.copyPeerFqdn(root.copyTargetPeer())
        else if (t === "r" || t === "R") netbird.refresh(true)
        else if (t === "a" || t === "A") netbird.openAdminConsole()
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
        ScrollBar.vertical: ScrollBar { id: panelScrollBar; policy: ScrollBar.AsNeeded }

        Column {
          id: column
          // Reserve the scrollbar's band: it is an overlay that owns the
          // clicks in that strip.
          width: panelFlick.width - (panelScrollBar.visible ? panelScrollBar.width : 0)
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // Exposed for the hero's trailingControl, whose `root` resolves to
            // PanelHero (not this Panel) — reach panel state via `header`.
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: netbird.installed ? (netbird.selfName || "NetBird") : "NetBird"
              meta: netbird.active ? root.heroPhraseText : (netbird.needsLogin ? "NetBird needs a login" : "NetBird is disconnected")
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: netbird.active ? 1.0 : 0.5
              // Status only — the switch owns toggling, mouse and keyboard alike.
              iconComponent: Component {
                NetbirdIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  badgeColor: root.urgent
                  crossed: !netbird.active && !netbird.needsLogin
                  warning: netbird.needsLogin
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: netbird.installed
                  checked: netbird.active
                  busy: netbird.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: netbird.toggleNetbird()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: netbird.actionStatus !== "" || netbird.lastError !== ""
            width: parent.width
            text: netbird.actionStatus !== "" ? netbird.actionStatus : netbird.lastError
            color: netbird.lastError !== "" && netbird.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // The tunnel reports healthy right up until the session lapses; the
          // countdown earns its line.
          Text {
            visible: netbird.installed && netbird.sessionExpiry.text !== ""
            width: parent.width
            text: netbird.sessionExpiry.text
            color: netbird.sessionExpiry.urgent ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          CursorSurface {
            visible: !netbird.installed
            width: parent.width
            implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: missingText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "NetBird CLI is not installed or not on PATH."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator {
            visible: root.showNotices
            foreground: root.foreground
          }

          Column {
            visible: root.showNotices
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.notices
              NoticeRow {
                required property var modelData
                required property int index
                width: parent.width
                notice: modelData
                rowIndex: index
              }
            }
          }

          PanelSeparator {
            visible: root.hasProfiles
            foreground: root.foreground
          }

          Column {
            visible: root.hasProfiles
            width: parent.width
            spacing: Style.space(10)

            CollapsibleHeader {
              width: parent.width
              section: "profiles"
              label: "PROFILES"
              summary: Model.profilesSummary(netbird.selectedProfileName)
            }

            Repeater {
              model: root.showProfiles ? netbird.profiles : []
              ProfileRow {
                required property var modelData
                required property int index
                width: parent.width
                profile: modelData
                rowIndex: index
              }
            }
          }

          PanelSeparator {
            visible: root.hasRoutes
            foreground: root.foreground
          }

          Column {
            visible: root.hasRoutes
            width: parent.width
            spacing: Style.space(10)

            CollapsibleHeader {
              width: parent.width
              section: "routes"
              label: "ROUTES"
              summary: Model.routesSummary(netbird.routes)
            }

            Column {
              id: routeColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.showRoutes ? netbird.routes : []
                RouteRow {
                  required property var modelData
                  required property int index
                  width: routeColumn.width
                  route: modelData
                  rowIndex: index
                }
              }
            }
          }

          PanelSeparator {
            visible: netbird.installed && netbird.active
            foreground: root.foreground
          }

          Column {
            visible: netbird.installed && netbird.active
            width: parent.width
            spacing: Style.space(10)

            CollapsibleHeader {
              width: parent.width
              section: "peers"
              label: "PEERS"
              summary: netbird.totalPeers > 0
                ? netbird.connectedPeers + "/" + netbird.totalPeers + " CONNECTED"
                : ""
            }

            Text {
              // Not showPeers — that requires peers to exist.
              visible: netbird.installed && netbird.active && !root.sectionCollapsed("peers") && netbird.peers.length === 0
              width: parent.width
              text: "No peers found on this network."
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
                model: root.showPeers ? netbird.peers : []
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

          PanelSeparator {
            visible: netbird.installed && netbird.active && netbird.healthRows.length > 0
            foreground: root.foreground
          }

          Column {
            id: healthColumn
            visible: netbird.installed && netbird.active && netbird.healthRows.length > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "HEALTH"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: netbird.healthRows

              RowLayout {
                required property var modelData

                width: healthColumn.width
                spacing: Style.space(8)

                Text {
                  text: modelData.label
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  Layout.preferredWidth: Math.round(healthColumn.width * 0.3)
                }

                Text {
                  Layout.fillWidth: true
                  text: modelData.detail !== "" ? modelData.value + " · " + modelData.detail : modelData.value
                  color: modelData.warn ? root.urgent : root.foreground
                  opacity: modelData.warn ? 1.0 : 0.75
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignRight
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
    running: root.opened && netbird.active
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

  component NoticeRow: CursorSurface {
    id: noticeRow
    property var notice: null
    property int rowIndex: 0
    readonly property bool actionable: notice && notice.actionable === true
    readonly property bool working: notice && ((notice.kind === "dns" && netbird.fixingDns) || (notice.kind === "daemon" && netbird.busy && netbird.daemonInactive))

    hasCursor: root.cursorActive && root.focusSection === "notices" && root.noticeIndex === rowIndex
    foreground: root.foreground
    fill: root.hoverFill

    implicitHeight: noticeInner.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: noticeRow.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: root.setNoticeCursor(noticeRow.rowIndex)
      onClicked: root.activateNotice(noticeRow.notice)
    }

    RowLayout {
      id: noticeInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: noticeRow.notice ? String(noticeRow.notice.glyph || "󰀦") : "󰀦"
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Layout.alignment: Qt.AlignVCenter
        opacity: noticeRow.working ? 0.45 : 1.0

        SequentialAnimation on opacity {
          running: noticeRow.working
          NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 0.45; duration: 420; easing.type: Easing.InOutQuad }
          loops: Animation.Infinite
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: noticeRow.notice ? String(noticeRow.notice.title || "") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: noticeRow.notice ? String(noticeRow.notice.subtitle || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  component ProfileRow: CursorSurface {
    id: profileRow
    property var profile: null
    property int rowIndex: 0
    readonly property bool selectedProfile: profile && profile.selected === true
    readonly property bool switchingProfile: profile && netbird.switchingProfileName === String(profile.name || "")
    readonly property string profileText: profile ? netbird.profileLabel(profile) : "Profile"

    hasCursor: root.cursorActive && root.focusSection === "profiles" && root.profileIndex === rowIndex
    current: selectedProfile
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

    implicitHeight: profileInner.implicitHeight + Style.spacing.xl

    Row {
      id: profileInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: "󰀄"
        color: profileRow.selectedProfile || profileRow.switchingProfile ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
        opacity: profileRow.switchingProfile ? 0.45 : 1.0

        SequentialAnimation on opacity {
          running: profileRow.switchingProfile
          NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 0.45; duration: 420; easing.type: Easing.InOutQuad }
          loops: Animation.Infinite
        }
      }

      Text {
        text: profileRow.profileText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: profileRow.selectedProfile
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setProfileCursor(profileRow.rowIndex)
      onClicked: if (profileRow.profile) netbird.switchProfile(profileRow.profile.name)
    }
  }

  component RouteRow: CursorSurface {
    id: routeRow
    property var route: null
    property int rowIndex: 0
    readonly property bool selectedRoute: route && route.Selected === true
    readonly property bool settingRoute: route && netbird.settingRouteId === String(route.id || "")
    readonly property bool exitNode: route && route.ExitNode === true
    readonly property string routeName: route ? String(route.DisplayName || "Route") : "Route"
    readonly property string routeDetail: route ? String(route.Detail || "") : ""
    readonly property string actionTooltip: selectedRoute ? "Deselect" : "Select"

    hasCursor: root.cursorActive && root.focusSection === "routes" && root.routeIndex === rowIndex
    current: selectedRoute || settingRoute
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

    implicitHeight: routeInner.implicitHeight + Style.spacing.lg

    Row {
      id: routeInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: routeRow.exitNode ? "󰖂" : "󱇢"
        color: routeRow.selectedRoute || routeRow.settingRoute ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter

        NumberAnimation on rotation {
          running: routeRow.settingRoute
          from: 0
          to: 360
          duration: 900
          loops: Animation.Infinite
        }

        onRotationChanged: if (!routeRow.settingRoute && rotation !== 0) rotation = 0
      }

      Column {
        width: parent.width - Style.space(30)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: routeRow.routeName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: routeRow.selectedRoute
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: routeRow.routeDetail
          visible: text !== ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      id: routeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setRouteCursor(routeRow.rowIndex)
      onClicked: netbird.toggleRoute(routeRow.route)
    }

    PanelToolTip {
      visible: routeMouse.containsMouse
      text: routeRow.actionTooltip
      fontFamily: root.fontFamily
    }
  }

  // A section header that folds its own rows away, keeping its summary.
  component CollapsibleHeader: CursorSurface {
    id: headerRoot

    required property string section
    required property string label
    property string summary: ""

    readonly property bool folded: root.sectionCollapsed(section)

    hasCursor: root.cursorActive && root.focusSection === section + "Header"
    foreground: root.foreground
    fill: root.hoverFill

    implicitHeight: headerRow.implicitHeight + Style.space(6)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setSectionHeaderCursor(headerRoot.section)
      onClicked: root.toggleSectionCollapsed(headerRoot.section)
    }

    RowLayout {
      id: headerRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(6)

      // Leads the label: the scrollbar overlay owns clicks at the right edge.
      Text {
        Layout.alignment: Qt.AlignVCenter
        text: headerRoot.folded ? "󰅂" : "󰅀"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      PanelSectionHeader {
        Layout.fillWidth: true
        text: Model.sectionHeader(headerRoot.label, headerRoot.summary)
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
    }
  }

  component PeerRow: CursorSurface {
    id: peerRow
    property var peer: null
    property int rowIndex: 0
    readonly property string peerName: peer ? String(peer.DisplayName || "Unknown") : "Unknown"
    readonly property string peerIp: peer ? String(peer.IP || "") : ""
    readonly property string peerFqdn: peer ? String(peer.Fqdn || "") : ""
    readonly property bool peerOnline: peer && peer.Online === true
    readonly property var copyOptions: {
      var options = []
      if (peerName !== "") options.push({ kind: "name", label: peerName })
      if (peerFqdn !== "") options.push({ kind: "fqdn", label: peerFqdn })
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
      if (kind === "name") netbird.copyPeerName(peer)
      else if (kind === "fqdn") netbird.copyPeerFqdn(peer)
      else if (kind === "ip") netbird.copyPeerIp(peer)
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
        text: netbird.osIcon(peerRow.peer ? peerRow.peer.OS : "")
        color: root.foreground
        // Idle peers are the norm; dim them rather than hide them.
        opacity: peerRow.peerOnline ? 1.0 : 0.45
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
          opacity: peerRow.peerOnline ? 1.0 : 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: {
            var parts = []
            if (peerRow.peerIp !== "") parts.push(peerRow.peerIp)
            var connection = netbird.connectionLabel(peerRow.peer)
            if (connection !== "") parts.push(connection)
            return parts.join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: netbird.peerActivity(peerRow.peer)
          visible: text !== ""
          color: root.dim
          opacity: 0.75
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
        enabled: peerRow.copyOptions.length > 0
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
}
