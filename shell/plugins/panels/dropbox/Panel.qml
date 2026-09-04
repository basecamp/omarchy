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
  moduleName: "omarchy.dropbox"
  ipcTarget: "omarchy.dropbox"
  manageIpc: false

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string focusSection: "login"
  property int fileIndex: 0
  property int folderIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0

  readonly property bool showFolders: settings && settings.showSyncedFolders !== undefined
    ? settings.showSyncedFolders !== false
    : true
  // The ".." row is a cursor stop too, so folder navigation indexes over
  // [up?, ...folders]. `folderRowCount` is that combined length.
  readonly property bool hasUpRow: !dropbox.folderAtRoot && dropbox.folderParentPath !== ""
  readonly property int folderRowCount: (hasUpRow ? 1 : 0) + dropbox.folders.length
  readonly property bool foldersVisible: showFolders && dropbox.authenticated
  readonly property string browseCrumb: {
    var root_ = String(dropbox.accountPath || "")
    var here = String(dropbox.browsePath || "")
    if (root_ === "" || here === "" || here === root_) return "Dropbox"
    if (here.indexOf(root_ + "/") !== 0) return here
    return "Dropbox/" + here.substring(root_.length + 1)
  }

  readonly property var activePhrases: [
    "Filing files",
    "Distributing data",
    "Shuffling folders",
    "Boxing bytes",
    "Sorting stuff",
    "Syncing secrets",
    "Packing packets",
    "Moving memories",
    "Wrangling revisions",
    "Cataloging chaos"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: dropbox.authenticated && dropbox.active ? foreground : dim
  readonly property string toggleHint: dropbox.active ? "Pause syncing" : "Resume syncing"
  readonly property color barIconColor: dropbox.authenticated && dropbox.active ? barForeground : Qt.darker(barForeground, 1.55)
  // Only claim the header cursor when the switch is actually on screen —
  // "header" stays navigable, but an absent CLI leaves nothing to highlight.
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && dropbox.installed

  function ensureCursor() {
    if (!dropbox.authenticated) {
      focusSection = "login"
      fileIndex = 0
      folderIndex = 0
      return
    }
    if (folderRowCount === 0 && focusSection === "folders") focusSection = "header"
    if (dropbox.files.length === 0 && focusSection === "files") focusSection = "header"
    if (focusSection !== "files" && focusSection !== "folders" && focusSection !== "header") {
      focusSection = folderRowCount > 0 && foldersVisible ? "folders" : "header"
    }
    folderIndex = Math.max(0, Math.min(folderIndex, Math.max(0, folderRowCount - 1)))
    fileIndex = Math.max(0, Math.min(fileIndex, Math.max(0, dropbox.files.length - 1)))
  }

  // Vertical order through the panel: header -> folders -> files. Each helper
  // returns "" when its section has nothing to land on, so an empty section is
  // skipped rather than trapping the cursor.
  function sectionBelow(name) {
    if (name === "header") {
      if (foldersVisible && folderRowCount > 0) return "folders"
      if (dropbox.files.length > 0) return "files"
      return ""
    }
    if (name === "folders" && dropbox.files.length > 0) return "files"
    return ""
  }

  function sectionAbove(name) {
    if (name === "files") {
      if (foldersVisible && folderRowCount > 0) return "folders"
      return "header"
    }
    if (name === "folders") return "header"
    return ""
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) {
      // Left/right (and h/l) browse the folder tree, the way a file manager
      // does. PanelKeyCatcher swallows h/l as movement, so this is the only
      // place folder navigation can hang off those keys.
      if (dx !== 0 && focusSection === "folders") {
        if (dx < 0) goUpFolder()
        else if (!onUpRow()) {
          var folder = selectedFolder()
          if (folder && folder.browsable === true) {
            dropbox.enterFolder(folder)
            folderIndex = 0
          }
        }
      }
      return
    }
    if (focusSection === "header") {
      var below = sectionBelow("header")
      if (dy > 0 && below !== "") {
        focusSection = below
        folderIndex = 0
        fileIndex = 0
        scrollCursorIntoView()
      }
      return
    }
    if (focusSection === "folders") {
      if (dy < 0 && folderIndex === 0) {
        setHeaderCursor()
        return
      }
      if (dy > 0 && folderIndex === folderRowCount - 1) {
        var next = sectionBelow("folders")
        if (next !== "") {
          focusSection = next
          fileIndex = 0
          scrollCursorIntoView()
          return
        }
      }
      folderIndex = Math.max(0, Math.min(folderRowCount - 1, folderIndex + dy))
      scrollCursorIntoView()
      return
    }
    if (focusSection === "files") {
      if (dy < 0 && fileIndex === 0) {
        var previous = sectionAbove("files")
        if (previous === "folders") {
          focusSection = "folders"
          folderIndex = Math.max(0, folderRowCount - 1)
          scrollCursorIntoView()
        } else {
          setHeaderCursor()
        }
        return
      }
      fileIndex = Math.max(0, Math.min(dropbox.files.length - 1, fileIndex + dy))
      scrollCursorIntoView()
    }
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

  // Row 0 is the ".." row when it is present, so folder N sits at N + 1.
  function selectedFolder() {
    var index = hasUpRow ? folderIndex - 1 : folderIndex
    if (index < 0 || index >= dropbox.folders.length) return null
    return dropbox.folders[index]
  }

  function onUpRow() {
    return hasUpRow && folderIndex === 0
  }

  function toggleSelectedFolder() {
    if (focusSection !== "folders") return
    var folder = selectedFolder()
    if (folder && !dropbox.syncBusy) dropbox.toggleFolderSynced(folder)
  }

  function goUpFolder() {
    if (!hasUpRow) return
    dropbox.goUpFolder()
    folderIndex = 0
  }

  function toggleRunning() {
    if (dropbox.installed && !dropbox.busy) dropbox.toggleRunning()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "login") dropbox.login()
    else if (focusSection === "header") toggleRunning()
    else if (focusSection === "files") dropbox.openFile(selectedFile())
    else if (focusSection === "folders") {
      if (onUpRow()) goUpFolder()
      else {
        var folder = selectedFolder()
        // Enter only ever navigates. A folder with no subfolders is not
        // browsable, and rows give no hint of that, so falling back to a
        // toggle here would silently unsync — and delete the local copy of —
        // whatever the cursor happened to be on. `s` and the switch own
        // toggling.
        if (folder && folder.browsable === true) {
          dropbox.enterFolder(folder)
          folderIndex = 0
        }
      }
    }
  }

  function selectedFile() {
    if (dropbox.files.length === 0) return null
    return dropbox.files[Math.max(0, Math.min(fileIndex, dropbox.files.length - 1))]
  }

  function setFileCursor(index) {
    cursorActive = true
    focusSection = "files"
    fileIndex = index
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
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "files" && fileColumn && fileIndex >= 0 && fileIndex < fileColumn.children.length) {
      scrollItemIntoView(fileColumn.children[fileIndex])
    } else if (focusSection === "folders" && folderColumn && folderIndex >= 0 && folderIndex < folderColumn.children.length) {
      scrollItemIntoView(folderColumn.children[folderIndex])
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    // The panel item outlives a close, so the cursor has to be sent back to the
    // top explicitly. Without this it resumes wherever it was last left, which
    // silently skips whichever sections sit above that point.
    focusSection = dropbox.authenticated ? "header" : "login"
    folderIndex = 0
    fileIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    dropbox.refresh()
    // Reopen at the Dropbox root rather than wherever the last visit left off,
    // so the view always matches the cursor being reset to the top.
    if (showFolders) dropbox.resetBrowse()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onFileIndexChanged: scrollCursorIntoView()
  onFolderIndexChanged: scrollCursorIntoView()

  Service {
    id: dropbox
    settings: root.settings
    omarchyPath: root.omarchyPath
  }

  Connections {
    target: dropbox
    function onAuthenticatedChanged() { root.ensureCursor() }
    function onFilesChanged() { root.ensureCursor() }
    function onFoldersChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { dropbox.refresh(); return "ok" }
    function login(): string { dropbox.login(); return "ok" }
    function status(): string { return dropbox.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        DropboxIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          opacity: dropbox.active ? 1.0 : 0.6
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) dropbox.refresh()
      else if (buttonCode === Qt.MiddleButton) dropbox.login()
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
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") { dropbox.refresh(); if (root.showFolders) dropbox.loadFolders() }
        else if (t === "l" || t === "L") dropbox.login()
        else if (t === "p" || t === "P") root.toggleRunning()
        else if (t === "s" || t === "S") root.toggleSelectedFolder()
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
            visible: dropbox.authenticated
            width: parent.width
            implicitHeight: hero.implicitHeight
            // Exposed for the hero's trailingControl, whose `root` resolves to
            // PanelHero (not this Panel) — reach panel state via `header`.
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Dropbox"
              meta: dropbox.active ? root.heroPhraseText : "Syncing paused"
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: dropbox.active ? 1.0 : 0.5
              // Status only — the switch owns toggling, mouse and keyboard alike.
              iconComponent: Component {
                DropboxIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                }
              }

              // Compact on/off switch on the trailing edge of the hero, and the
              // header's only cursor target. The service already flips `active`
              // optimistically, so the knob throws the instant you click it.
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: dropbox.installed
                  checked: dropbox.active
                  busy: dropbox.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: root.toggleRunning()

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
            textFormat: Text.PlainText
            visible: dropbox.actionStatus !== "" || dropbox.lastError !== ""
            width: parent.width
            text: dropbox.actionStatus !== "" ? dropbox.actionStatus : dropbox.lastError
            color: dropbox.lastError !== "" && dropbox.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          LoginButton {
            visible: !dropbox.authenticated
            width: parent.width
          }

          Column {
            visible: dropbox.authenticated
            width: parent.width
            spacing: Style.spacing.labelGap

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap
              InfoPair { label: "Stored"; value: Model.usageText(dropbox.usedBytes, dropbox.quotaBytes, dropbox.quotaKnown) }
            }
          }

          PanelSeparator {
            visible: root.foldersVisible
            foreground: root.foreground
          }

          Column {
            id: folderSection
            visible: root.foldersVisible
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: foldersHeader.implicitHeight

              PanelSectionHeader {
                id: foldersHeader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "SYNCED FOLDERS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰑐"
                tooltipText: "Refresh folders"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !dropbox.foldersBusy
                onClicked: dropbox.loadFolders()
              }
            }

            // Where we are in the tree, shown only once you have drilled in.
            Text {
              visible: root.hasUpRow
              width: parent.width
              text: root.browseCrumb
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideLeft
            }

            Text {
              visible: dropbox.foldersError !== ""
              width: parent.width
              text: dropbox.foldersError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              visible: dropbox.foldersError === "" && dropbox.foldersLoaded && root.folderRowCount === 0
              width: parent.width
              text: "No folders here."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: folderColumn
              visible: root.folderRowCount > 0
              width: parent.width
              spacing: Style.space(6)

              // A Repeater rather than a `visible` binding so the row is truly
              // absent when at the root — `scrollCursorIntoView` indexes into
              // `folderColumn.children`, which must line up with `folderIndex`.
              Repeater {
                model: root.hasUpRow ? 1 : 0
                UpRow { width: folderColumn.width }
              }

              Repeater {
                model: dropbox.folders
                FolderRow {
                  required property var modelData
                  required property int index
                  width: folderColumn.width
                  folder: modelData
                  rowIndex: root.hasUpRow ? index + 1 : index
                }
              }
            }
          }

          PanelSeparator {
            visible: dropbox.authenticated
            foreground: root.foreground
          }

          Column {
            visible: dropbox.authenticated
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "RECENT FILES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: dropbox.files.length === 0
              width: parent.width
              text: "No synced files found."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: fileColumn
              visible: dropbox.files.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: dropbox.files
                FileRow {
                  required property var modelData
                  required property int index
                  width: fileColumn.width
                  file: modelData
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
    running: root.opened && dropbox.authenticated && dropbox.active
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

  component LoginButton: CursorSurface {
    id: loginButton

    hasCursor: root.cursorActive && root.focusSection === "login"
    foreground: root.foreground

    implicitHeight: loginRow.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: dropbox.installed && !dropbox.busy ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: dropbox.installed && !dropbox.busy
      onEntered: {
        root.cursorActive = true
        root.focusSection = "login"
      }
      onClicked: dropbox.login()
    }

    RowLayout {
      id: loginRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: dropbox.installed ? "Login to Dropbox" : "Dropbox CLI is not installed"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: dropbox.installed ? "Start the authentication flow" : "Install Dropbox from the service menu"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "󰌋"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: dropbox.installed && !dropbox.busy
        Layout.alignment: Qt.AlignVCenter
        onClicked: dropbox.login()
      }
    }
  }

  // Always cursor row 0 when present. Clicking anywhere walks one level up.
  component UpRow: CursorSurface {
    id: upRow

    hasCursor: root.cursorActive && root.focusSection === "folders" && root.folderIndex === 0
    foreground: root.foreground

    implicitHeight: upContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setFolderCursor(0)
      onClicked: root.goUpFolder()
    }

    RowLayout {
      id: upContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: "󰁍"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        Layout.fillWidth: true
        text: "Back"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }
  }

  // One folder in the current directory: name, sync state, and a switch that
  // drives `dropbox-cli exclude add/remove`. The row body drills in when the
  // folder is browsable; the switch always owns toggling, mouse and keyboard
  // alike, exactly as the hero's power switch does.
  component FolderRow: CursorSurface {
    id: folderRow
    property var folder: null
    property int rowIndex: 0

    readonly property string folderName: folder ? String(folder.name || "Untitled") : "Untitled"
    readonly property bool synced: dropbox.folderSynced(folder)
    readonly property bool pending: dropbox.folderPending(folder)
    readonly property bool browsable: folder ? folder.browsable === true : false
    readonly property bool rowSelected: root.cursorActive && root.focusSection === "folders" && root.folderIndex === rowIndex

    hasCursor: rowSelected
    foreground: root.foreground

    implicitHeight: folderContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: folderMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: folderRow.browsable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: root.setFolderCursor(folderRow.rowIndex)
      onClicked: if (folderRow.browsable) {
        dropbox.enterFolder(folderRow.folder)
        root.folderIndex = 0
      }
    }

    PanelToolTip {
      visible: folderMouse.containsMouse && folderRow.browsable
      text: "Open folder"
      fontFamily: root.fontFamily
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: folderRow.synced ? "󰉋" : "󰉖"
        color: folderRow.synced ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: folderContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: folderRow.folderName
          color: folderRow.synced ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: folderRow.pending
            ? (folderRow.synced ? "Syncing…" : "Removing…")
            : Model.folderMeta(folderRow.folder)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        visible: folderRow.browsable
        text: "󰅂"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }

      ToggleSwitch {
        id: folderSwitch
        Layout.alignment: Qt.AlignVCenter
        checked: folderRow.synced
        busy: dropbox.syncBusy
        // The surrounding row owns drill-in, so the switch keeps its own
        // cursor ring rather than borrowing the row's highlight.
        hasCursor: false
        foreground: root.foreground
        trackHeight: Math.max(18, Math.round(Style.spacing.controlHeight * 0.42))
        onHovered: function(on) { if (on) root.setFolderCursor(folderRow.rowIndex) }
        onToggled: dropbox.setFolderSynced(folderRow.folder, !folderRow.synced)

        PanelToolTip {
          visible: folderSwitch.containsMouse
          text: folderRow.synced ? "Stop syncing this folder" : "Sync this folder"
          fontFamily: root.fontFamily
        }
      }
    }
  }

  component FileRow: CursorSurface {
    id: fileRow
    property var file: null
    property int rowIndex: 0
    readonly property string fileName: file ? String(file.name || "Untitled") : "Untitled"

    hasCursor: root.cursorActive && root.focusSection === "files" && root.fileIndex === rowIndex
    foreground: root.foreground

    implicitHeight: fileContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setFileCursor(fileRow.rowIndex)
      onClicked: dropbox.openFile(fileRow.file)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: Model.fileGlyph(fileRow.fileName)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: fileContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: fileRow.fileName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: Model.fileMeta(fileRow.file)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
