import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import qs.Commons

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string placeholder: "\uf002 Search..."
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: true
  property bool hoverArmed: false
  property var filteredEntries: []
  property int launchSerial: 0
  property int launchToplevelCount: 0
  property var launchActiveToplevel: null
  property bool launchOsdOpen: false
  property string launchOsdMessage: ""
  property var hiddenEntryIds: ({})

  // Bound to the central [app-launcher] section in shell.toml via Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: Color.appLauncher.background
  property color foreground: Color.appLauncher.text
  property color border: Color.appLauncher.border
  property color scrim: Color.appLauncher.scrim
  property color selectedBackground: Color.appLauncher.selectedBackground
  property color selectedText: Color.appLauncher.selectedText
  property color selectedBorder: Color.appLauncher.selectedBorder
  property string fontFamily: Quickshell.env("OMARCHY_MENU_FONT") || "monospace"

  property int cardWidth: 644
  property int cardHeight: 400
  property int contentMargin: 20
  property int contentSpacing: 10
  property int searchHeight: 44
  property int rowHeight: 50
  property int iconSlotWidth: 44
  property int iconSize: 24
  readonly property int listHeight: cardHeight - contentMargin * 2 - searchHeight - contentSpacing

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    root.placeholder = payload.placeholder || "\uf002 Search..."
    root.cardWidth = Math.max(300, Number(payload.width || 644))
    var requestedListHeight = Number(payload.listHeight || payload.maxHeight || 0)
    root.cardHeight = requestedListHeight > 0
      ? root.contentMargin * 2 + root.searchHeight + root.contentSpacing + requestedListHeight
      : 400

    root.opened = true
    root.filterText = payload.query || ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.hoverArmed = false
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omarchy.app-launcher")
  }

  function withAlpha(color, alpha) {
    return Qt.rgba(color.r, color.g, color.b, alpha)
  }

  function fileUrl(path) {
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return root.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  function entryName(entry) {
    return String((entry && entry.name) || (entry && entry.id) || "")
  }

  function entrySubtext(entry) {
    return String((entry && entry.genericName) || "")
  }

  function entrySortKey(entry) {
    return root.entryName(entry).toLowerCase()
  }

  function toplevelCount() {
    try { return ToplevelManager.toplevels.values.length } catch (e) { return 0 }
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function entrySearchText(entry) {
    if (!entry) return ""
    var keywords = ""
    try { keywords = (entry.keywords || []).join(" ") } catch (e) { keywords = "" }
    return [entry.name, entry.genericName, entry.comment, keywords, entry.id].join(" ").toLowerCase()
  }

  function isHiddenEntry(entry) {
    var id = String((entry && entry.id) || "")
    return root.hiddenEntryIds[id] === true
  }

  function loadHiddenEntries(rawText) {
    var next = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = lines[i].trim()
      if (id.length > 0) next[id] = true
    }
    root.hiddenEntryIds = next
    if (root.opened) root.rebuildDisplay()
  }

  function hiddenEntryScanCommand() {
    var desktop = [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")].filter(function(v) { return String(v || "").length > 0 }).join(":")
    var script = root.omarchyPath + "/shell/scripts/app-launcher-hidden-entries.sh"
    return root.shellQuote(script) + " " + root.shellQuote(desktop)
  }

  function fuzzyScore(entry, query) {
    var q = String(query || "").trim().toLowerCase()
    if (!q) return 0

    var name = root.entryName(entry).toLowerCase()
    var id = String((entry && entry.id) || "").toLowerCase()
    var haystack = root.entrySearchText(entry)
    var directName = name.indexOf(q)
    var directId = id.indexOf(q)
    if (directName === 0) return 10000 - name.length
    if (directId === 0) return 9500 - id.length
    if (directName > 0) return 8000 - directName * 10 - name.length
    if (directId > 0) return 7600 - directId * 10 - id.length

    var hayIndex = haystack.indexOf(q)
    if (hayIndex >= 0) return 6000 - hayIndex

    var pos = 0
    var first = -1
    var last = -1
    for (var i = 0; i < haystack.length && pos < q.length; i++) {
      if (haystack.charAt(i) !== q.charAt(pos)) continue
      if (first < 0) first = i
      last = i
      pos++
    }
    if (pos !== q.length) return -1
    return 3000 - (last - first) - haystack.length * 0.01
  }

  function sortedEntries(query) {
    var values = DesktopEntries.applications.values || []
    var q = String(query || "").trim()
    var rows = []

    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay || root.isHiddenEntry(entry)) continue
      var name = root.entryName(entry)
      if (!name) continue
      var score = root.fuzzyScore(entry, q)
      if (score < 0) continue
      rows.push({ entry: entry, score: score, key: root.entrySortKey(entry), name: name.toLowerCase() })
    }

    rows.sort(function(a, b) {
      if (q && a.score !== b.score) return b.score - a.score
      if (a.key < b.key) return -1
      if (a.key > b.key) return 1
      if (a.name < b.name) return -1
      if (a.name > b.name) return 1
      return 0
    })

    return rows
  }

  function rebuildDisplay() {
    displayModel.clear()
    var rows = root.sortedEntries(root.filterText)
    var entries = []
    var count = Math.min(rows.length, 256)
    for (var i = 0; i < count; i++) {
      var entry = rows[i].entry
      entries.push(entry)
      displayModel.append({
        name: root.entryName(entry),
        subtext: root.entrySubtext(entry),
        icon: String(entry.icon || "")
      })
    }
    root.filteredEntries = entries

    if (displayModel.count === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= displayModel.count) root.selectedIndex = displayModel.count - 1
    else if (root.selectedIndex < 0) root.selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.cursorActive = true
    root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function activateIndex(index) {
    if (index < 0 || index >= root.filteredEntries.length) return
    var entry = root.filteredEntries[index]
    if (!entry) return
    root.beginLaunchFeedback(entry)
    root.dismiss()
    entry.execute()
  }

  function beginLaunchFeedback(entry) {
    root.launchSerial++
    root.launchToplevelCount = root.toplevelCount()
    root.launchActiveToplevel = ToplevelManager.activeToplevel
    root.launchOsdOpen = false
    root.launchOsdMessage = "Launching " + root.entryName(entry) + "…"
    launchDelay.restart()
    launchTimeout.restart()
  }

  function closeLaunchFeedback(serial) {
    if (serial !== root.launchSerial) return
    launchDelay.stop()
    launchTimeout.stop()
    if (root.launchOsdOpen) {
      Quickshell.execDetached(["omarchy-shell", "osd", "close"])
      root.launchOsdOpen = false
    }
  }

  function maybeFinishLaunchFeedback() {
    if (!launchDelay.running && !launchTimeout.running && !root.launchOsdOpen) return
    if (root.toplevelCount() <= root.launchToplevelCount && ToplevelManager.activeToplevel === root.launchActiveToplevel) return
    root.closeLaunchFeedback(root.launchSerial)
  }

  ListModel { id: displayModel }

  Process {
    id: hiddenEntryScan
    command: ["bash", "-lc", root.hiddenEntryScanCommand()]
    stdout: SplitParser { onRead: function(line) { hiddenEntryOutput.text += line + "\n" } }
    onStarted: hiddenEntryOutput.text = ""
    onExited: root.loadHiddenEntries(hiddenEntryOutput.text)
  }

  QtObject {
    id: hiddenEntryOutput
    property string text: ""
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.maybeFinishLaunchFeedback() }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.maybeFinishLaunchFeedback() }
  }

  Timer {
    id: launchDelay
    interval: 2000
    onTriggered: {
      if (root.toplevelCount() > root.launchToplevelCount || ToplevelManager.activeToplevel !== root.launchActiveToplevel) return
      root.launchOsdOpen = true
      Quickshell.execDetached(["omarchy-shell", "osd", "show", JSON.stringify({ icon: "󱓞", message: root.launchOsdMessage, duration: 0 })])
    }
  }

  Timer {
    id: launchTimeout
    interval: 15000
    onTriggered: root.closeLaunchFeedback(root.launchSerial)
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      hiddenEntryScan.running = true
      if (root.opened) root.rebuildDisplay()
    }
  }

  Component.onCompleted: hiddenEntryScan.running = true

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-app-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Rectangle {
      id: card
      width: Math.min(root.cardWidth, panel.width - Style.gapsOut * 2)
      height: Math.min(root.cardHeight, panel.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      border.color: root.border
      border.width: 2
      clip: true

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText.length > 0) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            if (root.filterText.length > 0) root.setFilter(root.filterText.slice(0, -1))
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
          } else if (event.key === Qt.Key_Home) {
            if (displayModel.count > 0) {
              root.cursorActive = true
              root.selectedIndex = 0
              resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
            }
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            if (displayModel.count > 0) {
              root.cursorActive = true
              root.selectedIndex = displayModel.count - 1
              resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
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
          height: root.searchHeight
          radius: 0
          color: root.background

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || root.placeholder
            color: root.foreground
            opacity: root.filterText ? 1 : 0.5
            font.family: root.fontFamily
            font.pixelSize: 18
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.searchHeight - root.contentSpacing

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: row
              required property int index
              required property string name
              required property string subtext
              required property string icon

              readonly property bool hasCursor: root.cursorActive && row.index === root.selectedIndex

              width: ListView.view.width
              height: root.rowHeight
              radius: 0
              color: row.hasCursor ? root.selectedBackground : "transparent"
              border.color: row.hasCursor ? root.selectedBorder : "transparent"
              border.width: (row.hasCursor && root.selectedBorder.a > 0) ? Math.max(1, Style.normalBorderWidth) : 0

              Item {
                id: iconSlot
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: root.iconSlotWidth
                height: parent.height

                IconImage {
                  id: appIcon
                  anchors.centerIn: parent
                  implicitSize: root.iconSize
                  width: root.iconSize
                  height: root.iconSize
                  source: root.iconSource(row.icon)
                  asynchronous: true
                  mipmap: true
                }

                Text {
                  anchors.centerIn: parent
                  visible: appIcon.status === Image.Error
                  text: "?"
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: 18
                }
              }

              Text {
                anchors.left: iconSlot.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: row.name
                color: row.hasCursor ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: 18
                elide: Text.ElideRight
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) {
                  root.hoverArmed = true
                  root.cursorActive = true
                  root.selectedIndex = row.index
                }
                onContainsMouseChanged: if (containsMouse && root.hoverArmed) {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index)
                }
              }
            }
          }

          Text {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.leftMargin: 14
            visible: displayModel.count === 0
            text: "No Results"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 18
          }
        }
      }
    }
  }
}
