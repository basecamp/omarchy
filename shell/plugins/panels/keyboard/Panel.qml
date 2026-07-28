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
  // { layouts: [{code, label}], switcher, active, show_bar_icon }
  property var status: ({ layouts: [], switcher: "alt_shift", active: "", show_bar_icon: false })
  property var available: []

  readonly property var configuredLayouts: Model.toArray(status.layouts)
  readonly property var activeLayout: Model.activeLayout(status)
  // Always show the active layout's language code (e.g. "EN", "FA"), even
  // with only one language configured -- lets someone glance at the bar and
  // confirm which layout is active without opening the panel, and doubles
  // as a reminder of what layout will apply system-wide (see ensure_state
  // in the CLI: whatever was chosen at install time becomes this layout).
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

  // Re-reads status from the CLI. Skipped if a status request is already
  // in flight, so a fast poll never piles up overlapping processes.
  function refresh() {
    // Skip if a status request is already in flight, or if an action
    // (set/add/remove/switcher/next) is currently running -- every action
    // prints its own fresh status_json on completion, so a poll that lands
    // in between would just overwrite that fresher result with stale data.
    if (statusProc.running || actionProc.running) return
    statusProc.command = ["omarchy-keyboard-layout", "status"]
    statusProc.running = true
  }

  // Loads the full list of installable xkb layouts for the "Add language"
  // search view. Only called when that view opens, not on every refresh.
  function refreshAvailable() {
    if (availableProc.running) return
    availableProc.command = ["omarchy-keyboard-layout", "available"]
    availableProc.running = true
  }

  // Switches the active layout to an already-configured one.
  function switchTo(code) {
    if (!code || actionProc.running) return
    actionProc.command = ["omarchy-keyboard-layout", "set", code]
    actionProc.running = true
  }

  // Advances to the next configured layout, same action the right-click
  // shortcut and the in-panel cycle button both trigger.
  function cycleNext() {
    if (actionProc.running) return
    actionProc.command = ["omarchy-keyboard-layout", "next"]
    actionProc.running = true
  }

  // Adds a new layout and returns to the main list view, ready to show it.
  function addLanguage(code) {
    if (!code || actionProc.running) return
    actionProc.command = ["omarchy-keyboard-layout", "add", code]
    actionProc.running = true
    viewMode = "list"
    searchText = ""
    focusSection = "languages"
    selectedIndex = 0
  }

  // Removes a configured layout. Guarded on both sides (here and in the
  // CLI) so the last remaining layout, and the primary layout, can never
  // be removed -- there must always be at least one layout to fall back to.
  function removeLanguage(code) {
    if (!code || configuredLayouts.length <= 1 || actionProc.running) return
    if (configuredLayouts[0] && configuredLayouts[0].code === code) return
    actionProc.command = ["omarchy-keyboard-layout", "remove", code]
    actionProc.running = true
  }

  // Changes which shortcut preset Hyprland uses to cycle layouts.
  function setSwitcher(id) {
    if (!id || actionProc.running) return
    actionProc.command = ["omarchy-keyboard-layout", "switcher", id]
    actionProc.running = true
  }

  // Switches to the "Add language" view and loads the full available list
  // fresh, so it always reflects the current set of already-configured
  // layouts rather than a stale snapshot from last time it was open.
  // Moves the highlighted row in the "Add language" search results by dy
  // (+1/-1), wrapping around at either end and scrolling it into view.
  // Called both from keyCatcher (when the search field doesn't have focus)
  // and directly from the search field's own Up/Down handlers below --
  // PanelKeyCatcher is deliberately blocked while the search field has
  // focus (so typing doesn't fight with panel navigation), which would
  // otherwise leave Up/Down completely dead while actively searching.
  // Moving the keyboard cursor changes a row's appearance (hover highlight,
  // the remove button popping in), which shifts that row's layout under a
  // mouse pointer that never actually moved. Qt Quick re-hit-tests on that
  // shift and can fire onContainsMouseChanged for a row the mouse never
  // touched, silently overwriting the keyboard selection right after it
  // moved -- looks like the selection "jumping" or "getting lost" while
  // navigating with arrow keys. Suppress hover-driven selection for a short
  // window after every keyboard move so the layout has time to settle
  // before hover is trusted again; a real mouse move afterwards still
  // takes over normally once the window passes.
  property real hoverSuppressedUntil: 0
  function suppressHoverBriefly() { hoverSuppressedUntil = Date.now() + 200 }
  function hoverAllowed() { return Date.now() >= hoverSuppressedUntil }

  function moveAvailableSelection(dy) {
    root.suppressHoverBriefly()
    root.cursorActive = true
    var maxAvail = Math.max(0, root.filteredAvailable.length - 1)
    var next = root.selectedIndex + dy
    if (next < 0) next = maxAvail
    else if (next > maxAvail) next = 0
    root.selectedIndex = next
    root.ensureAvailableVisible(next)
  }

  function ensureAvailableVisible(index) {
    var item = availableRepeater.itemAt(index)
    if (!item || !availableFlick) return
    var top = item.y
    var bottom = item.y + item.height
    if (top < availableFlick.contentY) {
      availableFlick.contentY = top
    } else if (bottom > availableFlick.contentY + availableFlick.height) {
      availableFlick.contentY = bottom - availableFlick.height
    }
  }

  // Keeps focusSection/selectedIndex pointing at a row that actually still
  // exists. Without this, adding/removing a language, a background status
  // refresh (poll timer, Hyprland event, or any action completing) can
  // change the length of configuredLayouts/switcherPresets/filteredAvailable
  // out from under an already-set selectedIndex -- leaving the keyboard
  // cursor stuck on a row that no longer exists (or vanished entirely),
  // which is what makes arrow-key navigation feel like it "loses" the
  // selection. Mirrors MonitorPanel's clampCursor().
  function clampCursor() {
    if (root.viewMode === "list") {
      if (root.focusSection === "switcher") {
        var maxSw = Math.max(0, root.switcherPresets.length - 1)
        if (root.selectedIndex < 0) root.selectedIndex = 0
        else if (root.selectedIndex > maxSw) root.selectedIndex = maxSw
        return
      }
      // "languages" (default) -- also the fallback for any unknown section.
      if (root.configuredLayouts.length === 0) {
        // Shouldn't normally happen (there's always at least one layout),
        // but land somewhere sane rather than pointing at nothing.
        root.focusSection = root.switcherPresets.length > 0 ? "switcher" : "languages"
        root.selectedIndex = 0
        return
      }
      if (root.focusSection !== "languages") root.focusSection = "languages"
      var maxLang = root.configuredLayouts.length - 1
      if (root.selectedIndex < 0) root.selectedIndex = 0
      else if (root.selectedIndex > maxLang) root.selectedIndex = maxLang
    } else if (root.viewMode === "add") {
      if (root.focusSection !== "available") root.focusSection = "available"
      var maxAvail = Math.max(0, root.filteredAvailable.length - 1)
      if (root.selectedIndex < 0) root.selectedIndex = 0
      else if (root.selectedIndex > maxAvail) root.selectedIndex = maxAvail
    }
  }

  function openAddView() {
    viewMode = "add"
    searchText = ""
    focusSection = "available"
    selectedIndex = 0
    refreshAvailable()
  }

  // Returns to the main list view, resetting search state so it starts
  // clean the next time "Add language" is opened.
  function closeAddView() {
    viewMode = "list"
    searchText = ""
    focusSection = "languages"
    selectedIndex = 0
    // The search field held keyboard focus while typing; nothing moves it
    // back automatically just because it's now hidden, so without this,
    // keys like Esc silently go nowhere until something else grabs focus.
    keyCatcher.forceActiveFocus()
  }

  // Manual on/off switch for the bar icon, controlled from omarchy-menu
  // (Trigger > Toggle > Show Keyboard Layout) via `omarchy-keyboard-layout
  // bar-icon toggle`. Independent of the language-code icon above -- this
  // is a deliberate user choice, not an automatic language-count heuristic.
  readonly property bool barIconVisible: status.show_bar_icon !== false

  visible: barIconVisible
  implicitWidth: barIconVisible ? button.implicitWidth : 0
  implicitHeight: barIconVisible ? button.implicitHeight : 0

  onBarIconVisibleChanged: if (!barIconVisible && opened) close()

  // Mirrors MonitorPanel: always land on a known-good, top-of-list cursor
  // position when the panel is (re)opened, rather than trusting whatever
  // focusSection/selectedIndex was left over from before it was closed.
  onOpenedChanged: {
    if (opened) {
      refresh()
      viewMode = "list"
      focusSection = "languages"
      selectedIndex = 0
      cursorActive = false
    }
  }
  Component.onCompleted: refresh()

  onConfiguredLayoutsChanged: clampCursor()
  onSwitcherPresetsChanged: clampCursor()
  onFilteredAvailableChanged: clampCursor()

  // Hyprland switches the layout itself for the native Alt+Shift/Ctrl+Shift/
  // etc. shortcut (see config/hypr/input.lua's kb_options grp:*_toggle) -- that
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
    interval: 3000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // Runs `status` and updates root.status once it finishes.
  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // A crash, permissions error, or unexpected output from the CLI
        // shouldn't throw an uncaught exception out of a binding handler --
        // that can silently break other bindings downstream. Keep the last
        // good status instead of replacing it with garbage.
        try {
          root.status = Model.parseStatus(text)
        } catch (e) {
          console.warn("omarchy.keyboard: failed to parse status output:", e)
        }
      }
    }
  }
  Timer {
    // Watchdog: if the CLI ever hangs, statusProc.running would otherwise
    // stay true forever and permanently block every future refresh().
    interval: 8000
    running: statusProc.running
    onTriggered: if (statusProc.running) {
      console.warn("omarchy.keyboard: status query timed out, resetting")
      statusProc.running = false
    }
  }

  // Runs `available` and updates root.available once it finishes.
  Process {
    id: availableProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.available = Model.parseAvailable(text)
        } catch (e) {
          console.warn("omarchy.keyboard: failed to parse available output:", e)
        }
      }
    }
  }
  Timer {
    interval: 8000
    running: availableProc.running
    onTriggered: if (availableProc.running) {
      console.warn("omarchy.keyboard: available query timed out, resetting")
      availableProc.running = false
    }
  }

  // Runs any state-changing action (set/add/remove/switcher/next). Every
  // one of these commands prints a fresh status_json on completion, so
  // root.status can be updated the same way regardless of which action ran.
  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.status = Model.parseStatus(text)
        } catch (e) {
          console.warn("omarchy.keyboard: failed to parse action output:", e)
        }
      }
    }
  }
  Timer {
    interval: 8000
    running: actionProc.running
    onTriggered: if (actionProc.running) {
      console.warn("omarchy.keyboard: action timed out, resetting")
      actionProc.running = false
      // Fall back to a plain status query so the UI still ends up
      // reflecting reality even though we don't know if the action itself
      // actually took effect before it hung.
      root.refresh()
    }
  }

  // The clickable bar icon itself: left-click opens/closes the panel,
  // right-click cycles straight to the next layout without opening it.
  WidgetButton {
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

  // The popover itself: a hero row showing the active layout, then either
  // the configured-languages list or the "add language" search view.
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
      blocked: root.viewMode === "add" && searchField.activeFocus

      onMoveRequested: function(dx, dy) {
        root.suppressHoverBriefly()
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (root.viewMode === "list") {
          if (root.focusSection === "languages") {
            var maxLang = Math.max(0, root.configuredLayouts.length - 1)
            if (dy > 0 && root.selectedIndex >= maxLang) { root.focusSection = "switcher"; root.selectedIndex = 0; return }
            root.selectedIndex = Math.max(0, Math.min(maxLang, root.selectedIndex + dy))
          } else if (root.focusSection === "switcher") {
            var maxSw = Math.max(0, root.switcherPresets.length - 1)
            // Up always leaves the switcher row for the languages list above,
            // regardless of which pill (selectedIndex) is currently highlighted --
            // vertical movement is orthogonal to the pills' horizontal layout, so
            // it shouldn't require first navigating back to pillIndex 0 with
            // Left/Right before Up does anything.
            if (dy < 0) { root.focusSection = "languages"; root.selectedIndex = Math.max(0, root.configuredLayouts.length - 1); return }
            root.selectedIndex = Math.max(0, Math.min(maxSw, root.selectedIndex + dx))
          }
          return
        }
        root.moveAvailableSelection(dy)
      }

      onActivateRequested: function() {
        if (!root.cursorActive) return
        if (root.viewMode === "list" && root.focusSection === "languages") {
          var l = root.configuredLayouts[root.selectedIndex]
          if (l && l.code) root.switchTo(l.code)
        } else if (root.viewMode === "list" && root.focusSection === "switcher") {
          var p = root.switcherPresets[root.selectedIndex]
          if (p && p.id) root.setSwitcher(p.id)
        } else if (root.viewMode === "add") {
          var a = root.filteredAvailable[root.selectedIndex]
          if (a && a.code) root.addLanguage(a.code)
        }
      }

      onTabRequested: function(direction) { root.switchPanel(direction) }

      onCloseRequested: {
        if (root.viewMode === "add") root.closeAddView()
        else root.close()
      }
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

            readonly property int count: 3
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
          // Explicit binding (rather than relying on the default of true)
          // so this item's own `visible` actually flips with the view --
          // onVisibleChanged/Component.onCompleted below key off of it to
          // (re)grab keyboard focus, and an ancestor's visible=false does
          // NOT change a child's own visible property value, only its
          // effective on-screen rendering. Without this binding those
          // handlers only ever saw `visible === true`, so they fired once
          // on initial creation (while still in "list" view) and never
          // again -- meaning the field could end up never receiving focus
          // when "Add language" was actually opened.
          visible: root.viewMode === "add"
          placeholderText: "Search languages"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlGap
          verticalPadding: Style.spacing.controlPaddingY
          text: root.searchText
          onTextChanged: root.searchText = text
          onAccepted: {
            if (root.filteredAvailable.length === 0) return
            // Use whatever row is currently highlighted by the keyboard
            // cursor (kept in sync by moveAvailableSelection as Up/Down are
            // pressed), falling back to the first result only if no
            // selection has been made yet (e.g. Enter pressed immediately
            // after typing, before any arrow-key navigation).
            var idx = root.cursorActive
              ? Math.max(0, Math.min(root.selectedIndex, root.filteredAvailable.length - 1))
              : 0
            root.addLanguage(root.filteredAvailable[idx].code)
          }
          onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
          Component.onCompleted: if (visible) Qt.callLater(forceActiveFocus)
          Keys.onUpPressed: function(event) { root.moveAvailableSelection(-1); event.accepted = true }
          Keys.onDownPressed: function(event) { root.moveAvailableSelection(1); event.accepted = true }
          Keys.onEscapePressed: function(event) { root.closeAddView(); event.accepted = true }
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
              id: availableRepeater
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
    // the system's install-time keyboard layout) -- it's always layouts[0]
    // since add() appends and remove() never touches ordering. It can
    // never be removed, so never show the (x) for it.
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
      onContainsMouseChanged: if (containsMouse && root.hoverAllowed()) {
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
      onContainsMouseChanged: if (containsMouse && root.hoverAllowed()) {
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

  // One of the three switch-shortcut presets, same pill styling as the
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
      if (!isHovered || !root.hoverAllowed()) return
      root.cursorActive = true
      root.focusSection = "switcher"
      root.selectedIndex = pill.pillIndex
    }

    onClicked: root.setSwitcher(preset)
  }
}
