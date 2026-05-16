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
  property string colorsFile: Quickshell.env("OMARCHY_IMAGE_SELECTOR_COLORS_FILE") || (Quickshell.env("HOME") + "/.config/omarchy/current/theme/quickshell.json")
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
  property string actionKey: ""
  property string actionLabel: ""
  property string actionCommand: ""
  readonly property int defaultNearbyWindow: 16
  property int nearbyWindow: defaultNearbyWindow
  property var doneFilesToRelease: []
  property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID"))) + "/omarchy-image-selector.sock"
  property color accent: "#798186"
  property color background: "#101315"
  property color foreground: "#cacccc"
  property int expandedWidth: 768
  property int expandedHeight: 475
  property int sliceWidth: 108
  property int sliceHeight: 432
  property int sliceSpacing: -30
  property int skewOffset: 28
  // hasAction renders the "+" tile and accepts clicks. hasActionKey is the
  // stricter form that also fires on keypress, so callers can opt in to
  // click-only or click+key. The action tile is a synthetic slot at
  // index === imageArray.length when hasAction is true.
  property bool hasAction: actionCommand !== ""
  property bool hasActionKey: hasAction && actionKey !== ""
  // When the selected card is within autoLoadThreshold of imageArray.length
  // the action command auto-fires to fetch the next batch. ~24 = one page
  // of wallhaven results so the fetch starts about a page before the user
  // would actually run out, hiding the network roundtrip. Only kicks in
  // after the first manual action click (the "+" tile), so the bare theme
  // list never auto-grows.
  property int autoLoadThreshold: 24
  property bool autoLoadActive: false
  readonly property int totalCount: imageArray.length + (hasAction ? 1 : 0)
  property int bottomChromeHeight: (showLabels ? (filterable ? 104 : 74) : (filterable ? 60 : 30)) + (hasActionKey ? 22 : 0)

  function fileUrl(path) {
    if (!path) return ""
    // Pass remote URLs through unchanged so Qt can stream them via QNetwork.
    // This lets the wallhaven flow drop the local-cache step entirely and
    // load thumbs straight from wallhaven's CDN as cards enter the nearby
    // window.
    if (path.indexOf("http://") === 0 || path.indexOf("https://") === 0)
      return path
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

  function isActionIndex(index) {
    return hasAction && index === imageArray.length
  }

  function currentPath() {
    if (totalCount === 0 || !itemMatches(selectedIndex)) return ""
    if (isActionIndex(selectedIndex)) return ""
    return imageArray[selectedIndex].filePath
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
    if (index < 0 || index >= totalCount) return false
    if (isActionIndex(index)) return true
    if (!filterText) return true

    var path = imageArray[index].filePath
    var needle = filterText.toLowerCase()
    return nameForPath(path).toLowerCase().indexOf(needle) !== -1 || labelForPath(path).toLowerCase().indexOf(needle) !== -1
  }

  function matchingCount() {
    if (!filterText) return totalCount

    var count = 0
    for (var i = 0; i < totalCount; i++) {
      if (itemMatches(i)) count++
    }

    return count
  }

  function firstMatchingIndex() {
    for (var i = 0; i < totalCount; i++) {
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
    if (totalCount === 0) return
    if (index < 0) index = 0
    else if (index >= totalCount) index = totalCount - 1
    if (!itemMatches(index)) return
    if (index === selectedIndex && immediate !== true) return

    selectedIndex = index
    maybeAutoFetch()
  }

  function selectAdjacent(direction) {
    var count = totalCount
    if (count === 0) return

    var index = selectedIndex
    for (var i = 0; i < count; i++) {
      index = (index + direction + count) % count
      if (itemMatches(index)) {
        select(index)
        return
      }
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
    if (isActionIndex(selectedIndex)) {
      triggerAction()
      return
    }

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

  function parseRows(rows, seen) {
    var newImages = []
    var paths = rows.split("\n")
    for (var i = 0; i < paths.length; i++) {
      var row = paths[i]
      if (!row) continue

      var columns = row.split("\t")
      var path = columns[0]
      if (!path) continue
      if (seen[path]) continue
      seen[path] = true
      var fileName = path.split("/").pop()
      var palette = columns[2] ? columns[2].split(",").filter(function(c) { return c }) : []
      newImages.push({
        filePath: path,
        fileName: fileName,
        thumbnailPath: columns[1] || path,
        palette: palette
      })
    }
    return newImages
  }

  function loadRows(rows) {
    var seen = {}
    root.imageArray = parseRows(rows, seen)
    root.select(root.selectedImageIndex(), true)
    root.imagesLoaded = true
    root.opened = true
    carousel.forceActiveFocus()
  }

  // Append rows to the running carousel. Dedups by filePath so re-firing the
  // action does not pile up duplicate entries. Used by the wallhaven flow to
  // splice its results in after the theme thumbnails without closing.
  function appendRows(rows) {
    var seen = {}
    for (var i = 0; i < imageArray.length; i++) {
      seen[imageArray[i].filePath] = true
    }
    var added = parseRows(rows, seen)
    if (added.length === 0) return
    root.imageArray = imageArray.concat(added)
    carousel.forceActiveFocus()
    // The user may have scrolled past the threshold while the fetch was in
    // flight; re-evaluate so the next batch starts immediately if needed.
    maybeAutoFetch()
  }

  // Open the carousel with the given options. opts is a plain JS object so
  // call sites name what they pass instead of aligning a long positional
  // list; everything is optional and falls back to sensible defaults.
  function openSelector(opts) {
    var o = opts || {}
    var nextDoneFile = o.doneFile || ""

    if (requestActive && doneFile && doneFile !== nextDoneFile)
      finishDoneFile(doneFile)

    requestSerial += 1

    imageDirs = o.imageDirs || ""
    imageRows = o.imageRows || ""
    selectedImage = o.selectedImage || ""
    selectionFile = o.selectionFile || ""
    doneFile = nextDoneFile
    requestActive = !!doneFile
    showLabels = o.showLabels === true || o.showLabels === "true"
    filterable = o.filterable === true || o.filterable === "true"
    filterText = ""
    actionKey = o.actionKey || ""
    actionLabel = o.actionLabel || ""
    actionCommand = o.actionCommand || ""
    autoLoadActive = false
    var parsedNearby = parseInt(o.nearbyWindow)
    nearbyWindow = (parsedNearby > 0) ? parsedNearby : defaultNearbyWindow
    colorsFile = o.colorsFile || (Quickshell.env("HOME") + "/.config/omarchy/current/theme/quickshell.json")
    if (o.colorsRaw)
      loadColors(o.colorsRaw)
    imageArray = []
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

  // Fires the configured action command and keeps the carousel open. The
  // command is expected to send an op=append socket message that splices new
  // rows into the running carousel. Debounced via actionProc.running so
  // navigating near the end doesn't spam concurrent fetches.
  //
  // actionCommand is split on whitespace and exec'd directly (no shell), so
  // the IPC payload can't smuggle shell metacharacters through the bash -c
  // surface that a previous version used.
  function triggerAction() {
    if (!hasAction || actionProc.running) return

    var argv = actionCommand.split(/\s+/).filter(function(s) { return s.length > 0 })
    if (argv.length === 0) return

    autoLoadActive = true
    actionProc.command = argv
    actionProc.running = true
  }

  function maybeAutoFetch() {
    if (!autoLoadActive || actionProc.running) return
    if (imageArray.length === 0) return
    if (selectedIndex >= imageArray.length - autoLoadThreshold) {
      triggerAction()
    }
  }

  property var imageArray: []

  function selectedImageIndex() {
    for (var i = 0; i < imageArray.length; i++) {
      if (imageArray[i].filePath === selectedImage)
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
      openSelector({
        imageDirs: imageDirs,
        selectedImage: selectedImage,
        selectionFile: selectionFile,
        doneFile: Quickshell.env("OMARCHY_IMAGE_SELECTOR_DONE_FILE"),
        colorsFile: colorsFile
      })
  }

  IpcHandler {
    target: "image-selector"

    function open(imageDirs: string, imageRows: string, selectedImage: string, selectionFile: string, doneFile: string, colorsFile: string): void {
      root.openSelector({
        imageDirs: imageDirs,
        imageRows: imageRows,
        selectedImage: selectedImage,
        selectionFile: selectionFile,
        doneFile: doneFile,
        colorsFile: colorsFile
      })
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
          var op = fields[11] || "open"

          if (op === "append" && root.opened) {
            root.appendRows(root.decodeField(fields[0]))
            clientSocket.connected = false
            return
          }

          if (root.opened) {
            root.closeSelector(fields[3] || "")
            clientSocket.connected = false
            return
          }

          root.openSelector({
            imageRows: root.decodeField(fields[0]),
            selectedImage: fields[1] || "",
            selectionFile: fields[2] || "",
            doneFile: fields[3] || "",
            colorsRaw: root.decodeField(fields[4]),
            showLabels: fields[5] || "false",
            filterable: fields[6] || "false",
            actionKey: fields[7] || "",
            actionLabel: fields[8] || "",
            actionCommand: root.decodeField(fields[9]),
            nearbyWindow: fields[10] || ""
          })
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

  Process {
    id: actionProc
    // Disarm auto-fetch on a failed action so we don't spin re-firing
    // a broken command every arrow press. The user can still re-arm by
    // clicking the "+" tile manually.
    onExited: (code) => {
      if (code !== 0) root.autoLoadActive = false
    }
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
      height: root.expandedHeight + 30 + root.bottomChromeHeight
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
          } else if (root.hasActionKey && event.text && event.text.toLowerCase() === root.actionKey.toLowerCase() && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            // Action key takes precedence over filter typing so the bound key
            // can't be "captured" by an active filter session.
            root.triggerAction()
            event.accepted = true
          } else if (root.filterable && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.updateFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        Component.onCompleted: forceActiveFocus()

        Repeater {
          model: root.totalCount

          delegate: Item {
            id: item
            required property int index

            readonly property bool isAction: root.isActionIndex(index)
            readonly property var imageData: isAction ? null : root.imageArray[index]
            readonly property string filePath: imageData ? imageData.filePath : ""
            readonly property string fileName: imageData ? imageData.fileName : ""
            readonly property string thumbnailPath: imageData ? imageData.thumbnailPath : ""
            readonly property var palette: imageData && imageData.palette ? imageData.palette : []
            readonly property real swatchAreaWidth: selected ? width - 24 : width

            readonly property bool matched: root.itemMatches(index)
            readonly property int relativeIndex: root.filteredPosition(index) - root.selectedFilteredPosition()
            readonly property bool selected: matched && index === root.selectedIndex
            readonly property bool nearby: matched && Math.abs(relativeIndex) <= root.nearbyWindow

            visible: nearby
            x: selected ? carousel.previewX : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep : carousel.previewX + root.expandedWidth + root.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
            width: selected ? root.expandedWidth : root.sliceWidth
            height: selected ? root.expandedHeight : root.sliceHeight
            y: selected ? 0 : (root.expandedHeight - root.sliceHeight) / 2
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
                asynchronous: true
                cache: true
                smooth: true
              }

              // High-quality overlay. Loads for the 3 cards on either side of
              // the active one and stays painted on all of them so scrolling
              // never visibly swaps thumb -> full as cards become active.
              //
              // For local-file callers filePath == thumbnailPath so source
              // stays empty and this overlay never activates.
              Image {
                id: imageFull
                anchors.fill: parent
                source: (item.nearby && Math.abs(item.relativeIndex) <= 3
                         && item.filePath && item.filePath !== item.thumbnailPath)
                  ? root.fileUrl(item.filePath) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                // Cap decoded size so a 5120x1440 wallpaper doesn't pin
                // 30MB of pixmap memory per visited card.
                sourceSize.width: 1600
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
              }

              Rectangle {
                anchors.fill: parent
                color: root.withAlpha(root.background, item.selected ? 0 : 0.42)
              }

              // Wallhaven palette strip. Taller on the active card, slim on
              // neighbours. Model is empty for off-nearby cards so the
              // Repeater doesn't instantiate Rectangles for cards the user
              // can't see.
              Row {
                visible: item.palette.length > 0 && !item.isAction
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottomMargin: item.selected ? 8 : 0
                anchors.leftMargin: item.selected ? 12 : 0
                anchors.rightMargin: item.selected ? 12 : 0
                height: item.selected ? 22 : 6
                spacing: 0

                Repeater {
                  model: item.nearby ? item.palette : []
                  delegate: Rectangle {
                    required property string modelData
                    width: item.swatchAreaWidth / item.palette.length
                    height: parent.height
                    color: modelData
                  }
                }
              }

              Rectangle {
                anchors.fill: parent
                visible: item.isAction
                color: root.withAlpha(root.background, item.selected ? 0.55 : 0.78)

                Text {
                  anchors.centerIn: parent
                  text: "+"
                  color: item.selected ? root.accent : root.foreground
                  font.pixelSize: item.selected ? 200 : 80
                  font.weight: Font.Light
                  Behavior on font.pixelSize { NumberAnimation { duration: 160 } }
                }

                Text {
                  visible: item.selected && root.actionLabel
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: 32
                  text: root.actionLabel
                  color: root.withAlpha(root.foreground, 0.75)
                  font.pixelSize: 16
                  font.family: "monospace"
                }
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
        id: filterDisplay
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

      Text {
        visible: root.hasActionKey
        anchors.top: filterDisplay.visible ? filterDisplay.bottom : (selectedLabel.visible ? selectedLabel.bottom : carousel.bottom)
        anchors.topMargin: 8
        anchors.horizontalCenter: carousel.horizontalCenter
        width: root.expandedWidth
        text: "press " + root.actionKey + " " + (root.actionLabel || "for action")
        color: root.foreground
        opacity: 0.6
        style: Text.Outline
        styleColor: root.withAlpha(root.background, 0.7)
        font.pixelSize: 12
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }
  }
}
