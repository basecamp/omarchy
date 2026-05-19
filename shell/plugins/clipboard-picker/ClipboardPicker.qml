import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var items: []

  property color accent: Color.menu.selected
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: foreground
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Quickshell.env("OMARCHY_MENU_FONT") || "monospace"
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(800), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(600), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(50), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = false
    
    // Trigger fetch
    fetchProc.collected = ""
    fetchProc.command = ["bash", "-lc", "elephant query --json 'clipboard;;100'"]
    fetchProc.running = true

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

  function rebuildDisplay() {
    var query = root.filterText.trim().toLowerCase()
    
    displayModel.clear()
    var outCount = 0
    
    for (var i = 0; i < root.items.length; i++) {
      var entry = root.items[i]
      var isPassword = (entry.meta === "password" || entry.preview_type === "password")
      
      var textMatch = false
      if (isPassword) {
        textMatch = false // Passwords shouldn't match plain text search queries
      } else {
        textMatch = (entry.preview && entry.preview.toLowerCase().indexOf(query) >= 0)
      }
      
      if (!query || textMatch) {
        displayModel.append({
          identifier: entry.identifier,
          previewText: entry.preview_type === "text" ? entry.preview.replace(/\n/g, " ") : "",
          previewImage: entry.preview_type === "file" ? ("file://" + entry.preview) : "",
          previewType: entry.preview_type || "text",
          isPassword: isPassword,
          index: outCount
        })
        outCount++
        if (outCount >= 50) break
      }
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = false
    root.rebuildDisplay()
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.applySelected(row.identifier)
  }

  function applySelected(identifier) {
    if (!identifier) return
    root.opened = false
    var escId = identifier.replace(/'/g, "'\\''")
    Quickshell.execDetached(["bash", "-lc", "elephant activate 'clipboard;" + escId + ";copy;;'; sleep 0.15; wtype -M shift -k Insert -m shift 2>/dev/null || true"])
  }
  ListModel { id: displayModel }

  Process {
    id: fetchProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { fetchProc.collected += data + "\n" }
    }
    onExited: {
      var lines = fetchProc.collected.split("\n")
      var newItems = []
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        try {
          var parsed = JSON.parse(line)
          if (parsed && parsed.item) {
            newItems.push(parsed.item)
          }
        } catch(e) {}
      }
      root.items = newItems
      root.rebuildDisplay()
    }
  }
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-clipboard-picker"
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
      border.width: Math.max(1, Style.space(2))

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
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
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
            text: root.filterText || "Search clipboard…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing

          Row {
            anchors.fill: parent
            spacing: root.contentSpacing

            ListView {
              id: resultList
              width: parent.width / 2 - root.contentSpacing / 2
              height: parent.height
              model: displayModel
              clip: true
              spacing: Style.space(4)
              boundsBehavior: Flickable.StopAtBounds

              delegate: Rectangle {
                required property int index
                required property string identifier
                required property string previewText
                required property string previewType
                required property bool isPassword

                readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

                width: ListView.view.width
                height: root.rowHeight
                radius: root.cornerRadius
                color: hasCursor ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
                border.color: hasCursor ? Style.hoverBorderFor(root.foreground, root.accent) : "transparent"
                border.width: hasCursor ? Style.hoverBorderWidth : 0

                Rectangle {
                  visible: false
                  width: Style.space(4)
                  height: parent.height - Style.space(18)
                  radius: Math.min(root.cornerRadius, Style.space(4))
                  color: root.accent
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  anchors.topMargin: Style.space(8)
                  anchors.bottomMargin: Style.space(8)

                  Text {
                    width: parent.width
                    height: parent.height
                    text: parent.parent.isPassword ? "••••••••" : (parent.parent.previewType === "text" ? parent.parent.previewText : "Image")
                    color: parent.parent.hasCursor ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.italic: parent.parent.previewType === "file" || parent.parent.isPassword
                    opacity: (parent.parent.previewType === "file" || parent.parent.isPassword) ? 0.6 : 1.0
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    verticalAlignment: Text.AlignVCenter
                  }
                }

                MouseArea {
                  id: mouseArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onContainsMouseChanged: if (containsMouse) {
                    root.cursorActive = true
                    root.selectedIndex = index
                  }
                  onClicked: {
                    root.cursorActive = true
                    root.selectedIndex = index
                    root.activateIndex(index)
                  }
                }
              }
            }

            Rectangle {
              width: parent.width / 2 - root.contentSpacing / 2
              height: parent.height
              radius: root.cornerRadius
              color: root.withAlpha(root.background, 0.5)
              border.color: root.withAlpha(root.border, 0.1)
              border.width: Style.normalBorderWidth
              clip: true

              property var activeRow: root.cursorActive && displayModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count ? displayModel.get(root.selectedIndex) : null

              Text {
                visible: parent.activeRow && parent.activeRow.previewType === "text"
                anchors.fill: parent
                anchors.margins: Style.space(16)
                text: parent.activeRow ? (parent.activeRow.isPassword ? "••••••••" : parent.activeRow.previewText) : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
              }

              Image {
                visible: parent.activeRow && parent.activeRow.previewType === "file"
                anchors.fill: parent
                anchors.margins: Style.space(16)
                source: parent.activeRow ? parent.activeRow.previewImage : ""
                fillMode: Image.PreserveAspectFit
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              text: "󰅌"
              color: root.accent
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: root.items.length === 0 ? "Clipboard is empty" : "No matches for “" + root.filterText + "”"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }
      }
    }
  }
}
