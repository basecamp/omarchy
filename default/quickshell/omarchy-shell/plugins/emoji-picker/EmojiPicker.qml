import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || (Quickshell.env("HOME") + "/.local/share/omarchy")
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property var emojis: []
  property var filteredEmojis: []

  property color accent: Color.menu.selected
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: foreground
  property int cornerRadius: 0
  property string fontFamily: Quickshell.env("OMARCHY_MENU_FONT") || "monospace"
  property string styleFile: Quickshell.env("OMARCHY_MENU_STYLE_FILE") || (Quickshell.env("HOME") + "/.local/state/omarchy/toggles/quickshell-menu.json")

  property int contentMargin: 18
  property int headerHeight: 34
  property int contentSpacing: 6
  property int cardWidth: 400
  property int cardHeight: 500

  property int cellWidth: 44
  property int cellHeight: 44
  property int columns: Math.floor((cardWidth - contentMargin * 2) / cellWidth)

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function withAlpha(color, alpha) {
    return Qt.rgba(color.r, color.g, color.b, alpha)
  }

  function loadEmojis(raw) {
    try {
      var data = JSON.parse(raw)
      root.emojis = data || []
    } catch (e) {
      console.warn("Failed to parse emojis.json:", e)
      root.emojis = []
    }
    if (root.opened) root.rebuildDisplay()
  }

  function rebuildDisplay() {
    var query = root.filterText.trim().toLowerCase()
    var out = []
    for (var i = 0; i < root.emojis.length; i++) {
      var item = root.emojis[i]
      if (!query || item.k.indexOf(query) >= 0) {
        out.push(item)
        if (out.length >= 200) break // limit to keep it fast
      }
    }
    root.filteredEmojis = out

    displayModel.clear()
    for (var j = 0; j < out.length; j++) {
      displayModel.append({ emoji: out[j].e, index: j })
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return
    selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function selectRow(delta) {
    if (displayModel.count === 0) return
    var newIndex = selectedIndex + delta * columns
    if (newIndex < 0) newIndex = 0
    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1
    selectedIndex = newIndex
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.applySelected(row.emoji)
  }

  function applySelected(emoji) {
    if (!emoji) return
    root.opened = false
    var escEmoji = emoji.replace(/'/g, "'\\''")
    Quickshell.execDetached(["bash", "-lc", "wl-copy '" + escEmoji + "'; sleep 0.15; wtype '" + escEmoji + "' 2>/dev/null || true"])
  }

  function loadStyle(raw) {
    try {
      var style = JSON.parse(raw || "{}")
      root.cornerRadius = Number(style.radius || 0)
    } catch (e) {}
  }

  ListModel { id: displayModel }

  IpcHandler {
    target: "emoji-picker"
    function summon(): string { root.open("{}"); return "ok" }
    function hide(): string { root.close(); return "ok" }
    function toggle(): string { root.toggle(); return "ok" }
    function ping(): string { return "ok" }
  }

  FileView {
    path: root.omarchyPath + "/default/quickshell/omarchy-shell/plugins/emoji-picker/emojis.json"
    onLoaded: root.loadEmojis(text())
  }

  FileView {
    path: root.styleFile
    watchChanges: true
    onLoaded: root.loadStyle(text())
    onFileChanged: { reload(); root.loadStyle(text()) }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-emoji-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.withAlpha(root.background, 0.5)
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Rectangle {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      border.color: root.border
      border.width: 2

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            if (root.filterText.length > 0) root.setFilter(root.filterText.slice(0, -1))
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selectRow(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.selectRow(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
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
            text: root.filterText || "Search emojis…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: 16
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing

          GridView {
            id: resultGrid
            anchors.fill: parent
            model: displayModel
            clip: true
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              required property int index
              required property string emoji

              width: root.cellWidth
              height: root.cellHeight
              radius: root.cornerRadius
              color: index === root.selectedIndex ? root.withAlpha(root.foreground, 0.08) : root.withAlpha(root.foreground, mouseArea.containsMouse ? 0.045 : 0)

              Text {
                text: parent.emoji
                font.family: root.fontFamily
                font.pixelSize: 24
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selectedIndex = index
                  root.activateIndex(index)
                }
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
              width: parent.width
            }

            Text {
              text: "No matches for “" + root.filterText + "”"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: 14
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }
      }
    }
  }
}
