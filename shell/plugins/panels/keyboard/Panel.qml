import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.keyboard"
  ipcTarget: "omarchy.keyboard"

  // Raw status from `omarchy-keyboard-layout status`:
  // { layouts: [{code, label}], switcher, active }
  property var status: ({ layouts: [], switcher: "alt_shift", active: "" })
  property var available: []

  readonly property var configuredLayouts: Model.toArray(status.layouts)
  readonly property var activeLayout: Model.activeLayout(status)
  readonly property string icon: activeLayout ? Model.languageCode(activeLayout.code) : "--"
  readonly property string heroStatusText: activeLayout ? activeLayout.label : "Unknown"
  readonly property var switcherPresets: Model.switcherPresets()

  // "list" = languages + switcher pills (default). "add" = search + all
  // available xkb layouts not already configured.
  property string viewMode: "list"
  property string searchText: ""
  readonly property var filteredAvailable: Model.filterAvailable(available, status, searchText)

  property string focusSection: "languages"
  property int selectedIndex: 0
  property bool cursorActive: false

  // Typing narrows filteredAvailable, which can leave selectedIndex pointing
  // past the end of the new (shorter) list, or leave the scroll position
  // stuck below the now-shorter list. Snap both back to the top on every
  // keystroke so the highlighted/visible row always matches what's on screen.
  onSearchTextChanged: {
    selectedIndex = 0
    if (availableFlick) availableFlick.contentY = 0
  }

  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property real heroRingPad: Style.space(6)

  function refresh() {
    if (statusProc.running) return
    statusProc.command = ["omarchy-keyboard-layout", "status"]
    statusProc.running = true
  }

  function refreshAvailable() {
    if (availableProc.running) return
    availableProc.command = ["omarchy-keyboard-layout", "available"]
    availableProc.running = true
  }

  function switchTo(code) {
    if (!code || actionProc.running) return
    actionProc.command = ["omarchy-keyboard-layout", "set", code]
    actionProc.running = true
  }

  function cycleNext() {
    if (actionProc.running) return
    actionProc.command = ["omarchy-keyboard-layout", "next"]
    actionProc.running = true
  }

  function addLanguage(code) {
    if (!code || actionProc.running) return
    actionProc.command = ["omarchy-keyboard-layout", "add", code]
    actionProc.running = true
    viewMode = "list"
    searchText = ""
    focusSection = "languages"
    selectedIndex = 0
  }

  function removeLanguage(code) {
    if (!code || configuredLayouts.length <= 1 || actionProc.running) return
    if (configuredLayouts[0] && configuredLayouts[0].code === code) return
    actionProc.command = ["omarchy-keyboard-layout", "remove", code]
    actionProc.running = true
  }

  function setSwitcher(id) {
    if (!id || actionProc.running) return
    actionProc.command = ["omarchy-keyboard-layout", "switcher", id]
    actionProc.running = true
  }

  function openAddView() {
    viewMode = "add"
    searchText = ""
    focusSection = "available"
    selectedIndex = 0
    refreshAvailable()
  }

  function closeAddView() {
    viewMode = "list"
    searchText = ""
    focusSection = "languages"
    selectedIndex = 0
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) refresh()
  Component.onCompleted: refresh()

  // Hyprland switches the layout itself for the native Alt+Shift/Ctrl+Shift/
  // etc. shortcut (see default/input.lua's kb_options grp:*_toggle) -- that
  // path never goes through our `omarchy-keyboard-layout` CLI, so it doesn't
  // update `root.status` on its own. Listen for Hyprland's own layout-change
  // event and refresh from it so the bar icon stays in sync even when the
  // switch happened outside the panel. A slow poll is kept as a fallback in
  // case an event is ever missed.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      if (String(event.name).indexOf("activelayout") !== -1) root.refresh()
    }
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.status = Model.parseStatus(text)
    }
  }

  Process {
    id: availableProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.available = Model.parseAvailable(text)
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.status = Model.parseStatus(text)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    onPressed: function(b) {
      if (b === Qt.RightButton) { root.cycleNext(); return }
      if (root.opened) root.close()
      else { root.open(); root.refresh() }
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.viewMode === "add") root.closeAddView()
        else root.close()
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(18)

        // ---------- Hero: current language ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight) + root.heroRingPad * 2

          Text {
            id: heroIcon
            anchors.left: parent.left
            anchors.leftMargin: root.heroRingPad
            anchors.verticalCenter: parent.verticalCenter
            text: "󰌌"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: cycleBtn.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Keyboard"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
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

          PanelActionButton {
            id: cycleBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.configuredLayouts.length > 1
            iconText: "󰑖"
            tooltipText: "Switch to next language"
            foreground: root.bar.foreground
            hoverColor: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.cycleNext()
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        // ---------- "list" view: configured languages + switcher ----------
        Column {
          width: parent.width
          spacing: Style.space(16)
          visible: root.viewMode === "list"

          Column {
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: Math.max(languagesHeader.implicitHeight, addBtn.implicitHeight)

              PanelSectionHeader {
                id: languagesHeader
                text: "LANGUAGES"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              PanelActionButton {
                id: addBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰐕"
                tooltipText: "Add language"
                foreground: root.bar.foreground
                hoverColor: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.openAddView()
              }
            }

            Repeater {
              model: root.configuredLayouts
              LanguageRow {
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                lang: modelData
                rowIndex: index
              }
            }
          }

          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader {
              text: "SWITCH SHORTCUT"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Row {
              id: switcherRow
              width: parent.width
              spacing: Style.space(6)

              readonly property int count: 4
              readonly property real cellWidth: (width - spacing * (count - 1)) / count

              Repeater {
                model: root.switcherPresets
                SwitcherPill {
                  required property var modelData
                  required property int index
                  preset: modelData.id
                  presetLabel: modelData.label
                  pillIndex: index
                  width: switcherRow.cellWidth
                }
              }
            }
          }
        }

        // ---------- "add" view: search + all available layouts ----------
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.viewMode === "add"

          Item {
            width: parent.width
            implicitHeight: Math.max(backBtn.implicitHeight, addHeader.implicitHeight)

            PanelActionButton {
              id: backBtn
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰅁"
              tooltipText: "Back"
              foreground: root.bar.foreground
              hoverColor: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.closeAddView()
            }

            PanelSectionHeader {
              id: addHeader
              text: "ADD LANGUAGE"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: backBtn.right
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          TextField {
            id: searchField
            width: parent.width
            placeholderText: "Search languages"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.controlPaddingY
            text: root.searchText
            onTextChanged: root.searchText = text
            onAccepted: if (root.filteredAvailable.length > 0) root.addLanguage(root.filteredAvailable[0].code)
            onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
            Component.onCompleted: if (visible) Qt.callLater(forceActiveFocus)
          }

          Flickable {
            id: availableFlick
            width: parent.width
            height: Math.min(contentHeight, Style.space(260))
            contentWidth: width
            contentHeight: availableList.implicitHeight
            clip: true

            Column {
              id: availableList
              width: availableFlick.width
              spacing: Style.space(2)

              Repeater {
                model: root.filteredAvailable
                AvailableRow {
                  required property var modelData
                  required property int index
                  width: parent ? parent.width : 0
                  lang: modelData
                  rowIndex: index
                }
              }

              Text {
                visible: root.filteredAvailable.length === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "No matches"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }
    }
  }

  // A configured language. Click switches to it; a remove (x) button
  // appears on hover when more than one language is configured, but never
  // on the primary layout (the one set up at install time) since it can't
  // be removed.
  component LanguageRow: CursorSurface {
    id: row
    required property var lang
    required property int rowIndex

    readonly property bool isActive: root.activeLayout && lang && root.activeLayout.code === lang.code
    // The primary layout is whichever one was configured first (typically
    // the system's install-time keyboard layout, not necessarily English) --
    // it's always layouts[0] since add() appends and remove() never touches
    // ordering. It can never be removed, so never show the (x) for it.
    readonly property bool isPrimary: lang && root.configuredLayouts.length > 0
      && root.configuredLayouts[0].code === lang.code
    readonly property bool removable: root.configuredLayouts.length > 1 && !row.isPrimary

    current: isActive
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    hasCursor: root.cursorActive && root.focusSection === "languages" && root.selectedIndex === rowIndex

    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "languages"
        root.selectedIndex = row.rowIndex
      }
      onClicked: if (!row.isActive) root.switchTo(row.lang.code)
    }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(label.implicitHeight, removeBtn.implicitHeight)

      Text {
        id: label
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: removeBtn.visible ? removeBtn.left : parent.right
        anchors.rightMargin: removeBtn.visible ? Style.space(8) : 0
        text: (row.lang ? row.lang.label : "") + (row.isActive ? "  ✓" : "")
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      PanelActionButton {
        id: removeBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: row.removable && (rowMouse.containsMouse || row.hasCursor)
        iconText: "󰅙"
        tooltipText: "Remove"
        foreground: root.bar.foreground
        hoverColor: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onClicked: root.removeLanguage(row.lang.code)
      }
    }
  }

  // One row in the "Add language" search results.
  component AvailableRow: CursorSurface {
    id: availRow
    required property var lang
    required property int rowIndex

    current: false
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    hasCursor: root.cursorActive && root.focusSection === "available" && root.selectedIndex === rowIndex
    implicitHeight: availLabel.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: availMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "available"
        root.selectedIndex = availRow.rowIndex
      }
      onClicked: root.addLanguage(availRow.lang.code)
    }

    Text {
      id: availLabel
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      text: availRow.lang ? availRow.lang.label : ""
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }

  // One of the four switch-shortcut presets, same pill styling as the
  // network panel's DNS provider picker.
  component SwitcherPill: Button {
    id: pill
    required property string preset
    required property string presetLabel
    required property int pillIndex

    text: presetLabel
    fontSize: Style.font.bodySmall
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
    bordered: true

    active: root.status.switcher === preset
    hasCursor: root.cursorActive && root.focusSection === "switcher" && root.selectedIndex === pillIndex

    onHovered: function(isHovered) {
      if (!isHovered) return
      root.cursorActive = true
      root.focusSection = "switcher"
      root.selectedIndex = pill.pillIndex
    }

    onClicked: root.setSwitcher(preset)
  }
}
