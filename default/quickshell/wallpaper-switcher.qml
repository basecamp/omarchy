import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

ShellRoot {
  id: root

  property string imageDirs: Quickshell.env("OMARCHY_IMAGE_SELECTOR_DIRS") || Quickshell.env("OMARCHY_IMAGE_SELECTOR_DIR") || Quickshell.env("OMARCHY_STOCK_BACKGROUNDS_DIR") || (Quickshell.env("HOME") + "/.config/omarchy/current/theme/backgrounds")
  property string selectionFile: Quickshell.env("OMARCHY_IMAGE_SELECTOR_SELECTION_FILE") || Quickshell.env("OMARCHY_WALLPAPER_SELECTION_FILE")
  property string selectedImage: Quickshell.env("OMARCHY_IMAGE_SELECTOR_SELECTED")
  property string colorsFile: Quickshell.env("OMARCHY_IMAGE_SELECTOR_COLORS_FILE") || (Quickshell.env("HOME") + "/.config/omarchy/current/theme/wallpaper-switcher-colors.json")
  property string layerNamespace: Quickshell.env("OMARCHY_IMAGE_SELECTOR_NAMESPACE") || "omarchy-image-selector"
  property int selectedIndex: 0
  property bool imagesLoaded: false
  property color accent: "#798186"
  property color background: "#101315"
  property color foreground: "#cacccc"
  property int expandedWidth: 768
  property int sliceWidth: 108
  property int sliceHeight: 432
  property int sliceSpacing: -30
  property int skewOffset: 28

  function fileUrl(path) {
    return "file://" + path.split("/").map(encodeURIComponent).join("/")
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function currentPath() {
    if (imageModel.count === 0) return ""
    return imageModel.get(selectedIndex).filePath
  }

  function select(index) {
    if (imageModel.count === 0) return
    if (index < 0) index = imageModel.count - 1
    else if (index >= imageModel.count) index = 0

    selectedIndex = index
    list.currentIndex = index
    list.centerSelected()
  }

  function applySelected() {
    var path = currentPath()
    if (!path) return
    applyProc.command = ["bash", "-lc", "printf '%s\\n' " + shellQuote(path) + " > " + shellQuote(selectionFile)]
    applyProc.running = true
  }

  ListModel {
    id: imageModel
    onCountChanged: {
      if (count > 0 && list.currentIndex < 0)
        root.select(0)
    }
  }

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
    command: ["bash", "-lc", "cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/image-selector; while IFS= read -r dir; do [[ -d $dir ]] && find -L \"$dir\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) -print0; done <<< " + shellQuote(root.imageDirs) + " | sort -z | while IFS= read -r -d '' image; do hash=$(md5sum \"$image\" | cut -d ' ' -f 1); thumb=\"$cache_dir/$hash.jpg\"; [[ -f $thumb ]] || thumb=$image; printf '%s\\t%s\\n' \"$image\" \"$thumb\"; done"]
    stdout: SplitParser {
      onRead: function(data) {
        loadImagesProc.output += data + "\n"
      }
    }
    onExited: {
      var paths = output.split("\n")
      for (var i = 0; i < paths.length; i++) {
        var row = paths[i].trim()
        if (!row) continue

        var columns = row.split("\t")
        root.addImage(columns[0], columns[1])
      }
      root.select(root.selectedImageIndex())
      root.imagesLoaded = true
    }
  }

  Component.onCompleted: loadImagesProc.running = true

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
    onExited: Qt.quit()
  }

  PanelWindow {
    id: panel
    visible: root.imagesLoaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: root.layerNamespace
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)
    }

    MouseArea {
      anchors.fill: parent
      onClicked: Qt.quit()
    }

    Item {
      id: card
      width: Math.min(parent.width - 80, root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing) + 40)
      height: root.sliceHeight + 60
      anchors.centerIn: parent

      MouseArea { anchors.fill: parent; onClicked: {} }

      ListView {
        id: list
        anchors.top: parent.top
        anchors.topMargin: 30
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing)
        orientation: ListView.Horizontal
        model: imageModel
        spacing: root.sliceSpacing
        clip: false
        focus: true
        currentIndex: 0
        preferredHighlightBegin: (width - root.expandedWidth) / 2
        preferredHighlightEnd: (width + root.expandedWidth) / 2
        highlightRangeMode: ListView.NoHighlightRange
        highlightMoveDuration: 120
        highlight: Item {}
        header: Item { width: (list.width - root.expandedWidth) / 2; height: 1 }
        footer: Item { width: (list.width - root.expandedWidth) / 2; height: 1 }

        function centerSelected() {
          Qt.callLater(function() {
            var selectedItem = list.itemAtIndex(root.selectedIndex)
            if (selectedItem)
              list.contentX = selectedItem.x + selectedItem.width / 2 - list.width / 2
          })
        }

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            Qt.quit()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.applySelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.select(root.selectedIndex - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.select(root.selectedIndex + 1)
            event.accepted = true
          }
        }

        Component.onCompleted: forceActiveFocus()

        delegate: Item {
          id: item
          required property int index
          required property string filePath
          required property string fileName
          required property string thumbnailPath

          readonly property bool selected: index === root.selectedIndex

          width: selected ? root.expandedWidth : root.sliceWidth
          height: list.height
          z: selected ? 100 : 50 - Math.min(Math.abs(index - root.selectedIndex), 40)

          onWidthChanged: if (selected) list.centerSelected()

          readonly property real skAbs: Math.abs(root.skewOffset)
          readonly property real topLeft: root.skewOffset >= 0 ? skAbs : 0
          readonly property real topRight: root.skewOffset >= 0 ? width : width - skAbs
          readonly property real bottomRight: root.skewOffset >= 0 ? width - skAbs : width
          readonly property real bottomLeft: root.skewOffset >= 0 ? 0 : skAbs

          Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

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
              fillColor: "#000000"
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
              source: root.fileUrl(item.thumbnailPath)
              fillMode: Image.PreserveAspectCrop
              asynchronous: false
              cache: true
              smooth: true
            }

            Rectangle {
              anchors.fill: parent
              color: Qt.rgba(0, 0, 0, item.selected ? 0 : 0.42)
              Behavior on color { ColorAnimation { duration: 120 } }
            }
          }

          Shape {
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              fillColor: "transparent"
              strokeColor: item.selected ? root.accent : Qt.rgba(0, 0, 0, 0.65)
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
  }
}
