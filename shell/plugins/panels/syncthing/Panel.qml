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
  moduleName: "omarchy.syncthing"
  ipcTarget: "omarchy.syncthing"
  manageIpc: false

  property string focusSection: "header"
  property int folderIndex: 0
  property int deviceIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0

  readonly property var syncthing: bar && bar.shell ? bar.shell.firstPartyServiceFor(root.moduleName) : null
  readonly property var syncPhrases: [
    "Comparing hashes",
    "Negotiating blocks",
    "Reconciling folders",
    "Moving changes",
    "Checking versions",
    "Connecting devices"
  ]
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property bool running: syncthing ? syncthing.serviceRunning : false
  readonly property bool active: syncthing ? syncthing.active : false
  readonly property bool authenticated: syncthing ? syncthing.authenticated : false
  readonly property bool syncing: syncthing ? syncthing.syncing : false
  readonly property bool warning: syncthing ? syncthing.hasAttention || syncthing.serviceState === "failed" : false
  readonly property var folders: syncthing ? syncthing.folders : []
  readonly property var devices: syncthing ? syncthing.devices : []
  readonly property bool showFolders: authenticated && folders.length > 0
  readonly property bool showDevices: authenticated && devices.length > 0
  readonly property int folderProblemCount: {
    var count = 0
    for (var i = 0; i < folders.length; i++) if (Model.folderHasProblem(folders[i])) count++
    return count
  }
  readonly property int attentionCount: syncthing
    ? folderProblemCount + syncthing.pendingDevices.length + syncthing.pendingFolders.length + syncthing.systemErrors.length
    : 0
  readonly property bool showAttention: authenticated && attentionCount > 0
  readonly property bool showWebUi: syncthing && syncthing.guiUrl !== ""
  readonly property color iconColor: active ? foreground : dim
  readonly property color barIconColor: active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property string toggleHint: active ? "Stop Syncthing" : "Start Syncthing"
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && syncthing && syncthing.installed
  readonly property string heroMeta: {
    if (!syncthing) return "Loading integration"
    if (!syncthing.installed) return "Not installed"
    if (!active) return syncthing.serviceState === "failed" ? "Service failed" : "Syncing stopped"
    if (!authenticated) return syncthing.message || "Local API unavailable"
    if (syncthing.overall === "error") return "Sync needs attention"
    if (syncthing.overall === "attention") return "Sharing request waiting"
    if (syncthing.overall === "syncing") return syncPhrases[phraseIndex % syncPhrases.length] + " · " + Model.formatPercent(syncthing.syncPercent)
    if (syncthing.overall === "scanning") return "Scanning folders"
    if (syncthing.overall === "paused") return "All folders paused"
    return "Everything is up to date"
  }

  function configureService() {
    if (syncthing) syncthing.configure(settings)
  }

  function selectedFolder() {
    if (folders.length === 0) return null
    return folders[Math.max(0, Math.min(folderIndex, folders.length - 1))]
  }

  function selectedDevice() {
    if (devices.length === 0) return null
    return devices[Math.max(0, Math.min(deviceIndex, devices.length - 1))]
  }

  function nextSection(current, direction) {
    var sections = ["header"]
    if (showAttention) sections.push("attention")
    if (showFolders) sections.push("folders")
    if (showDevices) sections.push("devices")
    if (showWebUi) sections.push("webui")
    var index = sections.indexOf(current)
    if (index < 0) index = 0
    return sections[Math.max(0, Math.min(sections.length - 1, index + direction))]
  }

  function ensureCursor() {
    if (folderIndex >= folders.length) folderIndex = Math.max(0, folders.length - 1)
    if (deviceIndex >= devices.length) deviceIndex = Math.max(0, devices.length - 1)
    if (focusSection === "attention" && !showAttention) focusSection = nextSection("attention", 1)
    if (focusSection === "folders" && !showFolders) focusSection = nextSection("folders", 1)
    if (focusSection === "devices" && !showDevices) focusSection = nextSection("devices", 1)
    if (focusSection === "webui" && !showWebUi) focusSection = nextSection("webui", -1)
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "folders") {
      if (dy < 0 && folderIndex > 0) folderIndex--
      else if (dy > 0 && folderIndex < folders.length - 1) folderIndex++
      else focusSection = nextSection("folders", dy > 0 ? 1 : -1)
    } else if (focusSection === "devices") {
      if (dy < 0 && deviceIndex > 0) deviceIndex--
      else if (dy > 0 && deviceIndex < devices.length - 1) deviceIndex++
      else focusSection = nextSection("devices", dy > 0 ? 1 : -1)
    } else {
      focusSection = nextSection(focusSection, dy > 0 ? 1 : -1)
      if (focusSection === "folders" && dy > 0) folderIndex = 0
      if (focusSection === "devices" && dy > 0) deviceIndex = 0
    }
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (!syncthing) return
    if (focusSection === "header") syncthing.toggleService()
    else if (focusSection === "attention" || focusSection === "webui") openWebUiAndClose()
    else if (focusSection === "folders") syncthing.openFolder(selectedFolder())
    else if (focusSection === "devices") syncthing.copyDeviceId(selectedDevice())
  }

  function openWebUiAndClose() {
    if (!syncthing) return
    syncthing.openWebUi()
    close()
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function setFolderCursor(index) {
    cursorActive = true
    focusSection = "folders"
    folderIndex = index
    scrollCursorIntoView()
  }

  function setDeviceCursor(index) {
    cursorActive = true
    focusSection = "devices"
    deviceIndex = index
    scrollCursorIntoView()
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
      var maximum = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maximum, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "folders" && folderIndex >= 0 && folderIndex < folderColumn.children.length)
      scrollItemIntoView(folderColumn.children[folderIndex])
    else if (focusSection === "devices" && deviceIndex >= 0 && deviceIndex < deviceColumn.children.length)
      scrollItemIntoView(deviceColumn.children[deviceIndex])
    else if (focusSection === "attention") scrollItemIntoView(attentionRow)
    else if (focusSection === "webui") scrollItemIntoView(webUiRow)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onSyncthingChanged: configureService()
  onSettingsChanged: configureService()
  onOpenedChanged: {
    if (syncthing) syncthing.panelOpen = opened
    if (opened) {
      cursorActive = false
      if (panelFlick) panelFlick.contentY = 0
      if (syncthing) syncthing.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }
  onFolderIndexChanged: scrollCursorIntoView()
  onDeviceIndexChanged: scrollCursorIntoView()
  onShowFoldersChanged: ensureCursor()
  onShowDevicesChanged: ensureCursor()
  Component.onCompleted: configureService()
  Component.onDestruction: if (syncthing && opened) syncthing.panelOpen = false

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { if (root.syncthing) root.syncthing.refresh(); return "ok" }
    function scanAll(): string { if (root.syncthing) root.syncthing.scan(""); return "ok" }
    function toggleService(): string { if (root.syncthing) root.syncthing.toggleService(); return "ok" }
    function openWebUi(): string { if (root.syncthing) root.syncthing.openWebUi(); return "ok" }
    function status(): string { return root.syncthing ? root.syncthing.statusText : "Unavailable" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: syncthing ? "Syncthing: " + syncthing.statusText : "Syncthing"
    active: root.warning
    iconComponent: Component {
      Item {
        SyncthingIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          badgeColor: root.urgent
          crossed: !root.active
          warning: root.warning
          spinning: root.syncing
        }
      }
    }
    onPressed: function(buttonCode) {
      if (!syncthing) return
      if (buttonCode === Qt.RightButton) syncthing.openWebUi()
      else if (buttonCode === Qt.MiddleButton) syncthing.refresh()
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
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (!syncthing) return
        if (text === "t" || text === "T") syncthing.toggleService()
        else if (text === "o" || text === "O") root.openWebUiAndClose()
        else if (text === "r" || text === "R") syncthing.scan(root.focusSection === "folders" && root.selectedFolder() ? root.selectedFolder().id : "")
        else if ((text === "p" || text === "P") && root.focusSection === "folders" && root.selectedFolder())
          syncthing.setFolderPaused(root.selectedFolder().id, !root.selectedFolder().paused)
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
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: syncthing && syncthing.myName ? syncthing.myName : "Syncthing"
              meta: root.heroMeta
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.active ? 1.0 : 0.5
              iconComponent: Component {
                SyncthingIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  badgeColor: root.urgent
                  crossed: !root.active
                  warning: root.warning
                  spinning: root.syncing
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: syncthing && syncthing.installed
                  checked: root.active
                  busy: syncthing ? syncthing.busy : false
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: if (syncthing) syncthing.toggleService()

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
            visible: syncthing && (syncthing.actionStatus !== "" || syncthing.lastError !== "")
            width: parent.width
            text: syncthing ? (syncthing.actionStatus !== "" ? syncthing.actionStatus : syncthing.lastError) : ""
            color: syncthing && syncthing.lastError !== "" && syncthing.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          CursorSurface {
            visible: syncthing && (!syncthing.installed || (root.active && !root.authenticated))
            width: parent.width
            implicitHeight: unavailableText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: unavailableText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: {
                if (!syncthing) return "Loading Syncthing status…"
                if (!syncthing.installed) return "Install Syncthing from Install › Service."
                if (syncthing.reason === "nonlocal-api") return "The native panel connects only to a loopback Syncthing API. Change the Web UI listen address to 127.0.0.1:8384 to use it."
                return syncthing.message || "The local Syncthing API is not ready yet."
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          AttentionRow {
            id: attentionRow
            visible: root.showAttention
            width: parent.width
          }

          PanelSeparator {
            visible: root.showFolders
            foreground: root.foreground
          }

          Column {
            visible: root.showFolders
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "FOLDERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: folderColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.folders
                FolderRow {
                  required property var modelData
                  required property int index
                  width: folderColumn.width
                  folder: modelData
                  rowIndex: index
                }
              }
            }
          }

          PanelSeparator {
            visible: root.showDevices
            foreground: root.foreground
          }

          Column {
            visible: root.showDevices
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "DEVICES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: deviceColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.devices
                DeviceRow {
                  required property var modelData
                  required property int index
                  width: deviceColumn.width
                  device: modelData
                  rowIndex: index
                }
              }
            }
          }

          PanelSeparator {
            visible: root.showWebUi
            foreground: root.foreground
          }

          WebUiRow {
            id: webUiRow
            visible: root.showWebUi
            width: parent.width
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.syncing
    repeat: true
    onTriggered: root.phraseIndex = (root.phraseIndex + 1) % root.syncPhrases.length
  }

  component AttentionRow: CursorSurface {
    id: attention
    hasCursor: root.cursorActive && root.focusSection === "attention"
    foreground: root.foreground
    fill: root.hoverFill
    implicitHeight: attentionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.focusSection = "attention" }
      onClicked: root.openWebUiAndClose()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: "󰀦"
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      ColumnLayout {
        id: attentionContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: root.attentionCount + (root.attentionCount === 1 ? " item needs attention" : " items need attention")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: "Errors and sharing requests open in the Web UI"
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "󰇘"
        tooltipText: "Open Syncthing Web UI"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openWebUiAndClose()
      }
    }
  }

  component FolderRow: CursorSurface {
    id: folderRow
    property var folder: null
    property int rowIndex: 0
    readonly property bool paused: folder && folder.paused === true
    readonly property bool busyFolder: Model.folderIsBusy(folder)
    readonly property bool problem: Model.folderHasProblem(folder)

    hasCursor: root.cursorActive && root.focusSection === "folders" && root.folderIndex === rowIndex
    foreground: root.foreground
    fill: root.hoverFill
    implicitHeight: Math.max(folderContent.implicitHeight, pauseButton.implicitHeight) + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setFolderCursor(folderRow.rowIndex)
      onClicked: if (syncthing) syncthing.openFolder(folderRow.folder)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: folderRow.paused ? "󰏤" : "󰉋"
        color: folderRow.problem ? root.urgent : (folderRow.paused ? root.dim : root.foreground)
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      ColumnLayout {
        id: folderContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: folderRow.folder ? String(folderRow.folder.label || folderRow.folder.id) : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: {
            var parts = [Model.folderStatusText(folderRow.folder)]
            if (folderRow.folder && folderRow.folder.path) parts.push(Model.prettyPath(folderRow.folder.path, Quickshell.env("HOME")))
            return parts.join(" · ")
          }
          color: folderRow.problem ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }

      PanelActionButton {
        iconText: "󰑐"
        tooltipText: "Rescan folder"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: syncthing && !syncthing.busy
        Layout.alignment: Qt.AlignVCenter
        onClicked: if (syncthing && folderRow.folder) syncthing.scan(folderRow.folder.id)

      }

      PanelActionButton {
        id: pauseButton
        iconText: folderRow.paused ? "󰐊" : "󰏤"
        tooltipText: folderRow.paused ? "Resume folder" : "Pause folder"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: syncthing && !syncthing.busy
        Layout.alignment: Qt.AlignVCenter
        onClicked: if (syncthing && folderRow.folder) syncthing.setFolderPaused(folderRow.folder.id, !folderRow.paused)

      }
    }
  }

  component DeviceRow: CursorSurface {
    id: deviceRow
    property var device: null
    property int rowIndex: 0
    readonly property bool connected: device && device.connected === true
    readonly property bool paused: device && device.paused === true

    hasCursor: root.cursorActive && root.focusSection === "devices" && root.deviceIndex === rowIndex
    foreground: root.foreground
    fill: root.hoverFill
    implicitHeight: deviceContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setDeviceCursor(deviceRow.rowIndex)
      onClicked: if (syncthing) syncthing.copyDeviceId(deviceRow.device)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: deviceRow.connected ? "󰩟" : (deviceRow.paused ? "󰏤" : "󰲛")
        color: deviceRow.connected ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      ColumnLayout {
        id: deviceContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: deviceRow.device ? String(deviceRow.device.name || deviceRow.device.id) : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: {
            if (deviceRow.paused) return "Paused"
            if (deviceRow.connected) return deviceRow.device.address ? "Connected · " + deviceRow.device.address : "Connected"
            return "Last seen " + Model.relativeTime(deviceRow.device ? deviceRow.device.lastSeen : "")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "󰆏"
        tooltipText: "Copy device ID"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: if (syncthing) syncthing.copyDeviceId(deviceRow.device)
      }
    }
  }

  component WebUiRow: CursorSurface {
    id: webRow
    hasCursor: root.cursorActive && root.focusSection === "webui"
    foreground: root.foreground
    fill: root.hoverFill
    implicitHeight: webContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.focusSection = "webui" }
      onClicked: root.openWebUiAndClose()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: "󰖟"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      ColumnLayout {
        id: webContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: "Open Syncthing Web UI"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: syncthing ? syncthing.guiUrl : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }
    }
  }
}
