import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The expanded view: everything the under-bar panel shows, plus the full
// process table with filtering, sorting, and signals. Summoned from the panel's
// Expand button, from `omarchy-shell shell toggle omarchy.omatask`, or
// from a Hyprland binding.
Item {
  id: root

  // Dimming has to know what it is dimming *against*. dim() only reads as
  // "less prominent" on a dark ground; on a light theme it makes secondary text
  // darker — and therefore louder — than the primary text it sits behind. This
  // moves toward the background either way.
  readonly property bool groundIsDark: Model.groundIsDark(root.background)
  function dim(c, amount) { return Model.dim(root.background, c, amount) }

  // Injected by the shell's panel loader.
  property var shell: null
  property var service: null
  property var manifest: ({})
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property bool opened: false
  property string filterText: ""
  property int selectedPid: -1
  // Applications have no pid to key selection on, so they key on their scope.
  property string selectedUnit: ""
  // "processes" is the flat table; "apps" groups by systemd scope so one
  // Chromium replaces forty-seven chromium rows; "tree" keeps the flat data but
  // draws parent/child structure.
  readonly property string listMode: service ? service.listMode : "processes"
  readonly property bool appsMode: listMode === "apps"
  readonly property bool treeMode: listMode === "tree"
  // Whether rows carry a thread-disclosure chevron. An application row has no
  // threads to disclose, so the column disappears — and the table header has to
  // agree, which is why this is one property both of them read.
  readonly property bool rowsExpandable: !appsMode

  function cycleListMode(direction) {
    if (!service) return
    var modes = ["processes", "apps", "tree"]
    var at = modes.indexOf(listMode)
    service.listMode = modes[(at + (direction || 1) + modes.length) % modes.length]
  }

  // Reconcile every sampler gate with what is currently on screen. Called on
  // open as well as on change: a preference restored from shell.json means the
  // mode is already correct when the overlay is built, so a change handler
  // alone never fires and the view opens empty.
  function syncDetailGates() {
    if (!service) return
    service.appsDetail = appsMode && opened
    service.gpuDetail = gpuExpanded && opened
    service.netDetail = netExpanded && opened
    service.diskDetail = diskExpanded && opened
    service.sensorDetail = (cpuExpanded || memExpanded || diskExpanded) && opened
  }

  onAppsModeChanged: syncDetailGates()

  readonly property string sortId: service ? service.sortBy : "cpu"
  readonly property bool sortDescending: service ? service.sortDescending : true
  // The CPU card swaps between one aggregate graph and a per-core grid; the
  // grid needs the whole row, so the other cards stand down while it is up.
  // Only one card can hold the row at a time, so these are kept exclusive
  // rather than letting two full-width cards fight over it.
  property bool cpuExpanded: false
  property bool gpuExpanded: false
  property bool memExpanded: false
  property bool netExpanded: false
  property bool diskExpanded: false
  property int expandedPid: -1
  // The full key list is a reference, not a status bar. It lives behind `?`
  // so the persistent chrome can stay down to the one thing worth saying.
  property bool keysVisible: false

  readonly property var keyHelp: [
    { keys: "type", action: "Filter by name, command, user, or pid" },
    { keys: "↑ ↓", action: "Select a process" },
    { keys: "PgUp PgDn · Home End", action: "Jump through the list" },
    { keys: "Enter · →", action: "Expand the process into its threads" },
    { keys: "←", action: "Collapse the expanded process" },
    { keys: "Del", action: "Terminate (SIGTERM)" },
    { keys: "Shift+Del", action: "Kill (SIGKILL)" },
    { keys: "Tab · Shift+Tab", action: "Cycle the sort column" },
    { keys: "Ctrl+R", action: "Reverse the sort direction" },
    { keys: "Ctrl+L", action: "Toggle the per-core view" },
    { keys: "Ctrl+G", action: "Toggle the GPU engine view" },
    { keys: "Ctrl+M", action: "Toggle the memory breakdown" },
    { keys: "Ctrl+N", action: "Toggle the network breakdown" },
    { keys: "Ctrl+D", action: "Toggle the disk breakdown" },
    { keys: "Ctrl+A", action: "Cycle processes / applications / tree" },
    { keys: "g", action: "Group an app's scopes into one row (Applications view)" },
    { keys: "Ctrl+O", action: "Show the selected process's open files" },
    { keys: "s", action: "Suspend the selected process (SIGSTOP)" },
    { keys: "c", action: "Resume the selected process (SIGCONT)" },
    { keys: "[ / ]", action: "Lower / raise priority of the selected process" },
    { keys: "Ctrl+↑ Ctrl+↓", action: "Scroll the expanded card" },
    { keys: "Backspace · Ctrl+U", action: "Edit or clear the filter" },
    { keys: "Esc", action: "Clear the filter, then close" }
  ]

  // Live ScrollColumns, so Ctrl+arrow can drive whichever ones are on screen.
  property var scrollables: []

  function registerScrollable(item) {
    var next = scrollables.slice()
    next.push(item)
    scrollables = next
  }

  function unregisterScrollable(item) {
    var next = []
    for (var i = 0; i < scrollables.length; i++) {
      if (scrollables[i] !== item) next.push(scrollables[i])
    }
    scrollables = next
  }

  function scrollExpanded(delta) {
    var moved = false
    for (var i = 0; i < scrollables.length; i++) {
      var target = scrollables[i]
      if (target && target.visible && target.overflowing) {
        target.scrollBy(delta)
        moved = true
      }
    }
    return moved
  }

  readonly property bool anyCardExpanded: cpuExpanded || gpuExpanded || memExpanded || netExpanded || diskExpanded

  function toggleCpuExpanded() {
    diskExpanded = false
    netExpanded = false
    gpuExpanded = false
    memExpanded = false
    cpuExpanded = !cpuExpanded
  }

  function toggleGpuExpanded() {
    diskExpanded = false
    netExpanded = false
    if (!service || !service.hasGpu) return
    cpuExpanded = false
    memExpanded = false
    gpuExpanded = !gpuExpanded
  }

  function toggleDiskExpanded() {
    cpuExpanded = false
    gpuExpanded = false
    memExpanded = false
    netExpanded = false
    diskExpanded = !diskExpanded
  }

  function toggleNetExpanded() {
    diskExpanded = false
    cpuExpanded = false
    gpuExpanded = false
    memExpanded = false
    netExpanded = !netExpanded
  }

  function toggleMemExpanded() {
    diskExpanded = false
    netExpanded = false
    cpuExpanded = false
    gpuExpanded = false
    memExpanded = !memExpanded
  }

  // The expensive GPU readings are collected only while the card showing them
  // is open — and never once the overlay itself is gone.
  onGpuExpandedChanged: if (service) service.gpuDetail = gpuExpanded && opened
  // Both expansions show hwmon readings — CPU the full strip, memory the DIMM
  // sensors — so either one opens the expensive sensor gate.
  function syncSensorDetail() {
    if (service) service.sensorDetail = (cpuExpanded || memExpanded || diskExpanded) && opened
  }
  onCpuExpandedChanged: syncSensorDetail()
  onMemExpandedChanged: syncSensorDetail()
  onNetExpandedChanged: if (service) service.netDetail = netExpanded && opened
  onDiskExpandedChanged: {
    if (!service) return
    service.diskDetail = diskExpanded && opened
    // Drive temperatures come from the same hwmon tier as the DIMM sensors.
    syncSensorDetail()
  }
  onOpenedChanged: {
    if (service && !opened) {
      service.gpuDetail = false
      service.sensorDetail = false
    }
  }

  // True only for processes worth expanding. Keeping the keyboard and the
  // chevron on the same rule means Enter never opens a disclosure the row
  // showed no arrow for.
  function hasThreads(pid) {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].pid === pid) return Number(rows[i].threads) > 1
    }
    return false
  }

  function toggleThreads(pid) {
    var target = Number(pid) || -1
    if (expandedPid === target) {
      expandedPid = -1
      if (service) service.unwatchThreads(target)
      return
    }
    if (!hasThreads(target)) return
    expandedPid = target
    if (service) service.watchThreads(target)
  }

  // Shares the [menu] surface tokens, so a theme that restyles the menu
  // restyles this too rather than needing its own entry.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.menuFamily

  readonly property var rows: {
    if (!service) return []
    if (appsMode) {
      return Model.sortApps(Model.filterApps(service.apps, filterText), sortId, sortDescending)
    }
    var flat = Model.sortProcesses(
      Model.filterProcesses(service.processes, filterText), sortId, sortDescending)
    // The tree only makes sense over the whole set; once a filter has cut it
    // down, the surviving rows have no shared ancestry to draw.
    return treeMode && filterText === "" ? Model.buildTree(flat) : flat
  }
  readonly property int selectedIndex: {
    for (var i = 0; i < rows.length; i++) {
      if (appsMode ? rows[i].unit === selectedUnit : rows[i].pid === selectedPid) return i
    }
    return -1
  }

  function open(payloadJson) {
    if (opened) return
    opened = true
    filterText = ""
    selectedPid = -1
    if (service) {
      service.retainProcesses()
      service.retainGpu()
    }
    syncDetailGates()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (!opened) return
    opened = false
    gpuExpanded = false
    cpuExpanded = false
    memExpanded = false
    netExpanded = false
    diskExpanded = false
    if (expandedPid > 0 && service) service.unwatchThreads(expandedPid)
    expandedPid = -1
    if (service) {
      service.gpuDetail = false
      service.sensorDetail = false
      service.netDetail = false
      service.diskDetail = false
      service.appsDetail = false
      service.socketDetail = false
      service.openFilesPid = 0
      service.releaseProcesses()
      service.releaseGpu()
    }
  }

  function toggle() {
    if (opened) close()
    else open("{}")
  }

  Component.onDestruction: {
    if (!opened || !service) return
    if (expandedPid > 0) service.unwatchThreads(expandedPid)
    service.gpuDetail = false
    service.sensorDetail = false
    service.netDetail = false
    service.diskDetail = false
    service.appsDetail = false
    service.socketDetail = false
    service.openFilesPid = 0
    service.releaseProcesses()
    service.releaseGpu()
  }

  // Selection follows the pid, not the row number: the table re-sorts on every
  // sample, and an index-based cursor would slide onto whatever process
  // happened to overtake the one you were aiming at.
  function select(delta) {
    if (rows.length === 0) return
    var next = selectedIndex < 0
      ? (delta > 0 ? 0 : rows.length - 1)
      : Math.max(0, Math.min(rows.length - 1, selectedIndex + delta))
    if (appsMode) selectedUnit = rows[next].unit
    else selectedPid = rows[next].pid
    list.positionViewAtIndex(next, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (rows.length === 0) return
    var clamped = Math.max(0, Math.min(rows.length - 1, index))
    if (appsMode) selectedUnit = rows[clamped].unit
    else selectedPid = rows[clamped].pid
    list.positionViewAtIndex(clamped, ListView.Contain)
  }

  property bool filesVisible: false

  function toggleOpenFiles() {
    if (appsMode || selectedPid <= 0) return
    filesVisible = !filesVisible
    if (service) service.openFilesPid = filesVisible ? selectedPid : 0
  }

  onSelectedPidChanged: {
    if (filesVisible && service) service.openFilesPid = selectedPid
    // A priority nudge applies to whatever is selected, so the accumulated
    // offset resets when the selection moves.
    pendingNice = 0
  }

  // Priority moves in preset-sized steps rather than one nice unit at a time,
  // so a keypress produces a change a person can feel.
  property int pendingNice: 0

  function nudgePriority(delta) {
    if (!service || selectedPid <= 0) return
    pendingNice = Math.max(-19, Math.min(19, pendingNice + delta))
    service.setPriority(selectedPid, pendingNice)
  }

  function killSelected(signalName) {
    if (!service || selectedIndex < 0) return
    service.killProcess(rows[selectedIndex].pid, signalName)
  }

  function applySort(id) {
    if (!service) return
    // Clicking the column you are already sorted by flips direction; picking a
    // new one starts descending, because "most first" is always the question.
    if (sortId === id) service.sortDescending = !sortDescending
    else {
      service.sortBy = id
      service.sortDescending = true
    }
  }

  // A real toplevel window, not a layer-shell surface. Layer-shell is what made
  // this hover above the desktop without being part of it: it could not be
  // dragged, windows dragged around it passed underneath, and SUPER+W closed
  // whatever was behind it because the compositor resolves keybindings before a
  // layer surface ever sees them. As a window it drags, stacks, tiles and
  // closes like everything else the window manager owns.
  FloatingWindow {
    id: window
    visible: root.opened
    // The window manager shows this in alt-tab and matches window rules against
    // it, so it is the public name rather than the internal one.
    title: "Task Manager"
    color: "transparent"
    implicitWidth: Style.space(1180)
    implicitHeight: Style.space(820)
    // Below this the stat cards stop being readable and the table loses its
    // right-hand columns, so refuse rather than degrade.
    minimumSize: Qt.size(Style.space(720), Style.space(420))

    // The compositor's close — a window rule, SUPER+W, a close button — arrives
    // here. Without this the shell would keep thinking the view is open.
    onClosed: root.close()

    BorderSurface {
      id: card
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      Item {
        id: keyCatcher
        // BorderSurface exposes padding as insets rather than applying them,
        // so content has to honour them explicitly.
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        focus: true
        // Nothing inside should ever paint over the card border; a layout slip
        // in an unclipped layer-shell surface bleeds onto the desktop itself.
        clip: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          // The legend swallows everything while it is up, so no shortcut can
          // act on a list the user cannot currently see.
          if (root.keysVisible) {
            if (event.key === Qt.Key_Escape || event.text === "?") root.keysVisible = false
            event.accepted = true
            return
          }
          // `?` is a printable character, so it only opens the legend when
          // there is no filter to append it to.
          if (event.text === "?" && root.filterText === "") {
            root.keysVisible = true
            event.accepted = true
            return
          }

          if (event.key === Qt.Key_Escape) {
            if (root.filterText !== "") root.filterText = ""
            else root.close()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.filterText = Util.editedFilter(event, root.filterText)
            event.accepted = true
          } else if (root.anyCardExpanded && (event.modifiers & Qt.ControlModifier)
                     && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
            // Scrolls whatever the expanded card is showing: the per-core
            // grid, the VRAM list, or any detail column that overflowed. Each
            // call is a no-op when its target already fits.
            var step = event.key === Qt.Key_Down ? Style.space(58) : -Style.space(58)
            if (root.cpuExpanded) coreGraphs.scrollBy(step)
            if (root.gpuExpanded) vramList.scrollBy(step)
            root.scrollExpanded(step)
            event.accepted = true
          } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
            if (root.service) root.service.sortDescending = !root.sortDescending
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1); event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1); event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-12); event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(12); event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0); event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(root.rows.length - 1); event.accepted = true
          } else if (event.text === "g" && root.filterText === "" && root.appsMode) {
            if (root.service) root.service.groupApps = !root.service.groupApps
            event.accepted = true
          } else if (event.text === "s" && root.filterText === "" && root.selectedPid > 0) {
            // Suspending is the humane alternative to killing something you
            // actually want back.
            if (root.service) root.service.killProcess(root.selectedPid, "STOP")
            event.accepted = true
          } else if (event.text === "c" && root.filterText === "" && root.selectedPid > 0) {
            if (root.service) root.service.killProcess(root.selectedPid, "CONT")
            event.accepted = true
          } else if ((event.text === "[" || event.text === "]") && root.selectedPid > 0) {
            root.nudgePriority(event.text === "]" ? 5 : -5)
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            root.killSelected(event.modifiers & Qt.ShiftModifier ? "KILL" : "TERM")
            event.accepted = true
          } else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
            // Ctrl+L for "logical processors", the same view the CPU card
            // toggles on click. Ctrl-modified keys never reach the filter.
            root.toggleCpuExpanded()
            event.accepted = true
          } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ControlModifier)) {
            root.toggleGpuExpanded()
            event.accepted = true
          } else if (event.key === Qt.Key_M && (event.modifiers & Qt.ControlModifier)) {
            root.toggleMemExpanded()
            event.accepted = true
          } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
            root.toggleNetExpanded()
            event.accepted = true
          } else if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
            root.toggleDiskExpanded()
            event.accepted = true
          } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            root.cycleListMode((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            event.accepted = true
          } else if (event.key === Qt.Key_O && (event.modifiers & Qt.ControlModifier)) {
            root.toggleOpenFiles()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.selectedPid > 0) root.toggleThreads(root.selectedPid)
            event.accepted = true
          } else if (event.key === Qt.Key_Right && root.selectedPid > 0 && root.expandedPid !== root.selectedPid) {
            root.toggleThreads(root.selectedPid)
            event.accepted = true
          } else if (event.key === Qt.Key_Left && root.expandedPid > 0) {
            root.toggleThreads(root.expandedPid)
            event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            // Tab walks the sort columns rather than moving focus; there is
            // only one focusable surface here.
            var order = Model.SORTS
            var at = 0
            for (var i = 0; i < order.length; i++) {
              if (order[i].id === root.sortId) at = i
            }
            var step = (event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1
            if (root.service) {
              root.service.sortBy = order[(at + step + order.length) % order.length].id
              root.service.sortDescending = true
            }
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text >= " "
                     && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            root.filterText += event.text
            event.accepted = true
          }
        }

        // ------------------------------------------------------ key legend
        //
        // Sits above the content rather than inside the layout, so opening it
        // never reflows the table behind it.
        BorderSurface {
          id: legend
          visible: root.keysVisible
          z: 30
          anchors.centerIn: parent
          width: Math.min(Style.space(520), parent.width - Style.space(40))
          height: Math.min(legendColumn.implicitHeight + Style.space(36), parent.height - Style.space(20))
          radius: Style.cornerRadius
          color: Color.menu.background
          borderSpec: root.borderSpec

          MouseArea {
            anchors.fill: parent
            onClicked: root.keysVisible = false
          }

          Column {
            id: legendColumn
            anchors.centerIn: parent
            width: parent.width - Style.space(36)
            spacing: Style.space(6)

            Text {
              text: "KEYS"
              bottomPadding: Style.space(4)
              color: dim(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }

            Repeater {
              model: root.keyHelp

              Item {
                required property var modelData
                width: legendColumn.width
                height: Style.space(19)

                Text {
                  anchors.left: parent.left
                  width: Style.space(160)
                  text: modelData.keys
                  elide: Text.ElideRight
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(168)
                  anchors.right: parent.right
                  text: modelData.action
                  elide: Text.ElideRight
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Text {
              topPadding: Style.space(6)
              text: "? or Esc to close"
              color: dim(root.foreground, 1.8)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Column {
          anchors.fill: parent
          spacing: Style.space(14)

          // ------------------------------------------------------- header
          Item {
            width: parent.width
            implicitHeight: Math.max(title.implicitHeight, summary.implicitHeight)

            Text {
              id: title
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Task Manager"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              id: summary
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: {
                if (!root.service || !root.service.ready) return "SAMPLING…"
                var s = root.service
                return s.processCount + " PROCESSES · " + s.runningCount + " RUNNING · "
                  + s.threadCount + " THREADS · UP " + Model.formatUptime(s.uptime)
              }
              color: dim(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.0
            }
          }

          // -------------------------------------------------- stat cards
          Row {
            id: cards
            width: parent.width
            // Taller while expanded so a normal core count lands in full
            // instead of making the user scroll a grid to see half their CPU.
            height: root.anyCardExpanded ? Style.space(384) : Style.space(196)
            spacing: Style.space(12)

            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            // CPU takes two parts, every other card one. Counting parts rather
            // than cards is what keeps the row exactly `width` wide whether or
            // not the GPU card is present.
            readonly property bool gpuVisible: root.service && root.service.hasGpu
            readonly property int cardCount: gpuVisible ? 5 : 4
            readonly property real unit: (width - spacing * (cardCount - 1)) / (cardCount + 1)

            // CPU is the widest card because the per-core grid needs the room;
            // the others split what is left evenly. Expanded, it takes the lot.
            StatCard {
              visible: !root.gpuExpanded && !root.memExpanded && !root.netExpanded && !root.diskExpanded
              width: root.cpuExpanded ? cards.width : cards.unit * 2
              height: cards.height
              heading: "CPU"
              reading: root.service ? root.service.cpuPercent.toFixed(1) + "%" : "—"
              readingHot: root.service && root.service.cpuPercent >= 85
              detail: {
                if (!root.service || !root.service.ready) return ""
                var load = root.service.loadAverage
                var parts = [root.service.coreCount + " threads"]
                if (root.service.hasCpuTemp) parts.push(root.service.cpuTemp.toFixed(1) + "°C")
                parts.push("load " + Number(load[0]).toFixed(2) + " "
                  + Number(load[1]).toFixed(2) + " " + Number(load[2]).toFixed(2))
                parts.push(root.cpuExpanded ? "click to collapse" : "click for all cores")
                return parts.join(" · ")
              }
              interactive: true
              onCardClicked: root.toggleCpuExpanded()

              Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

              Sparkline {
                width: parent.width
                height: Style.space(60)
                visible: !root.cpuExpanded
                values: root.service ? root.service.cpuHistory : []
                capacity: root.service ? root.service.historyPoints : 60
                maxValue: 100
                stroke: root.foreground
                showBaseline: true
              }

              CoreGrid {
                ground: root.background
                width: parent.width
                visible: !root.cpuExpanded
                cores: root.service ? root.service.cores : []
                foreground: root.foreground
                fill: root.foreground
                hotColor: root.urgent
                rowHeight: Style.space(18)
              }

              CoreGraphGrid {
                ground: root.background
                id: coreGraphs
                width: parent.width
                // Whatever the card has left below the heading block, minus the
                // sensor strip that shares the expanded view with it.
                height: root.cpuExpanded
                  ? Math.max(Style.space(60), cards.height - Style.space(84) - sensorStrip.height - Style.space(10))
                  : 0
                visible: root.cpuExpanded
                histories: root.service ? root.service.coreHistories : []
                cores: root.service ? root.service.cores : []
                capacity: root.service ? root.service.historyPoints : 60
                foreground: root.foreground
                hotColor: root.urgent
                fontFamily: root.fontFamily
              }

              // Temperatures and fans. Which of these exist is decided entirely
              // by what hwmon drivers are loaded, so the strip reports what the
              // kernel offers and says plainly when it offers nothing.
              Column {
                id: sensorStrip
                width: parent.width
                visible: root.cpuExpanded
                spacing: Style.space(6)

                PanelSeparator { width: parent.width; foreground: root.foreground }

                // The two temperatures worth watching over time rather than
                // reading once. Both ride the free sampling path, so these open
                // populated; the other ten stay as text below, because graphing
                // them would mean paying their bus cost on every sample.
                Row {
                  id: tempGraphs
                  width: parent.width
                  height: Style.space(62)
                  spacing: Style.space(12)

                  readonly property bool cpuShown: root.service && root.service.hasCpuTemp
                  readonly property bool gpuShown: root.service && root.service.hasGpu
                    && root.service.gpuTempHistory.length > 0
                  readonly property real cell: cpuShown && gpuShown ? (width - spacing) / 2 : width

                  TempGraph {
                    width: tempGraphs.cell
                    height: tempGraphs.height
                    visible: tempGraphs.cpuShown
                    label: "CPU TEMP"
                    value: root.service ? root.service.cpuTemp : 0
                    history: root.service ? root.service.cpuTempHistory : []
                  }

                  TempGraph {
                    width: tempGraphs.cell
                    height: tempGraphs.height
                    visible: tempGraphs.gpuShown
                    label: "GPU TEMP"
                    value: root.service && root.service.hasGpu
                      ? (Number(root.service.primaryGpu.temp) || 0) : 0
                    history: root.service ? root.service.gpuTempHistory : []
                  }
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(18)

                  PanelSectionHeader {
                    text: "SENSORS"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                  }

                  Repeater {
                    model: root.service ? root.service.sensors : []

                    Text {
                      required property var modelData
                      // 80°C is the point past which a reading stops being
                      // trivia and starts being something to look at.
                      readonly property bool hot: Number(modelData.temp) >= 80

                      text: modelData.name + " " + Number(modelData.temp).toFixed(0) + "°C"
                      color: hot ? root.urgent : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: hot
                    }
                  }
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(18)

                  PanelSectionHeader {
                    text: "FANS"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                  }

                  Text {
                    visible: root.service && !root.service.fansAvailable
                    text: "no tachometer exposed by this board"
                    color: dim(root.foreground, 1.8)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Repeater {
                    model: root.service ? root.service.fans : []

                    Text {
                      required property var modelData
                      text: modelData.name + " " + modelData.rpm + " RPM"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    // The GPU fan comes from NVML rather than hwmon, so it is
                    // listed here alongside the board's fans instead of being
                    // stranded in the GPU card.
                    visible: root.service && root.service.hasGpu
                      && root.service.primaryGpu.fan !== null
                      && root.service.primaryGpu.fan !== undefined
                    text: "GPU " + (root.service ? root.service.primaryGpu.fan : 0) + "%"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            StatCard {
              visible: !root.cpuExpanded && !root.gpuExpanded && !root.netExpanded && !root.diskExpanded
              width: root.memExpanded ? cards.width : cards.unit
              height: cards.height
              heading: "MEMORY"
              reading: root.service ? root.service.memPercent.toFixed(0) + "%" : "—"
              readingHot: root.service && root.service.memPercent >= 90
              interactive: true
              onCardClicked: root.toggleMemExpanded()
              detail: {
                if (!root.service) return ""
                var text = Model.formatBytes(root.service.memUsed) + " / " + Model.formatBytes(root.service.memTotal)
                return text + " · " + (root.memExpanded ? "click to collapse" : "click for breakdown")
              }

              Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

              // ---------- collapsed ----------
              Sparkline {
                width: parent.width
                height: Style.space(52)
                visible: !root.memExpanded
                values: root.service ? root.service.memHistory : []
                capacity: root.service ? root.service.historyPoints : 60
                maxValue: 100
                stroke: root.foreground
                showBaseline: true
              }

              Meter {
                ground: root.background
                width: parent.width
                visible: !root.memExpanded && root.service && root.service.swapTotal > 0
                label: "SWAP"
                value: root.service ? Model.formatBytes(root.service.swapUsed) : ""
                fraction: root.service ? root.service.swapPercent / 100 : 0
                foreground: root.foreground
                fontFamily: root.fontFamily
                compact: true
              }

              // ---------- expanded ----------
              //
              // What the headline percentage hides: where "used" actually went,
              // whether anything is stalling on memory, and what swap is really
              // holding once zram's compression is accounted for.
              Item {
                width: parent.width
                visible: root.memExpanded
                height: visible ? Math.max(Style.space(60), cards.height - Style.space(84)) : 0

                // Graphs first: composition tells you where memory is now,
                // but only a trace tells you whether it is going somewhere.
                Row {
                  id: memGraphs
                  anchors.top: parent.top
                  width: parent.width
                  height: Style.space(74)
                  spacing: Style.space(12)

                  readonly property bool swapShown: root.service && root.service.swapTotal > 0
                  readonly property int count: swapShown ? 3 : 2
                  readonly property real cell: (width - spacing * (count - 1)) / count

                  MemGraph {
                    width: memGraphs.cell
                    height: memGraphs.height
                    label: "USED"
                    reading: root.service ? Model.formatBytes(root.service.memUsed) : ""
                    values: root.service ? root.service.memHistory : []
                    scaleMax: 100
                  }

                  // Processes against page cache on one shared scale. Anonymous
                  // memory climbing while cache is squeezed out is the shape of
                  // a machine running out of room, and it is only visible when
                  // the two are plotted against each other.
                  MemGraph {
                    width: memGraphs.cell
                    height: memGraphs.height
                    label: "PROCESSES vs CACHE"
                    reading: root.service
                      ? Model.formatBytes(root.service.mem.anon) + " / " + Model.formatBytes(root.service.mem.cached)
                      : ""
                    values: root.service ? root.service.memAnonHistory : []
                    secondaryValues: root.service ? root.service.memCacheHistory : []
                    scaleMax: root.service
                      ? Math.max(Model.peak(root.service.memAnonHistory),
                                 Model.peak(root.service.memCacheHistory)) * 1.05
                      : 0
                  }

                  MemGraph {
                    width: memGraphs.cell
                    height: memGraphs.height
                    visible: memGraphs.swapShown
                    label: "SWAP USED"
                    reading: root.service ? Model.formatBytes(root.service.swapUsed) : ""
                    values: root.service ? root.service.swapUsedHistory : []
                    // Autoscaled rather than pinned to swap size: on a 63 GB
                    // zram device a real 200 MB of swapping would be an
                    // invisible sliver against the total.
                    scaleMax: 0
                    hot: root.service && root.service.swapUsed > 0
                  }
                }

                Row {
                  id: memColumns
                  anchors.top: memGraphs.bottom
                  anchors.topMargin: Style.space(12)
                  anchors.bottom: parent.bottom
                  width: parent.width
                  spacing: Style.space(20)

                  readonly property real cell: (width - spacing * 2) / 3

                  // --- composition ---
                  ScrollColumn {
                    width: memColumns.cell
                    height: memColumns.height
                    spacing: Style.space(6)

                    PanelSectionHeader {
                      text: "WHERE IT WENT"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }

                    Repeater {
                      model: root.service ? root.service.memBreakdown : []

                      Item {
                        required property var modelData
                        width: parent.width
                        height: Style.space(19)

                        Text {
                          anchors.left: parent.left
                          anchors.right: breakdownValue.left
                          anchors.rightMargin: Style.space(8)
                          anchors.verticalCenter: parent.verticalCenter
                          text: modelData.label
                          elide: Text.ElideRight
                          color: dim(root.foreground, 1.4)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          id: breakdownValue
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          text: Model.formatBytes(modelData.value)
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }

                    // Page cache is not "used" in any sense worth alarming
                    // about — the kernel hands it back on demand — so it sits
                    // apart from the breakdown above rather than inside it.
                    Item {
                      width: parent.width
                      height: Style.space(19)

                      Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Cache (reclaimable)"
                        color: dim(root.foreground, 1.7)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.service ? Model.formatBytes(root.service.mem.cached) : ""
                        color: dim(root.foreground, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  // --- pressure ---
                  ScrollColumn {
                    width: memColumns.cell
                    height: memColumns.height
                    spacing: Style.space(6)

                    PanelSectionHeader {
                      text: "PRESSURE"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }

                    Text {
                      width: parent.width
                      wrapMode: Text.WordWrap
                      text: root.service && root.service.memStall > 0
                        ? "Tasks are stalling on memory."
                        : "No task has stalled on memory."
                      color: root.service && root.service.memStall > 0
                        ? root.urgent : dim(root.foreground, 1.6)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Sparkline {
                      width: parent.width
                      height: Style.space(44)
                      values: root.service ? root.service.memStallHistory : []
                      capacity: root.service ? root.service.historyPoints : 60
                      // Autoscaled: stall percentages live near zero, and the
                      // shape of a spike matters more than its absolute height.
                      maxValue: 0
                      stroke: root.service && root.service.memStall > 0 ? root.urgent : root.foreground
                      showBaseline: true
                    }

                    Repeater {
                      model: [
                        { label: "memory", key: "memPressure" },
                        { label: "cpu", key: "cpuPressure" },
                        { label: "io", key: "ioPressure" }
                      ]

                      Item {
                        required property var modelData
                        width: parent.width
                        height: Style.space(17)

                        readonly property var stats: root.service ? root.service[modelData.key] : ({})

                        Text {
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          text: modelData.label
                          color: dim(root.foreground, 1.6)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          text: "some " + Number(parent.stats.some10 || 0).toFixed(2)
                            + " / " + Number(parent.stats.some60 || 0).toFixed(2)
                            + " / " + Number(parent.stats.some300 || 0).toFixed(2)
                          color: Number(parent.stats.some10 || 0) > 0 ? root.urgent : root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }
                  }

                  // --- swap + commit ---
                  ScrollColumn {
                    width: memColumns.cell
                    height: memColumns.height
                    spacing: Style.space(6)

                    PanelSectionHeader {
                      text: "SWAP"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }

                    Text {
                      visible: root.service && root.service.swaps.length === 0
                      text: "no swap configured"
                      color: dim(root.foreground, 1.7)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Repeater {
                      model: root.service ? root.service.swaps : []

                      Column {
                        required property var modelData
                        width: parent.width
                        spacing: Style.space(2)

                        Item {
                          width: parent.width
                          height: Style.space(17)

                          Text {
                            anchors.left: parent.left
                            text: modelData.name
                            elide: Text.ElideRight
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }

                          Text {
                            anchors.right: parent.right
                            text: Model.formatBytes(modelData.used) + " / " + Model.formatBytes(modelData.size)
                            color: dim(root.foreground, 1.3)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }
                        }

                        // Only meaningful once zram is actually holding
                        // something; on an empty device the ratio is noise.
                        Text {
                          visible: modelData.zramRatio !== undefined && modelData.zramOriginal > 1048576
                          width: parent.width
                          text: "  " + (modelData.zramAlgorithm || "zram") + " · "
                            + Model.formatBytes(modelData.zramOriginal) + " in "
                            + Model.formatBytes(modelData.zramUsed) + " · "
                            + Number(modelData.zramRatio).toFixed(1) + "× · saves "
                            + Model.formatBytes(modelData.zramSaved)
                          elide: Text.ElideRight
                          color: dim(root.foreground, 1.6)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          visible: modelData.zramRatio !== undefined && !(modelData.zramOriginal > 1048576)
                          text: "  " + (modelData.zramAlgorithm || "zram") + " · idle"
                          color: dim(root.foreground, 1.8)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }

                    PanelSectionHeader {
                      text: "DIMM TEMPERATURE"
                      topPadding: Style.space(6)
                      visible: root.service && root.service.dimmSensors.length > 0
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }

                    Repeater {
                      model: root.service ? root.service.dimmSensors : []

                      Item {
                        required property var modelData
                        width: parent.width
                        height: Style.space(17)
                        // 85°C is the point where DIMMs start refreshing twice
                        // as often, which is the first thing you would notice.
                        readonly property bool hot: Number(modelData.temp) >= 85

                        Text {
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          text: modelData.name
                          color: dim(root.foreground, 1.6)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          text: Number(modelData.temp).toFixed(0) + "°C"
                          color: parent.hot ? root.urgent : root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: parent.hot
                        }
                      }
                    }

                    Text {
                      visible: root.service && root.service.dimmSensors.length === 0
                      text: "no DIMM sensor exposed"
                      color: dim(root.foreground, 1.8)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    PanelSectionHeader {
                      text: "COMMIT"
                      topPadding: Style.space(6)
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }

                    Item {
                      width: parent.width
                      height: Style.space(17)

                      Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        // Overcommit is normal on Linux and not by itself a
                        // fault, so it is stated rather than alarmed about.
                        text: root.service && root.service.overcommitted ? "overcommitted" : "within limit"
                        color: dim(root.foreground, 1.6)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.service
                          ? Model.formatBytes(root.service.committed) + " / " + Model.formatBytes(root.service.commitLimit)
                          : ""
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }
              }
            }

            // Absent entirely on a machine with no readable GPU, rather than
            // showing a card full of dashes.
            StatCard {
              visible: cards.gpuVisible && !root.cpuExpanded && !root.memExpanded && !root.netExpanded && !root.diskExpanded
              width: root.gpuExpanded ? cards.width : cards.unit
              height: cards.height
              interactive: true
              onCardClicked: root.toggleGpuExpanded()

              Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

              heading: "GPU"
              reading: root.service ? Math.round(root.service.gpuPercent) + "%" : "—"
              readingHot: root.service && root.service.gpuPercent >= 85
              // Temperature and power only; the VRAM figures go on the meter
              // below, where they have a bar to sit against. Cramming all four
              // onto one line just elided the last two away.
              detail: {
                if (!root.service || !root.service.hasGpu) return ""
                var device = root.service.primaryGpu
                var parts = []
                if (device.temp !== null && device.temp !== undefined) parts.push(device.temp + "°C")
                if (device.power !== null && device.power !== undefined) parts.push(device.power + " W")
                parts.push(root.gpuExpanded ? "click to collapse" : "click for engines")
                return parts.join(" · ")
              }

              // ---------- collapsed ----------
              Sparkline {
                width: parent.width
                height: Style.space(52)
                visible: !root.gpuExpanded
                values: root.service ? root.service.gpuHistory : []
                capacity: root.service ? root.service.historyPoints : 60
                maxValue: 100
                stroke: root.foreground
                showBaseline: true
              }

              Meter {
                ground: root.background
                width: parent.width
                visible: !root.gpuExpanded
                label: "VRAM"
                value: root.service
                  ? Model.formatBytes(root.service.gpuMemUsed) + " / " + Model.formatBytes(root.service.gpuMemTotal)
                  : ""
                fraction: root.service ? root.service.gpuMemPercent / 100 : 0
                foreground: root.foreground
                fontFamily: root.fontFamily
                compact: true
              }

              Text {
                width: parent.width
                visible: !root.gpuExpanded
                text: root.service && root.service.hasGpu ? String(root.service.primaryGpu.name) : ""
                elide: Text.ElideRight
                color: dim(root.foreground, 1.7)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              // ---------- expanded ----------
              //
              // Where CPU expands into its cores, the GPU expands into its
              // engines and its clients: three utilisation graphs, the hardware
              // readouts, and the answer to "what is holding my VRAM".
              Item {
                width: parent.width
                visible: root.gpuExpanded
                height: visible ? Math.max(Style.space(60), cards.height - Style.space(84)) : 0

                readonly property var device: root.service ? root.service.primaryGpu : ({})

                Row {
                  id: engineRow
                  width: parent.width
                  height: Style.space(96)
                  spacing: Style.space(12)

                  readonly property real cell: (width - spacing * 2) / 3

                  EngineGraph {
                    width: engineRow.cell
                    height: engineRow.height
                    label: "GRAPHICS"
                    value: root.service ? root.service.gpuPercent : 0
                    history: root.service ? root.service.gpuHistory : []
                  }

                  EngineGraph {
                    width: engineRow.cell
                    height: engineRow.height
                    label: "ENCODE"
                    supported: root.service && root.service.hasGpuEngines
                    value: parent.parent.device.encode || 0
                    history: root.service ? root.service.gpuEncodeHistory : []
                  }

                  EngineGraph {
                    width: engineRow.cell
                    height: engineRow.height
                    label: "DECODE"
                    supported: root.service && root.service.hasGpuEngines
                    value: parent.parent.device.decode || 0
                    history: root.service ? root.service.gpuDecodeHistory : []
                  }
                }

                // Hardware readouts. Each cell hides itself when the driver
                // returns null for that counter, so an unsupported reading is
                // absent rather than a confident zero.
                Row {
                  id: readoutRow
                  anchors.top: engineRow.bottom
                  anchors.topMargin: Style.space(10)
                  width: parent.width
                  spacing: Style.space(20)

                  readonly property var device: parent.device

                  Readout { label: "VRAM"; value: root.service
                    ? Model.formatBytes(root.service.gpuMemUsed) + " / " + Model.formatBytes(root.service.gpuMemTotal)
                    : "" }
                  Readout { label: "SM CLOCK"; value: readoutRow.device.smClock ? readoutRow.device.smClock + " MHz" : "" }
                  Readout { label: "MEM CLOCK"; value: readoutRow.device.memClock ? readoutRow.device.memClock + " MHz" : "" }
                  Readout {
                    label: "FAN"
                    value: readoutRow.device.fan === null || readoutRow.device.fan === undefined
                      ? "" : readoutRow.device.fan + "%"
                  }
                  Readout {
                    label: "POWER"
                    value: readoutRow.device.power === null || readoutRow.device.power === undefined
                      ? ""
                      : readoutRow.device.power + " / " + (readoutRow.device.powerLimit || "?") + " W"
                  }
                  Readout {
                    label: "PCIE"
                    value: readoutRow.device.pcieRx === null || readoutRow.device.pcieRx === undefined
                      ? ""
                      : "↓" + Model.formatRate(readoutRow.device.pcieRx) + "  ↑" + Model.formatRate(readoutRow.device.pcieTx)
                  }
                }

                PanelSeparator {
                  id: gpuRule
                  anchors.top: readoutRow.bottom
                  anchors.topMargin: Style.space(10)
                  width: parent.width
                  foreground: root.foreground
                }

                PanelSectionHeader {
                  id: vramHeader
                  anchors.top: gpuRule.bottom
                  anchors.topMargin: Style.space(8)
                  text: "VRAM BY PROCESS"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                ListView {
                  id: vramList
                  anchors.top: vramHeader.bottom
                  anchors.topMargin: Style.space(4)
                  anchors.bottom: parent.bottom
                  width: parent.width
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  model: root.service ? root.service.gpuProcesses : []

                  // Driven by the same Ctrl+↑/↓ that scrolls the per-core grid,
                  // so those keys mean "scroll whatever is expanded" rather
                  // than one thing here and something else there.
                  function scrollBy(delta) {
                    if (contentHeight <= height) return
                    contentY = Math.max(0, Math.min(contentHeight - height, contentY + delta))
                  }

                  delegate: Item {
                    required property var modelData
                    width: ListView.view.width
                    height: Style.space(20)

                    Text {
                      anchors.left: parent.left
                      width: Style.space(72)
                      text: modelData.pid
                      horizontalAlignment: Text.AlignRight
                      color: dim(root.foreground, 1.6)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(84)
                      anchors.right: vramValue.left
                      anchors.rightMargin: Style.space(10)
                      text: modelData.name
                      elide: Text.ElideRight
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      id: vramValue
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(8)
                      width: Style.space(80)
                      horizontalAlignment: Text.AlignRight
                      text: Model.formatBytes(modelData.mem)
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: parent.count === 0
                    text: "No process is holding VRAM"
                    color: dim(root.foreground, 1.7)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            StatCard {
              visible: !root.cpuExpanded && !root.gpuExpanded && !root.memExpanded && !root.diskExpanded
              width: root.netExpanded ? cards.width : cards.unit
              height: cards.height
              interactive: true
              onCardClicked: root.toggleNetExpanded()
              heading: "NETWORK"
              reading: root.service ? Model.formatRate(root.service.net.rx) : "—"
              detail: root.service
                ? "↑ " + Model.formatRate(root.service.net.tx)
                  + (root.service.net.ifaces && root.service.net.ifaces.length > 0
                     ? " · " + root.service.net.ifaces.map(function(i) { return i.name }).join(", ")
                     : "")
                : ""

              Sparkline {
                width: parent.width
                height: Style.space(52)
                visible: !root.netExpanded
                values: root.service ? root.service.netRxHistory : []
                capacity: root.service ? root.service.historyPoints : 60
                maxValue: 0  // byte rates have no ceiling; scale to what is in view
                stroke: root.foreground
                showBaseline: true
              }

              Sparkline {
                width: parent.width
                height: Style.space(30)
                visible: !root.netExpanded
                values: root.service ? root.service.netTxHistory : []
                capacity: root.service ? root.service.historyPoints : 60
                maxValue: 0
                stroke: dim(root.foreground, 1.4)
                fillOpacity: 0.10
                showBaseline: true
              }

              // ---------- expanded ----------
              Item {
                width: parent.width
                visible: root.netExpanded
                height: visible ? Math.max(Style.space(60), cards.height - Style.space(84)) : 0

                Row {
                  id: netGraphs
                  anchors.top: parent.top
                  width: parent.width
                  height: Style.space(74)
                  spacing: Style.space(12)

                  readonly property bool wifiShown: root.service && root.service.hasWifi
                  readonly property int count: wifiShown ? 3 : 2
                  readonly property real cell: (width - spacing * (count - 1)) / count

                  MemGraph {
                    width: netGraphs.cell
                    height: netGraphs.height
                    label: "DOWN"
                    reading: root.service ? Model.formatRate(root.service.net.rx) : ""
                    values: root.service ? root.service.netRxHistory : []
                    scaleMax: 0
                  }

                  MemGraph {
                    width: netGraphs.cell
                    height: netGraphs.height
                    label: "UP"
                    reading: root.service ? Model.formatRate(root.service.net.tx) : ""
                    values: root.service ? root.service.netTxHistory : []
                    scaleMax: 0
                  }

                  // Signal is the one network reading that is a condition
                  // rather than a rate: throughput can be zero because nothing
                  // is being asked for, but a sagging dBm is always a fact
                  // about the link.
                  TempGraph {
                    width: netGraphs.cell
                    height: netGraphs.height
                    visible: netGraphs.wifiShown
                    label: "WIFI SIGNAL"
                    value: root.service ? root.service.wifiSignal : 0
                    history: root.service ? root.service.wifiSignalHistory : []
                    unit: " dBm"
                    floor: -90
                    ceiling: -30
                    throttlePoint: -70
                    invertHot: true
                  }
                }

                Row {
                  anchors.top: netGraphs.bottom
                  anchors.topMargin: Style.space(12)
                  anchors.bottom: parent.bottom
                  width: parent.width
                  spacing: Style.space(20)

                  readonly property real cell: (width - spacing * 2) / 3

                  // --- links ---
                  ScrollColumn {
                    width: parent.cell
                    height: parent.height
                    spacing: Style.space(6)

                    PanelSectionHeader {
                      text: "LINKS"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }

                    Repeater {
                      model: root.service ? root.service.netLinks : []

                      Column {
                        required property var modelData
                        width: parent.width
                        spacing: Style.space(1)

                        readonly property var rate: root.service ? root.service.rateFor(modelData.name) : ({})

                        Item {
                          width: parent.width
                          height: Style.space(17)

                          Text {
                            anchors.left: parent.left
                            text: modelData.name
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }

                          Text {
                            anchors.right: parent.right
                            text: "↓" + Model.formatRate(parent.parent.rate.rx || 0)
                              + "  ↑" + Model.formatRate(parent.parent.rate.tx || 0)
                            color: dim(root.foreground, 1.3)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }
                        }

                        Text {
                          width: parent.width
                          text: {
                            var bits = [modelData.state]
                            if (modelData.speed) bits.push(modelData.speed + " Mb/s")
                            if (modelData.duplex && modelData.duplex !== "unknown") bits.push(modelData.duplex)
                            bits.push("mtu " + modelData.mtu)
                            if (modelData.wireless) bits.push("q " + Math.round(modelData.wireless.quality))
                            return "  " + bits.join(" · ")
                          }
                          elide: Text.ElideRight
                          color: dim(root.foreground, 1.7)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }
                  }

                  // --- errors ---
                  ScrollColumn {
                    width: parent.cell
                    height: parent.height
                    spacing: Style.space(6)

                    PanelSectionHeader {
                      text: "ERRORS & DROPS"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }

                    Repeater {
                      model: root.service ? root.service.netLinks : []

                      Item {
                        required property var modelData
                        width: parent.width
                        height: Style.space(17)

                        readonly property real bad: (Number(modelData.rx_errors) || 0)
                          + (Number(modelData.tx_errors) || 0)
                          + (Number(modelData.rx_dropped) || 0)
                          + (Number(modelData.tx_dropped) || 0)

                        Text {
                          anchors.left: parent.left
                          text: modelData.name
                          color: dim(root.foreground, 1.6)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          anchors.right: parent.right
                          text: "err " + ((Number(modelData.rx_errors) || 0) + (Number(modelData.tx_errors) || 0))
                            + " · drop " + ((Number(modelData.rx_dropped) || 0) + (Number(modelData.tx_dropped) || 0))
                          color: parent.bad > 0 ? root.urgent : root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }

                    Text {
                      width: parent.width
                      wrapMode: Text.WordWrap
                      topPadding: Style.space(4)
                      text: "Counters are since boot, not rates."
                      color: dim(root.foreground, 1.8)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  // --- sockets ---
                  ScrollColumn {
                    width: parent.cell
                    height: parent.height
                    spacing: Style.space(6)

                    PanelSectionHeader {
                      text: "TCP SOCKETS"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }

                    Repeater {
                      model: [
                        { label: "established", key: "established" },
                        { label: "listening", key: "listen" },
                        { label: "time-wait", key: "timeWait" },
                        { label: "close-wait", key: "closeWait" },
                        { label: "total", key: "total" }
                      ]

                      Item {
                        required property var modelData
                        width: parent.width
                        height: Style.space(17)

                        Text {
                          anchors.left: parent.left
                          text: modelData.label
                          color: dim(root.foreground, 1.6)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          anchors.right: parent.right
                          text: root.service ? (root.service.sockets[modelData.key] || 0) : "0"
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }

                    // Stated rather than left as a puzzle: people expect a task
                    // manager to name the process using the bandwidth, and the
                    // kernel simply does not account for it anywhere in /proc.
                    Text {
                      width: parent.width
                      wrapMode: Text.WordWrap
                      topPadding: Style.space(6)
                      text: "Per-process bandwidth needs eBPF; /proc does not account for it."
                      color: dim(root.foreground, 1.8)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            StatCard {
              visible: !root.cpuExpanded && !root.gpuExpanded && !root.memExpanded && !root.netExpanded
              width: root.diskExpanded ? cards.width : cards.unit
              height: cards.height
              interactive: true
              onCardClicked: root.toggleDiskExpanded()
              heading: "DISK"
              reading: root.service ? Model.formatRate(root.service.disk.read) : "—"
              detail: root.service
                ? "write " + Model.formatRate(root.service.disk.write)
                : ""

              Column {
                width: parent.width
                visible: !root.diskExpanded
                spacing: Style.spacing.labelGap

                Repeater {
                  model: root.service && root.service.diskDevices ? root.service.diskDevices.slice(0, 4) : []

                  Item {
                    required property var modelData
                    width: parent.width
                    height: Style.space(16)

                    Text {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.name
                      color: dim(root.foreground, 1.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: "↓" + Model.formatRate(modelData.read) + "  ↑" + Model.formatRate(modelData.write)
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }

              // ---------- expanded ----------
              Item {
                width: parent.width
                visible: root.diskExpanded
                height: visible ? Math.max(Style.space(60), cards.height - Style.space(84)) : 0

                Row {
                  id: diskGraphs
                  anchors.top: parent.top
                  width: parent.width
                  height: Style.space(74)
                  spacing: Style.space(12)

                  readonly property real cell: (width - spacing * 2) / 3

                  MemGraph {
                    width: diskGraphs.cell
                    height: diskGraphs.height
                    label: "READ"
                    reading: root.service ? Model.formatRate(root.service.disk.read) : ""
                    values: root.service ? root.service.diskReadHistory : []
                    scaleMax: 0
                  }

                  MemGraph {
                    width: diskGraphs.cell
                    height: diskGraphs.height
                    label: "WRITE"
                    reading: root.service ? Model.formatRate(root.service.disk.write) : ""
                    values: root.service ? root.service.diskWriteHistory : []
                    scaleMax: 0
                  }

                  // Throughput says how much is moving; utilisation says how
                  // hard the device is working to move it. A drive can be at
                  // 100% util shifting very little, which is the interesting
                  // case and the one a byte-rate graph alone hides.
                  MemGraph {
                    width: diskGraphs.cell
                    height: diskGraphs.height
                    label: "BUSIEST DEVICE"
                    reading: root.service ? Math.round(root.service.diskUtil) + "% util" : ""
                    values: root.service ? root.service.diskUtilHistory : []
                    scaleMax: 100
                    hot: root.service && root.service.diskUtil >= 90
                  }
                }

                Row {
                  anchors.top: diskGraphs.bottom
                  anchors.topMargin: Style.space(12)
                  anchors.bottom: parent.bottom
                  width: parent.width
                  spacing: Style.space(20)

                  readonly property real cell: (width - spacing * 2) / 3

                  // --- devices ---
                  ScrollColumn {
                    width: parent.cell
                    height: parent.height
                    spacing: Style.space(6)

                    PanelSectionHeader {
                      text: "DEVICES"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }

                    Repeater {
                      model: root.service ? root.service.diskDevices : []

                      Column {
                        required property var modelData
                        width: parent.width
                        spacing: Style.space(1)

                        Item {
                          width: parent.width
                          height: Style.space(17)

                          Text {
                            anchors.left: parent.left
                            text: modelData.name
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }

                          Text {
                            anchors.right: parent.right
                            text: "↓" + Model.formatRate(modelData.read) + "  ↑" + Model.formatRate(modelData.write)
                            color: dim(root.foreground, 1.3)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }
                        }

                        // The iostat figures: how hard the queue is working and
                        // how long a request is taking, which is what tells a
                        // busy device from a struggling one.
                        Text {
                          width: parent.width
                          text: "  " + Number(modelData.iops).toFixed(0) + " iops · "
                            + Number(modelData.util).toFixed(0) + "% util · q "
                            + modelData.queue + " · " + Number(modelData.latency).toFixed(2) + " ms"
                          elide: Text.ElideRight
                          color: Number(modelData.util) >= 90
                            ? root.urgent : dim(root.foreground, 1.7)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }
                  }

                  // --- filesystems ---
                  ScrollColumn {
                    width: parent.cell
                    height: parent.height
                    spacing: Style.space(5)

                    PanelSectionHeader {
                      text: "FILESYSTEMS"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }

                    Repeater {
                      model: root.service ? root.service.filesystems : []

                      Column {
                        required property var modelData
                        width: parent.width
                        spacing: Style.space(1)

                        // Matches df's Use%, so the number is comparable with
                        // what the terminal says.
                        readonly property bool nearlyFull: Number(modelData.percent) >= 90

                        Item {
                          width: parent.width
                          height: Style.space(16)

                          Text {
                            anchors.left: parent.left
                            anchors.right: fsPercent.left
                            anchors.rightMargin: Style.space(8)
                            text: modelData.mounts.join(", ")
                            elide: Text.ElideRight
                            color: parent.parent.nearlyFull ? root.urgent : root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }

                          Text {
                            id: fsPercent
                            anchors.right: parent.right
                            text: Number(modelData.percent).toFixed(0) + "%"
                            color: parent.parent.nearlyFull ? root.urgent : root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: parent.parent.nearlyFull
                          }
                        }

                        Meter {
                          ground: root.background
                          width: parent.width
                          fraction: Number(modelData.percent) / 100
                          foreground: root.foreground
                          fill: parent.nearlyFull ? root.urgent : root.foreground
                          fontFamily: root.fontFamily
                          trackHeight: Style.space(3)
                          compact: true
                        }

                        Text {
                          width: parent.width
                          text: "  " + modelData.fstype + " · "
                            + Model.formatBytes(modelData.avail) + " free"
                          elide: Text.ElideRight
                          color: dim(root.foreground, 1.7)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }
                  }

                  // --- I/O by process ---
                  ScrollColumn {
                    width: parent.cell
                    height: parent.height
                    spacing: Style.space(6)

                    PanelSectionHeader {
                      text: "I/O BY PROCESS"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                    }

                    Text {
                      visible: root.service && root.service.ioProcesses.length === 0
                      text: "no block I/O this interval"
                      color: dim(root.foreground, 1.8)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Repeater {
                      model: root.service ? root.service.ioProcesses.slice(0, 8) : []

                      Item {
                        required property var modelData
                        width: parent.width
                        height: Style.space(17)

                        Text {
                          anchors.left: parent.left
                          anchors.right: ioRate.left
                          anchors.rightMargin: Style.space(8)
                          text: modelData.name
                          elide: Text.ElideRight
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          id: ioRate
                          anchors.right: parent.right
                          text: "↓" + Model.formatRate(modelData.read) + "  ↑" + Model.formatRate(modelData.write)
                          color: dim(root.foreground, 1.3)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }

                    // Unlike network, the kernel does account for this per
                    // process — but only to the owner, so the list is partial
                    // by design and says how partial.
                    Text {
                      width: parent.width
                      wrapMode: Text.WordWrap
                      topPadding: Style.space(6)
                      text: root.service && root.service.ioTotal > 0
                        ? "Readable for " + root.service.ioReadable + " of "
                          + root.service.ioTotal + " processes; the rest are other users'."
                        : ""
                      color: dim(root.foreground, 1.8)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ------------------------------------------------ filter + sort
          Item {
            width: parent.width
            implicitHeight: Style.space(22)

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: {
                if (root.filterText !== "") return "filter: " + root.filterText + "▏"
                if (root.appsMode) {
                  var grouped = root.service && root.service.groupApps
                  return "Applications  ·  " + (grouped ? "grouped" : "by scope")
                    + " (g)  ·  Ctrl+A to switch  ·  ? for keys"
                }
                return (root.treeMode ? "Process tree" : "Processes")
                  + "  ·  Ctrl+A to switch  ·  ? for keys"
              }
              elide: Text.ElideRight
              width: parent.width - Style.space(90)
              color: root.filterText === "" ? dim(root.foreground, 1.8) : root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.rows.length + " shown"
              color: dim(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // -------------------------------------------------- table header
          //
          // The header has to reproduce ProcessRow's geometry exactly: same
          // insets, same conditional columns, same gap count. Two things had
          // drifted. ProcessRow insets its Row a few pixels each side and the
          // header did not, so every heading sat slightly right of the values
          // it labels, in every view. And Row drops the spacing of an invisible
          // child along with its width, so the chevron the header always
          // reserved but an application row never has left the PROCESS heading
          // a whole column-and-gap right of the names underneath it.
          Row {
            id: header
            width: parent.width
            height: Style.space(20)
            spacing: Style.space(8)
            // Matches ProcessRow's Row margins, which are otherwise a constant
            // few pixels of skew between every heading and its column.
            leftPadding: Style.space(6)
            rightPadding: Style.space(4)

            // Name, CPU, memory and the kill column are always present (three
            // gaps); pid and wait are always on in the overlay (two more); the
            // chevron is the only one that comes and goes.
            readonly property int gapCount: 5 + (root.rowsExpandable ? 1 : 0)
            readonly property real fixedWidth: leftPadding + rightPadding
              + spacing * gapCount
              + (root.rowsExpandable ? Style.space(16) : 0)
              + Style.space(56) + Style.space(64) + Style.space(60)
              + Style.space(72) + Style.space(22)

            Item {
              visible: root.rowsExpandable                    // chevron column
              width: visible ? Style.space(16) : 0
              height: 1
            }
            SortHeader {
              width: Style.space(56)
              label: root.appsMode ? "PROCS" : "PID"
              sort: root.appsMode ? "procs" : "pid"
              alignment: Text.AlignRight
            }
            SortHeader {
              width: header.width - header.fixedWidth
              label: "PROCESS"
              sort: "name"
            }
            SortHeader {
              width: Style.space(64)
              label: root.appsMode ? "STALL" : (root.listMode === "processes" ? "WAIT" : "USER")
              sort: root.appsMode ? "ioStall" : (root.listMode === "processes" ? "wait" : "")
              alignment: root.appsMode || root.listMode === "processes" ? Text.AlignRight : Text.AlignLeft
            }
            SortHeader { width: Style.space(60); label: "CPU"; sort: "cpu"; alignment: Text.AlignRight }
            SortHeader {
              width: Style.space(72)
              label: "MEMORY"
              sort: root.appsMode ? "mem" : "rss"
              alignment: Text.AlignRight
            }
            Item { width: Style.space(22); height: 1 }
          }

          // --------------------------------------------------- the table
          ListView {
            id: list
            width: parent.width
            // Fill whatever the cards and chrome above did not take.
            height: parent.height - y
            clip: true
            model: root.rows
            boundsBehavior: Flickable.StopAtBounds
            spacing: Style.space(1)
            currentIndex: root.selectedIndex
            cacheBuffer: Style.space(400)

            // A row plus, when expanded, that process's threads underneath it.
            // The delegate is a Column so the ListView measures the pair as one
            // variable-height item and scrolling stays correct.
            delegate: Column {
              id: rowGroup
              required property var modelData
              required property int index

              readonly property bool expanded: root.expandedPid === modelData.pid

              width: list.width

              ProcessRow {
                ground: root.background
                width: parent.width
                height: Style.space(34)
                process: rowGroup.modelData
                detailed: true
                machineCapacity: root.service ? Math.max(1, root.service.coreCount) * 100 : 100
                appMode: root.appsMode
                depth: Number(rowGroup.modelData.depth) || 0
                showWait: root.listMode === "processes"
                expandable: root.rowsExpandable
                expanded: rowGroup.expanded
                selected: root.appsMode
                  ? rowGroup.modelData.unit === root.selectedUnit
                  : rowGroup.modelData.pid === root.selectedPid
                foreground: root.foreground
                accent: root.accent
                urgent: root.urgent
                fontFamily: root.fontFamily

                onActivated: {
                  if (root.appsMode) root.selectedUnit = rowGroup.modelData.unit
                  else root.selectedPid = rowGroup.modelData.pid
                }
                onExpandToggled: {
                  root.selectedPid = rowGroup.modelData.pid
                  root.toggleThreads(rowGroup.modelData.pid)
                }
                onKillRequested: function(signalName) {
                  if (root.service) root.service.killProcess(rowGroup.modelData.pid, signalName)
                }
              }

              Loader {
                width: parent.width
                active: rowGroup.expanded
                visible: active
                sourceComponent: threadList
              }
            }

            // Threads of the expanded process. Its own component so the
            // delegate stays legible and the rows cost nothing when collapsed.
            Component {
              id: threadList

              Column {
                readonly property var threads: root.service ? root.service.threads : []

                spacing: 0
                bottomPadding: Style.space(6)

                Text {
                  visible: parent.threads.length === 0
                  leftPadding: Style.space(78)
                  height: Style.space(22)
                  verticalAlignment: Text.AlignVCenter
                  text: "Reading threads…"
                  color: dim(root.foreground, 1.7)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Repeater {
                  model: parent.threads

                  Item {
                    required property var modelData
                    width: list.width
                    height: Style.space(20)

                    readonly property real cpuValue: Number(modelData.cpu) || 0
                    readonly property bool hot: cpuValue >= 50

                    // Indented under the process name column, so the threads
                    // read as belonging to the row above rather than as peers.
                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(78)
                      anchors.verticalCenter: parent.verticalCenter
                      text: "└ " + modelData.tid
                      color: dim(root.foreground, 1.8)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(148)
                      anchors.right: threadCpu.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.name + "  ·  " + Model.stateName(modelData.state)
                      elide: Text.ElideRight
                      color: dim(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      id: threadCpu
                      anchors.right: parent.right
                      // Lands on ProcessRow's CPU column: its Row's right
                      // margin, the kill column, the memory column, and the
                      // gap either side of memory. Counted out rather than
                      // written as one number so it stays checkable against
                      // the row — it was two gaps short, which pushed every
                      // thread's percentage right of the process above it.
                      anchors.rightMargin: Style.space(4 + 22 + 8 + 72 + 8)
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(60)
                      horizontalAlignment: Text.AlignRight
                      text: parent.cpuValue.toFixed(1) + "%"
                      color: parent.hot ? root.urgent : dim(root.foreground, 1.2)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: root.rows.length === 0
              text: {
                if (!root.service || !root.service.ready) return "Waiting for the first sample…"
                var noun = root.appsMode ? "application" : "process"
                if (root.filterText !== "") return "No " + noun + " matches “" + root.filterText + "”"
                return "Collecting " + noun + " data…"
              }
              color: dim(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }
      }
    }
  }

  // A bordered panel with a heading, a big reading, a caption, and whatever
  // graphs the caller nests inside it.
  component StatCard: BorderSurface {
    id: statCard
    default property alias cardContent: cardColumn.children

    property string heading: ""
    property string reading: ""
    property string detail: ""
    property bool readingHot: false
    property bool interactive: false

    signal cardClicked()

    radius: Style.cornerRadius
    color: cardMouse.containsMouse
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
    borderSpec: Border.none()

    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
      id: cardMouse
      anchors.fill: parent
      enabled: statCard.interactive
      hoverEnabled: statCard.interactive
      cursorShape: statCard.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: statCard.cardClicked()
    }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(12)
      spacing: Style.space(8)

      Item {
        width: parent.width
        implicitHeight: cardReading.implicitHeight

        Text {
          anchors.left: parent.left
          // Stop where the reading starts. A wide reading ("385 KB/s") would
          // otherwise be painted straight through the heading.
          anchors.right: cardReading.left
          anchors.rightMargin: Style.space(6)
          anchors.bottom: cardReading.baseline
          anchors.bottomMargin: -Style.space(1)
          text: statCard.heading
          elide: Text.ElideRight
          color: dim(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
        }

        Text {
          id: cardReading
          anchors.right: parent.right
          text: statCard.reading
          color: statCard.readingHot ? root.urgent : root.foreground
          font.family: root.fontFamily
          // Rates run far longer than percentages; stepping the size down
          // keeps a five-card row from having to choose between the number
          // and the label that says what it is.
          font.pixelSize: statCard.reading.length > 6 ? Style.font.heading : Style.font.display
          font.bold: true

          Behavior on color { ColorAnimation { duration: 200 } }
        }
      }

      Text {
        width: parent.width
        text: statCard.detail
        elide: Text.ElideRight
        color: dim(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Column {
        id: cardColumn
        width: parent.width
        spacing: Style.space(8)
      }
    }
  }

  // A temperature over time, plotted on a fixed 30–100°C scale with a dashed
  // line at the point where a part is usually throttling. Fixed rather than
  // autoscaled on purpose: autoscale would turn a degree of idle jitter into a
  // dramatic mountain range, and the question being asked is "how close is this
  // to its limit", which only a stable scale can answer at a glance.
  // A detail column that scrolls when its content outgrows the card, with a
  // scrollbar that only appears when there is something to scroll to. Without
  // this a long list — six filesystems, a dozen interfaces — simply ran past
  // the bottom of the card and was silently cut off.
  component ScrollColumn: Item {
    id: scrollRoot

    default property alias content: inner.children
    property real spacing: Style.space(6)

    readonly property bool overflowing: flick.contentHeight > flick.height + 1

    function scrollBy(delta) {
      if (!overflowing) return
      flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + delta))
    }

    // Registered so the keyboard can reach it; whichever card is expanded is
    // the only one with live columns, so Ctrl+arrow never has to guess.
    Component.onCompleted: root.registerScrollable(scrollRoot)
    Component.onDestruction: root.unregisterScrollable(scrollRoot)

    Flickable {
      id: flick
      anchors.fill: parent
      // Give the bar its own gutter rather than letting it sit over the text.
      anchors.rightMargin: scrollRoot.overflowing ? Style.space(9) : 0
      clip: true
      contentWidth: width
      contentHeight: inner.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick

      Column {
        id: inner
        width: flick.width
        spacing: scrollRoot.spacing
      }
    }

    Rectangle {
      visible: scrollRoot.overflowing
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Style.space(3)
      radius: width / 2
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

      Rectangle {
        width: parent.width
        radius: parent.radius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
        height: Math.max(Style.space(16), parent.height * (flick.height / Math.max(1, flick.contentHeight)))
        y: {
          var scrollable = Math.max(1, flick.contentHeight - flick.height)
          return (parent.height - height) * Math.min(1, Math.max(0, flick.contentY / scrollable))
        }
      }
    }
  }

  // A labelled memory trace, optionally with a second series overlaid on the
  // same scale (drawn fainter, so the pair reads as foreground against
  // background rather than as two equal claims).
  component MemGraph: Item {
    property string label: ""
    property string reading: ""
    property var values: []
    property var secondaryValues: []
    property real scaleMax: 0
    property bool hot: false

    Rectangle {
      anchors.fill: parent
      radius: Style.space(3)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
    }

    Text {
      id: memGraphLabel
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.margins: Style.space(6)
      text: parent.label
      color: dim(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.0
    }

    Text {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(6)
      text: parent.reading
      color: parent.hot ? root.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    // Background series first so the primary one draws over it.
    Sparkline {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.top: memGraphLabel.bottom
      anchors.margins: Style.space(6)
      visible: parent.secondaryValues.length > 0
      values: parent.secondaryValues
      capacity: root.service ? root.service.historyPoints : 60
      maxValue: parent.scaleMax
      stroke: dim(root.foreground, 1.7)
      lineWidth: 1
      fillOpacity: 0.06
    }

    Sparkline {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.top: memGraphLabel.bottom
      anchors.margins: Style.space(6)
      values: parent.values
      capacity: root.service ? root.service.historyPoints : 60
      maxValue: parent.scaleMax
      stroke: parent.hot ? root.urgent : root.foreground
      lineWidth: 1
      fillOpacity: 0.18
      showBaseline: true
    }
  }

  component TempGraph: Item {
    property string label: ""
    property real value: 0
    property var history: []
    property real floor: 30
    property real ceiling: 100
    property real throttlePoint: 90
    property string unit: "°C"
    // Temperature is bad when high; signal strength is bad when low. Same
    // graph, opposite sense of "past the line".
    property bool invertHot: false

    readonly property bool hot: invertHot ? value <= throttlePoint : value >= throttlePoint

    Rectangle {
      anchors.fill: parent
      radius: Style.space(3)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
    }

    Text {
      id: tempLabel
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.margins: Style.space(5)
      text: parent.label
      color: dim(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.0
    }

    Text {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(5)
      text: Math.round(parent.value) + parent.unit
      color: parent.hot ? root.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Sparkline {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.top: tempLabel.bottom
      anchors.margins: Style.space(5)
      values: parent.history
      capacity: root.service ? root.service.historyPoints : 60
      minValue: parent.floor
      maxValue: parent.ceiling
      thresholdValue: parent.throttlePoint
      thresholdColor: root.urgent
      stroke: parent.hot ? root.urgent : root.foreground
      lineWidth: 1
      fillOpacity: 0.18
    }
  }

  // One engine's utilisation: title, current percentage, and its history.
  // `supported: false` greys the cell out rather than drawing a flat zero line
  // that would read as "idle" when it actually means "not reported".
  component EngineGraph: Item {
    property string label: ""
    property real value: 0
    property var history: []
    property bool supported: true

    Rectangle {
      anchors.fill: parent
      radius: Style.space(3)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
    }

    Text {
      id: engineLabel
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.margins: Style.space(6)
      text: parent.label
      color: dim(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.0
    }

    Text {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(6)
      text: parent.supported ? Math.round(parent.value) + "%" : "n/a"
      color: parent.supported && parent.value >= 85 ? root.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Sparkline {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.top: engineLabel.bottom
      anchors.margins: Style.space(6)
      visible: parent.supported
      values: parent.history
      capacity: root.service ? root.service.historyPoints : 60
      maxValue: 100
      stroke: root.foreground
      showBaseline: true
    }
  }

  // Stacked label-over-value pair for the GPU hardware readouts.
  component Readout: Column {
    property string label: ""
    property string value: ""

    visible: value !== ""
    spacing: Style.spacing.labelGap

    PanelSectionHeader {
      text: parent.label
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Text {
      text: parent.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // Column label that sorts on click and marks the active column's direction.
  component SortHeader: Text {
    property string label: ""
    property string sort: ""
    property int alignment: Text.AlignLeft

    readonly property bool active: sort !== "" && root.sortId === sort

    height: parent ? parent.height : implicitHeight
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: alignment
    text: label + (active ? (root.sortDescending ? " ▼" : " ▲") : "")
    elide: Text.ElideRight
    color: active ? root.accent : dim(root.foreground, 1.6)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 0.8

    MouseArea {
      anchors.fill: parent
      enabled: parent.sort !== ""
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.applySort(parent.sort)
    }
  }
}
