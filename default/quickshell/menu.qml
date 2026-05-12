import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
  id: root

  property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID"))) + "/omarchy-menu.sock"
  property string startupMenuJsonFile: Quickshell.env("OMARCHY_MENU_JSON_FILE") || ""
  property string menuBin: Quickshell.env("OMARCHY_MENU_BIN") || "omarchy-menu"
  property string startupInitialMenu: Quickshell.env("OMARCHY_MENU_INITIAL_MENU") || "root"
  property string startupSelectionFile: Quickshell.env("OMARCHY_MENU_SELECTION_FILE") || ""
  property string startupDoneFile: Quickshell.env("OMARCHY_MENU_DONE_FILE") || ""
  property string startupColorsRaw: Quickshell.env("OMARCHY_MENU_COLORS_RAW") || ""
  property string fontFamily: Quickshell.env("OMARCHY_MENU_FONT") || "monospace"
  property string colorsFile: Quickshell.env("OMARCHY_MENU_COLORS_FILE") || (Quickshell.env("HOME") + "/.config/omarchy/current/theme/menu.json")
  property string styleFile: Quickshell.env("OMARCHY_MENU_STYLE_FILE") || (Quickshell.env("HOME") + "/.local/state/omarchy/toggles/quickshell-menu.json")
  property string selectionFile: ""
  property string doneFile: ""
  property bool requestActive: false
  property bool opened: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  property string filterText: ""
  property int selectedIndex: 0
  property int requestSerial: 0
  property int applySerial: 0
  property var items: ({})
  property var itemOrder: []
  property var navStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property var doneFilesToRelease: []
  property color accent: "#89b4fa"
  property color background: "#101315"
  property color foreground: "#cacccc"
  property color border: foreground
  property int cornerRadius: 0
  property int contentMargin: 18
  property int headerHeight: 34
  property int contentSpacing: 6
  property int baseRowHeight: 50
  property int detailRowHeight: 58
  property int rowSpacing: 3
  property int dividerHeight: 17
  property bool searchDivider: false
  property int layoutSerial: 0
  property int cardWidth: Math.min(300, panel.width - 48)
  property int visibleRowsHeight: rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  property int cardHeight: Math.min(Math.max(220, contentMargin * 2 + headerHeight + contentSpacing + visibleRowsHeight), panel.height - 48)

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function decodeField(value) {
    return String(value || "").replace(/\v/g, "\n").replace(/\f/g, "\t")
  }

  function withAlpha(color, alpha) {
    return Qt.rgba(color.r, color.g, color.b, alpha)
  }

  function rowHeightForDetail(detail) {
    return root.filterText && detail ? root.detailRowHeight : root.baseRowHeight
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    if (displayModel.count === 0) return root.baseRowHeight

    var count = Math.min(displayModel.count, 10)
    var total = 0
    var previousSection = ""

    for (var i = 0; i < count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      if (row.section === "drilldown" && previousSection !== "drilldown") total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail)
      previousSection = row.section
    }

    return total
  }

  function item(id) {
    return root.items[id] || null
  }

  function loadMenuJson(raw) {
    var nextItems = ({})
    var nextOrder = []
    var payload = JSON.parse(raw || "{}")
    var rows = payload.items || []

    for (var i = 0; i < rows.length; i++) {
      var entry = rows[i]
      var id = entry.id || ""
      if (!id) continue

      var order = nextItems[id] ? nextItems[id].order : nextOrder.length
      if (!nextItems[id]) nextOrder.push(id)

      nextItems[id] = {
        id: id,
        parent: entry.parent || "",
        kind: entry.kind || "action",
        icon: entry.icon || "",
        label: entry.label || id,
        target: entry.target || "",
        keywords: entry.keywords || "",
        description: entry.description || "",
        action: entry.action || "",
        provider: entry.provider || "",
        order: order
      }
    }

    if (!nextItems.root) {
      nextItems.root = { id: "root", parent: "", kind: "menu", icon: "", label: "Go", target: "", keywords: "", description: "", order: -1 }
    }

    root.items = nextItems
    root.itemOrder = nextOrder
    root.rowsLoaded = true
  }

  function mergeProviderJson(raw, menuId) {
    var payload = ({})
    try {
      payload = JSON.parse(raw || "{}")
    } catch (e) {
      return
    }

    var rows = payload.items || []
    var changed = false

    for (var i = 0; i < rows.length; i++) {
      var entry = rows[i]
      var id = entry.id || ""
      if (!id) continue

      if (!root.items[id]) root.itemOrder.push(id)
      root.items[id] = {
        id: id,
        parent: entry.parent || menuId,
        kind: entry.kind || "action",
        icon: entry.icon || "",
        label: entry.label || id,
        target: entry.target || "",
        keywords: entry.keywords || "",
        description: entry.description || "",
        action: entry.action || "",
        provider: entry.provider || "",
        order: root.itemOrder.indexOf(id)
      }
      changed = true
    }

    if (changed) root.rebuildDisplay()
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.output = ""
    providerProc.command = [root.menuBin, "--provider", entry.provider, id]
    providerProc.running = true
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) {
    var depth = 0
    var current = root.item(id)
    var guard = 0

    while (current && current.parent && current.parent !== "root" && guard < 32) {
      depth += 1
      current = root.item(current.parent)
      guard += 1
    }

    return depth
  }

  function pathFor(id) {
    var labels = []
    var current = root.item(id)
    var guard = 0

    while (current && current.id !== "root" && guard < 32) {
      labels.unshift(current.label)
      current = root.item(current.parent)
      guard += 1
    }

    return labels.join(" › ")
  }

  function parentPathFor(id) {
    var entry = root.item(id)
    if (!entry || !entry.parent || entry.parent === "root") return ""

    return root.pathFor(entry.parent)
  }

  function breadcrumbFor(id) {
    var path = root.pathFor(id)
    return path ? ("Go › " + path) : "Go"
  }

  function isDescendantOf(id, ancestorId) {
    if (ancestorId === "root") return id !== "root"

    var current = root.item(id)
    var guard = 0
    while (current && current.parent && guard < 32) {
      if (current.parent === ancestorId) return true
      current = root.item(current.parent)
      guard += 1
    }

    return false
  }

  function childCount(id) {
    var count = 0
    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (entry && entry.parent === id) count += 1
    }

    return count
  }

  function matchesQuery(entry, query) {
    if (!entry || entry.id === "root") return false

    var haystack = (entry.label + " " + root.pathFor(entry.id) + " " + entry.keywords + " " + entry.description).toLowerCase()
    var terms = query.toLowerCase().trim().split(/\s+/)

    for (var i = 0; i < terms.length; i++) {
      if (terms[i] && haystack.indexOf(terms[i]) === -1) return false
    }

    return true
  }

  function searchScore(entry, query) {
    var needle = query.toLowerCase().trim()
    var label = entry.label.toLowerCase()
    var path = root.pathFor(entry.id).toLowerCase()
    var keywords = entry.keywords.toLowerCase()
    var parent = root.item(entry.parent)
    var parentLabel = parent ? parent.label.toLowerCase() : ""
    var score = 80

    if (label === needle) score = entry.parent === "root" ? 2 : 0
    else if (label.indexOf(needle) === 0) score = 10
    else if (path.indexOf(needle) === 0) score = entry.kind === "action" ? 12 : 14
    else if (parentLabel === needle) score = entry.kind === "action" ? 18 : 20
    else if (label.indexOf(needle) >= 0) score = 30
    else if (path.indexOf(needle) >= 0) score = 40
    else if (keywords.indexOf(needle) >= 0) score = 50

    if (entry.kind === "menu" || entry.kind === "link") score -= 2

    return score * 1000 + root.depthFor(entry.id) * 25 + entry.order
  }

  function displayRow(entry, detail, score, section) {
    var target = entry.kind === "link" ? entry.target : entry.id
    return {
      itemId: entry.id,
      kind: entry.kind,
      icon: entry.icon,
      label: entry.label,
      target: target,
      detail: detail || "",
      path: root.pathFor(entry.id),
      childCount: (entry.kind === "menu" || entry.kind === "link") ? root.childCount(target) : 0,
      action: entry.action || "",
      provider: entry.provider || "",
      score: score || 0,
      section: section || ""
    }
  }

  function rebuildDisplay() {
    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var currentRows = []
      var drilldownRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (!root.isDescendantOf(entry.id, active)) continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        if (entry.parent === active) currentRows.push(row)
        else drilldownRows.push(row)
      }

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      currentRows.sort(searchSort)
      drilldownRows.sort(searchSort)
      root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0
      if (root.searchDivider) {
        for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
      }
      rows = currentRows.concat(drilldownRows)
    } else {
      if (active !== "root") {
        var parentTarget = root.item(active).parent || "root"
        var backTarget = root.navStack.length > 0 ? root.navStack[root.navStack.length - 1] : parentTarget
        rows.push({ itemId: "__back", kind: "back", icon: "", label: "Back", target: backTarget, detail: root.breadcrumbFor(backTarget), path: "", childCount: 0, action: "", score: -1, section: "" })
      }

      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active) continue
        rows.push(root.displayRow(child, child.description, child.order))
      }
    }

    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return

    selectedIndex += delta
    if (selectedIndex < 0) selectedIndex = 0
    if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    if (root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }

  function setActiveMenu(id, pushHistory) {
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
    root.selectedIndex = 0
    root.rebuildDisplay()
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root") return false

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    if (row.kind === "back") {
      root.goBack()
    } else if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true)
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function releaseNextDoneFile() {
    if (releaseProc.running || doneFilesToRelease.length === 0) return

    var path = doneFilesToRelease.shift()
    releaseProc.command = ["bash", "-lc", ": > " + shellQuote(path)]
    releaseProc.running = true
  }

  function finishDoneFile(path) {
    if (!path) return
    doneFilesToRelease.push(path)
    releaseNextDoneFile()
  }

  function resetRequest() {
    requestActive = false
    selectionFile = ""
    doneFile = ""
  }

  function applySelected(id, action) {
    if (!id || !selectionFile || !doneFile) {
      cancel()
      return
    }

    var activeSelectionFile = selectionFile
    var activeDoneFile = doneFile
    applySerial = requestSerial
    resetRequest()
    opened = false

    applyProc.command = ["bash", "-lc", "printf '%s\\t%s\\n' " + shellQuote(id) + " " + shellQuote(action || "") + " > " + shellQuote(activeSelectionFile) + "; : > " + shellQuote(activeDoneFile)]
    applyProc.running = true
  }

  function cancel() {
    if (requestActive) finishDoneFile(doneFile)
    resetRequest()
    opened = false
    filterText = ""
  }

  function closeMenu(nextDoneFile) {
    requestSerial += 1

    if (requestActive) finishDoneFile(doneFile)
    if (nextDoneFile && nextDoneFile !== doneFile) finishDoneFile(nextDoneFile)

    resetRequest()
    opened = false
    filterText = ""
  }

  function openMenu(menuJson, initialMenu, nextSelectionFile, nextDoneFile, colorsRaw) {
    requestSerial += 1

    if (requestActive && doneFile && doneFile !== nextDoneFile) finishDoneFile(doneFile)

    loadMenuJson(menuJson)
    if (colorsRaw) loadColors(colorsRaw)

    selectionFile = nextSelectionFile
    doneFile = nextDoneFile
    requestActive = !!doneFile
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    providersLoaded = ({})
    providerQueue = []
    filterText = ""
    selectedIndex = 0
    opened = true
    rebuildDisplay()
    loadProviderForMenu(activeMenu)

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function loadColors(raw) {
    try {
      var colors = JSON.parse(raw || "{}")
      root.accent = colors.accent || colors.primary || root.accent
      root.background = colors.background || root.background
      root.foreground = colors.foreground || colors.backgroundText || root.foreground
      root.border = colors.border || root.foreground
    } catch (e) {}
  }

  function loadStyle(raw) {
    try {
      var style = JSON.parse(raw || "{}")
      root.cornerRadius = Number(style.radius || 0)
    } catch (e) {}
  }

  ListModel { id: displayModel }

  Process {
    id: providerProc
    property string menuId: ""
    property string output: ""
    stdout: SplitParser {
      onRead: function(data) {
        providerProc.output += data + "\n"
      }
    }
    onExited: {
      root.mergeProviderJson(output, menuId)
      if (root.filterText.trim()) root.loadProvidersForSearch()
      root.startNextProvider()
    }
  }

  SocketServer {
    active: true
    path: root.socketPath

    handler: Socket {
      id: clientSocket
      parser: SplitParser {
        onRead: function(message) {
          var fields = message.split("\t")
          root.closeMenu(fields[3] || "")
          clientSocket.connected = false
        }
      }
    }
  }

  FileView {
    path: root.startupMenuJsonFile
    onLoaded: root.openMenu(text(), root.startupInitialMenu, root.startupSelectionFile, root.startupDoneFile, root.decodeField(root.startupColorsRaw))
  }

  FileView {
    path: root.colorsFile
    watchChanges: true
    onLoaded: root.loadColors(text())
    onFileChanged: { reload(); root.loadColors(text()) }
  }

  FileView {
    path: root.styleFile
    watchChanges: true
    onLoaded: root.loadStyle(text())
    onFileChanged: { reload(); root.loadStyle(text()) }
  }

  Process {
    id: applyProc
    onExited: {
      if (root.applySerial === root.requestSerial) root.opened = false
    }
  }

  Process {
    id: releaseProc
    onExited: root.releaseNextDoneFile()
  }

  PanelWindow {
    id: panel
    visible: root.opened && root.rowsLoaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    Rectangle {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      border.color: root.withAlpha(root.border, 0.36)
      border.width: 1

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.cancel()
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            if (root.filterText.length > 0) root.setFilter(root.filterText.slice(0, -1))
            else root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            if (!root.filterText) root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            root.activateIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.margins: root.contentMargin
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"
          border.width: 0

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || ((root.item(root.activeMenu) ? root.item(root.activeMenu).label : "Go") + "…")
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: 16
            elide: Text.ElideRight
          }

        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            section.property: "section"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              required property string section

              width: ListView.view.width
              height: section === "drilldown" ? root.dividerHeight : 0
              visible: section === "drilldown"

              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: root.withAlpha(root.foreground, 0.2)
              }
            }

            delegate: Rectangle {
              id: row
              required property int index
              required property string itemId
              required property string kind
              required property string icon
              required property string label
              required property string target
              required property string detail
              required property string path
              required property string action
              required property int childCount

              width: ListView.view.width
              height: root.rowHeightForDetail(row.detail)
              radius: root.cornerRadius
              color: index === root.selectedIndex ? root.withAlpha(root.foreground, 0.08) : root.withAlpha(root.foreground, mouseArea.containsMouse ? 0.045 : 0)
              border.color: "transparent"
              border.width: 0

              Rectangle {
                visible: false
                width: 4
                height: parent.height - 18
                radius: Math.min(root.cornerRadius, 4)
                color: root.accent
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: iconText
                text: row.icon
                color: index === root.selectedIndex ? root.accent : root.foreground
                opacity: row.kind === "back" ? 0.7 : 1
                font.family: root.fontFamily
                font.pixelSize: 18
                width: 36
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Column {
                id: contentColumn
                anchors.left: iconText.right
                anchors.leftMargin: 6
                anchors.right: trail.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                  id: labelText
                  width: parent.width
                  text: row.label
                  color: index === root.selectedIndex ? root.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: 16
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: row.detail
                  visible: root.filterText && row.detail.length > 0
                  color: root.foreground
                  opacity: 0.52
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  elide: Text.ElideRight
                }
              }

              Row {
                id: trail
                width: 14
                anchors.right: parent.right
                anchors.rightMargin: 8
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
                spacing: 0

                Text {
                  visible: false
                  text: row.childCount
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: row.kind === "menu" || row.kind === "link" ? "›" : (row.kind === "back" ? "" : "↵")
                  color: index === root.selectedIndex ? root.accent : root.foreground
                  opacity: row.kind === "back" ? 0 : 0.36
                  font.family: root.fontFamily
                  font.pixelSize: 16
                  font.weight: Font.Normal
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activateIndex(row.index)
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: 8
            visible: displayModel.count === 0

            Text {
              text: "󰈉"
              color: root.accent
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: 28
              horizontalAlignment: Text.AlignHCenter
              width: 320
            }

            Text {
              text: root.filterText ? "No matches for “" + root.filterText + "”" : "Nothing here yet"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: 14
              horizontalAlignment: Text.AlignHCenter
              width: 320
            }
          }
        }

        Item {
          width: parent.width
          height: 0
        }
      }
    }
  }
}
