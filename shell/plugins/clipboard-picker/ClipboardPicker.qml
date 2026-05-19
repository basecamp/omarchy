import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var history: []

  property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  property string captureScript: root.omarchyPath + "/shell/scripts/clipboard-capture.sh"
  // Shares the [menu] surface tokens — themes that style the menu also
  // style the clipboard picker. Selected-row colors composed in the
  // singleton so consumers drop them straight into Rectangle bindings.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
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

  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  function fileUrl(path) {
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
  }

  function normalizeEntry(value) {
    if (typeof value === "string") {
      return value.length > 0 ? { type: "text", text: value } : null
    }
    if (!value || typeof value !== "object") return null

    var type = String(value.type || value.kind || "")
    if (type === "text") {
      var text = String(value.text || "")
      return text.length > 0 ? { type: "text", text: text } : null
    }
    if (type === "image") {
      var path = String(value.path || "")
      if (!path) return null
      return {
        type: "image",
        path: path,
        mime: String(value.mime || "image/png")
      }
    }
    return null
  }

  function entryKey(entry) {
    if (!entry) return ""
    if (entry.type === "image") return "image:" + String(entry.path || "")
    return "text:" + String(entry.text || "")
  }

  function loadHistory(raw) {
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      var next = []
      if (Array.isArray(parsed)) {
        for (var i = 0; i < parsed.length; i++) {
          var entry = root.normalizeEntry(parsed[i])
          if (entry) next.push(entry)
        }
      }
      root.history = next
    } catch (e) {
      root.history = []
    }
    if (root.opened) root.rebuildDisplay()
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify(root.history.slice(0, 100), null, 2) + "\n")
  }

  function addClipboardEntry(entry) {
    var normalized = root.normalizeEntry(entry)
    if (!normalized) return

    var key = root.entryKey(normalized)
    var next = [normalized]
    for (var i = 0; i < root.history.length && next.length < 100; i++) {
      var existing = root.normalizeEntry(root.history[i])
      if (!existing || root.entryKey(existing) === key) continue
      next.push(existing)
    }
    root.history = next
    root.saveHistory()
    if (root.opened) root.rebuildDisplay()
  }

  function addClipboardJson(line) {
    var raw = String(line || "").trim()
    if (!raw) return
    try { root.addClipboardEntry(JSON.parse(raw)) } catch (e) {}
  }

  function rebuildDisplay() {
    var query = root.filterText.trim().toLowerCase()

    displayModel.clear()
    var outCount = 0

    for (var i = 0; i < root.history.length; i++) {
      var entry = root.normalizeEntry(root.history[i])
      if (!entry) continue

      var isImage = entry.type === "image"
      var searchable = isImage ? ("image " + String(entry.mime || "")) : String(entry.text || "")
      if (query && searchable.toLowerCase().indexOf(query) < 0) continue

      displayModel.append({
        entryType: entry.type,
        fullText: isImage ? "" : String(entry.text || ""),
        previewText: isImage ? "Image" : String(entry.text || "").replace(/\s+/g, " "),
        previewImage: isImage ? root.fileUrl(entry.path) : "",
        path: isImage ? String(entry.path || "") : "",
        mime: isImage ? String(entry.mime || "image/png") : "text/plain",
        index: outCount
      })
      outCount++
      if (outCount >= 50) break
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
    root.applySelected(row)
  }

  function applySelected(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached(["bash", "-lc", "wl-copy --type " + root.shellQuote(row.mime) + " < " + root.shellQuote(row.path) + "; sleep 0.15; wtype -M shift -k Insert -m shift 2>/dev/null || true"])
    } else if (row.fullText) {
      Quickshell.execDetached(["bash", "-lc", "printf %s " + root.shellQuote(row.fullText) + " | wl-copy; sleep 0.15; wtype -M shift -k Insert -m shift 2>/dev/null || true"])
    }
  }

  Component.onCompleted: initProc.running = true

  ListModel { id: displayModel }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]")
    onFileChanged: reload()
  }

  Process {
    id: initProc
    command: ["bash", "-lc", "mkdir -p ~/.local/state/omarchy"]
    onExited: {
      currentProc.command = [root.captureScript]
      currentProc.running = true
      watchProc.command = ["wl-paste", "--watch", root.captureScript]
      watchProc.running = true
    }
  }

  Process {
    id: currentProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addClipboardJson(text)
    }
  }

  Process {
    id: watchProc
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
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
      color: root.scrim
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
                required property string entryType
                required property string previewText
                required property string fullText
                required property string previewImage

                readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

                width: ListView.view.width
                height: root.rowHeight
                radius: root.cornerRadius
                color: hasCursor ? root.selectedBackground : "transparent"
                border.color: hasCursor ? root.selectedBorder : "transparent"
                border.width: (hasCursor && root.selectedBorder.a > 0) ? Style.hoverBorderWidth : 0

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  anchors.topMargin: Style.space(8)
                  anchors.bottomMargin: Style.space(8)
                  spacing: Style.space(10)

                  Image {
                    visible: parent.parent.entryType === "image"
                    width: visible ? parent.height : 0
                    height: parent.height
                    source: parent.parent.previewImage
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                  }

                  Text {
                    width: parent.width - (parent.parent.entryType === "image" ? parent.height + parent.spacing : 0)
                    height: parent.height
                    text: parent.parent.previewText
                    color: parent.parent.hasCursor ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.italic: parent.parent.entryType === "image"
                    opacity: parent.parent.entryType === "image" ? 0.72 : 1.0
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    verticalAlignment: Text.AlignVCenter
                  }
                }

                MouseArea {
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

              property var activeRow: displayModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count ? displayModel.get(root.selectedIndex) : null

              Text {
                visible: parent.activeRow && parent.activeRow.entryType === "text"
                anchors.fill: parent
                anchors.margins: Style.space(16)
                text: parent.activeRow ? parent.activeRow.fullText : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
              }

              Image {
                visible: parent.activeRow && parent.activeRow.entryType === "image"
                anchors.fill: parent
                anchors.margins: Style.space(16)
                source: parent.activeRow ? parent.activeRow.previewImage : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              text: "󰅌"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: root.history.length === 0 ? "Clipboard is empty" : "No matches for “" + root.filterText + "”"
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
