import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

ShellRoot {
  id: root

  property string imageDirs: Quickshell.env("OMARCHY_IMAGE_SELECTOR_DIRS") || Quickshell.env("OMARCHY_IMAGE_SELECTOR_DIR") || Quickshell.env("OMARCHY_STOCK_BACKGROUNDS_DIR") || (Quickshell.env("HOME") + "/.config/omarchy/current/theme/backgrounds")
  property string imageRows: ""
  property string selectionFile: Quickshell.env("OMARCHY_IMAGE_SELECTOR_SELECTION_FILE") || Quickshell.env("OMARCHY_BACKGROUND_SELECTION_FILE")
  property string selectedImage: Quickshell.env("OMARCHY_IMAGE_SELECTOR_SELECTED")
  property string colorsFile: Quickshell.env("OMARCHY_IMAGE_SELECTOR_COLORS_FILE") || (Quickshell.env("HOME") + "/.config/omarchy/current/theme/background-switcher-colors.json")
  property int selectedIndex: 0
  property bool imagesLoaded: false
  property bool opened: false
  property bool showLabels: false
  property bool filterable: false
  property bool requestActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property string doneFile: ""
  property string filterText: ""
  property var doneFilesToRelease: []
  property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID"))) + "/omarchy-image-selector.sock"
  property color accent: "#798186"
  property color background: "#101315"
  property color foreground: "#cacccc"
  property int expandedWidth: 768
  property int sliceWidth: 108
  property int sliceHeight: 432
  property int sliceSpacing: -30
  property int skewOffset: 28
  property int bottomChromeHeight: showLabels ? (filterable ? 104 : 74) : (filterable ? 60 : 30)

  function fileUrl(path) {
    return "file://" + path.split("/").map(encodeURIComponent).join("/")
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function decodeField(value) {
    return String(value || "").replace(/\v/g, "\n").replace(/\f/g, "\t")
  }

  function withAlpha(color, alpha) {
    return Qt.rgba(color.r, color.g, color.b, alpha)
  }

  function currentPath() {
    if (imageModel.count === 0 || !itemMatches(selectedIndex)) return ""
    return imageModel.get(selectedIndex).filePath
  }

  function nameForPath(path) {
    return path.split("/").pop().replace(/\.[^/.]+$/, "")
  }

  function labelForPath(path) {
    return nameForPath(path).replace(/[-_]+/g, " ").replace(/\b\w/g, function(match) { return match.toUpperCase() })
  }

  function currentLabel() {
    var path = currentPath()
    if (!path) return filterText ? "No matches" : ""

    return labelForPath(path)
  }

  function itemMatches(index) {
    if (index < 0 || index >= imageModel.count) return false
    if (!filterText) return true

    var path = imageModel.get(index).filePath
    var needle = filterText.toLowerCase()
    return nameForPath(path).toLowerCase().indexOf(needle) !== -1 || labelForPath(path).toLowerCase().indexOf(needle) !== -1
  }

  function matchingCount() {
    if (!filterText) return imageModel.count

    var count = 0
    for (var i = 0; i < imageModel.count; i++) {
      if (itemMatches(i)) count++
    }

    return count
  }

  function firstMatchingIndex() {
    for (var i = 0; i < imageModel.count; i++) {
      if (itemMatches(i)) return i
    }

    return -1
  }

  function filteredPosition(index) {
    if (!filterText) return index

    var position = 0
    for (var i = 0; i < index; i++) {
      if (itemMatches(i)) position++
    }

    return position
  }

  function selectedFilteredPosition() {
    if (!filterText) return selectedIndex

    return itemMatches(selectedIndex) ? filteredPosition(selectedIndex) : 0
  }

  function select(index, immediate) {
    if (imageModel.count === 0) return
    if (index < 0) index = 0
    else if (index >= imageModel.count) index = imageModel.count - 1
    if (!itemMatches(index)) return
    if (index === selectedIndex && immediate !== true) return

    selectedIndex = index
  }

  function selectAdjacent(direction) {
    if (!filterText) {
      select(selectedIndex + direction)
      return
    }

    var index = selectedIndex + direction
    while (index >= 0 && index < imageModel.count) {
      if (itemMatches(index)) {
        select(index)
        return
      }

      index += direction
    }
  }

  function updateFilter(nextFilterText) {
    filterText = nextFilterText

    if (!itemMatches(selectedIndex)) {
      var first = firstMatchingIndex()
      if (first >= 0) selectedIndex = first
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

  function applySelected() {
    var path = currentPath()
    if (!path || !selectionFile) {
      cancel()
      return
    }

    var activeSelectionFile = selectionFile
    var activeDoneFile = doneFile
    applySerial = requestSerial
    requestActive = false
    selectionFile = ""
    doneFile = ""

    applyProc.command = ["bash", "-lc", "printf '%s\\n' " + shellQuote(path) + " > " + shellQuote(activeSelectionFile) + "; : > " + shellQuote(activeDoneFile)]
    applyProc.running = true
  }

  function cancel() {
    if (requestActive)
      finishDoneFile(doneFile)

    requestActive = false
    selectionFile = ""
    doneFile = ""
    root.opened = false
  }

  function closeSelector(nextDoneFile) {
    requestSerial += 1

    if (requestActive)
      finishDoneFile(doneFile)

    if (nextDoneFile && nextDoneFile !== doneFile)
      finishDoneFile(nextDoneFile)

    requestActive = false
    selectionFile = ""
    doneFile = ""
    filterText = ""
    root.opened = false
  }

  function loadRows(rows) {
    var paths = rows.split("\n")
    for (var i = 0; i < paths.length; i++) {
      var row = paths[i]
      if (!row) continue

      var columns = row.split("\t")
      root.addImage(columns[0], columns[1])
    }

    root.select(root.selectedImageIndex(), true)
    root.imagesLoaded = true
    root.opened = true
    carousel.forceActiveFocus()
  }

  function openSelector(nextImageDirs, nextImageRows, nextSelectedImage, nextSelectionFile, nextDoneFile, nextColorsFile, nextColorsRaw, nextShowLabels, nextFilterable) {
    if (requestActive && doneFile && doneFile !== nextDoneFile)
      finishDoneFile(doneFile)

    requestSerial += 1

    imageDirs = nextImageDirs
    imageRows = nextImageRows
    selectedImage = nextSelectedImage
    selectionFile = nextSelectionFile
    doneFile = nextDoneFile
    requestActive = !!doneFile
    showLabels = nextShowLabels === true || nextShowLabels === "true"
    filterable = nextFilterable === true || nextFilterable === "true"
    filterText = ""
    colorsFile = nextColorsFile || (Quickshell.env("HOME") + "/.config/omarchy/current/theme/background-switcher-colors.json")
    if (nextColorsRaw)
      loadColors(nextColorsRaw)
    imageModel.clear()
    selectedIndex = 0
    imagesLoaded = false
    opened = false
    if (imageRows) {
      loadRows(imageRows)
    } else {
      loadImagesProc.output = ""
      loadImagesProc.running = true
    }
  }

  ListModel { id: imageModel }

  function addImage(path, thumbnailPath) {
    if (!path) return
    var fileName = path.split("/").pop()

    for (var i = imageModel.count - 1; i >= 0; i--) {
      if (imageModel.get(i).fileName === fileName)
        imageModel.remove(i)
    }

    imageModel.append({ filePath: path, fileName: fileName, thumbnailPath: thumbnailPath || path })
  }

  function selectedImageIndex() {
    for (var i = 0; i < imageModel.count; i++) {
      if (imageModel.get(i).filePath === selectedImage)
        return i
    }

    return 0
  }

  Process {
    id: loadImagesProc
    property string output: ""
    command: ["bash", "-lc", "cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/image-selector; while IFS= read -r dir; do [[ -n $dir && -d $dir ]] && find -L \"$dir\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \\) -print0; done <<< " + shellQuote(root.imageDirs) + " | sort -z | while IFS= read -r -d '' image; do hash=$(md5sum \"$image\" | cut -d ' ' -f 1); thumb=\"$cache_dir/$hash.jpg\"; [[ -f $thumb ]] || thumb=$image; printf '%s\\t%s\\n' \"$image\" \"$thumb\"; done"]
    stdout: SplitParser {
      onRead: function(data) {
        loadImagesProc.output += data + "\n"
      }
    }
    onExited: {
      root.loadRows(output)
    }
  }

  Component.onCompleted: {
    if (selectionFile)
      openSelector(imageDirs, "", selectedImage, selectionFile, Quickshell.env("OMARCHY_IMAGE_SELECTOR_DONE_FILE"), colorsFile, "", false, false)
  }

  IpcHandler {
    target: "image-selector"

    function open(imageDirs: string, imageRows: string, selectedImage: string, selectionFile: string, doneFile: string, colorsFile: string): void {
      root.openSelector(imageDirs, imageRows, selectedImage, selectionFile, doneFile, colorsFile, "", false, false)
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
          if (root.opened) {
            root.closeSelector(fields[3] || "")
            clientSocket.connected = false
            return
          }

          root.openSelector("", root.decodeField(fields[0]), fields[1] || "", fields[2] || "", fields[3] || "", "", root.decodeField(fields[4]), fields[5] || "false", fields[6] || "false")
          clientSocket.connected = false
        }
      }
    }
  }

  FileView {
    path: root.colorsFile
    watchChanges: true
    onLoaded: root.loadColors(text())
    onFileChanged: { reload(); root.loadColors(text()) }
  }

  function loadColors(raw) {
    try {
      var colors = JSON.parse(raw || "{}")
      root.accent = colors.primary || root.accent
      root.background = colors.background || root.background
      root.foreground = colors.backgroundText || root.foreground
    } catch (e) {}
  }

  Process {
    id: applyProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  Process {
    id: releaseProc
    onExited: root.releaseNextDoneFile()
  }

  PanelWindow {
    id: panel
    visible: root.opened && root.imagesLoaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-image-selector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.withAlpha(root.background, 0.72)
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    Item {
      id: card
      width: Math.min(parent.width - 80, root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing) + 40)
      height: root.sliceHeight + 30 + root.bottomChromeHeight
      anchors.centerIn: parent

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: carousel
        anchors.top: parent.top
        anchors.topMargin: 30
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.bottomChromeHeight
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing)
        clip: false
        focus: true

        readonly property real itemStep: root.sliceWidth + root.sliceSpacing
        readonly property real previewX: (width - root.expandedWidth) / 2

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) {
              root.updateFilter("")
            } else {
              root.cancel()
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.applySelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace && root.filterable) {
            if (root.filterText.length > 0)
              root.updateFilter(root.filterText.slice(0, -1))
            event.accepted = true
          } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab) {
            root.selectAdjacent(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
            root.selectAdjacent(1)
            event.accepted = true
          } else if (root.filterable && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.updateFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        Component.onCompleted: forceActiveFocus()

        Repeater {
          model: imageModel

          delegate: Item {
            id: item
            required property int index
            required property string filePath
            required property string fileName
            required property string thumbnailPath

            readonly property bool matched: root.itemMatches(index)
            readonly property int relativeIndex: root.filteredPosition(index) - root.selectedFilteredPosition()
            readonly property bool selected: matched && index === root.selectedIndex
            readonly property bool nearby: matched && Math.abs(relativeIndex) <= 16

            visible: nearby
            x: selected ? carousel.previewX : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep : carousel.previewX + root.expandedWidth + root.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
            width: selected ? root.expandedWidth : root.sliceWidth
            height: carousel.height
            z: selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40)

            readonly property real skAbs: Math.abs(root.skewOffset)
            readonly property real topLeft: root.skewOffset >= 0 ? skAbs : 0
            readonly property real topRight: root.skewOffset >= 0 ? width : width - skAbs
            readonly property real bottomRight: root.skewOffset >= 0 ? width - skAbs : width
            readonly property real bottomLeft: root.skewOffset >= 0 ? 0 : skAbs

            Item {
              id: maskShape
              anchors.fill: parent
              visible: false
              layer.enabled: true

              Shape {
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                  fillColor: "white"
                  strokeColor: "transparent"
                  startX: item.topLeft; startY: 0
                  PathLine { x: item.topRight; y: 0 }
                  PathLine { x: item.bottomRight; y: item.height }
                  PathLine { x: item.bottomLeft; y: item.height }
                  PathLine { x: item.topLeft; y: 0 }
                }
              }
            }

            Shape {
              x: item.selected ? 4 : 2
              y: item.selected ? 10 : 5
              width: item.width
              height: item.height
              opacity: item.selected ? 0.5 : 0.32
              antialiasing: true
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                fillColor: root.background
                strokeColor: "transparent"
                startX: item.topLeft; startY: 0
                PathLine { x: item.topRight; y: 0 }
                PathLine { x: item.bottomRight; y: item.height }
                PathLine { x: item.bottomLeft; y: item.height }
                PathLine { x: item.topLeft; y: 0 }
              }
            }

            Item {
              anchors.fill: parent
              layer.enabled: true
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: maskShape
                maskThresholdMin: 0.3
                maskSpreadAtMin: 0.3
              }

              Image {
                id: image
                anchors.fill: parent
                source: item.nearby ? root.fileUrl(item.thumbnailPath) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                cache: true
                smooth: true
              }

              Rectangle {
                anchors.fill: parent
                color: root.withAlpha(root.background, item.selected ? 0 : 0.42)
                Behavior on color { ColorAnimation { duration: 120 } }
              }
            }

            Shape {
              anchors.fill: parent
              antialiasing: true
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                fillColor: "transparent"
                strokeColor: item.selected ? root.accent : root.withAlpha(root.foreground, 0.28)
                strokeWidth: item.selected ? 3 : 1
                startX: item.topLeft; startY: 0
                PathLine { x: item.topRight; y: 0 }
                PathLine { x: item.bottomRight; y: item.height }
                PathLine { x: item.bottomLeft; y: item.height }
                PathLine { x: item.topLeft; y: 0 }
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: item.selected ? root.applySelected() : root.select(index)
            }
          }
        }
      }

      Text {
        id: selectedLabel
        visible: root.showLabels
        anchors.top: carousel.bottom
        anchors.topMargin: 16
        anchors.horizontalCenter: carousel.horizontalCenter
        width: root.expandedWidth
        text: root.currentLabel()
        color: root.foreground
        style: Text.Outline
        styleColor: root.withAlpha(root.background, 0.7)
        font.pixelSize: 24
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Text {
        visible: root.filterable && root.filterText
        anchors.top: selectedLabel.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: carousel.horizontalCenter
        width: root.expandedWidth
        text: root.filterText
        color: root.foreground
        opacity: 0.85
        style: Text.Outline
        styleColor: root.withAlpha(root.background, 0.7)
        font.pixelSize: 14
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }
  }
}
