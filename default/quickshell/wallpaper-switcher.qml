import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

ShellRoot {
  id: root

  property string stockBackgroundsDir: Quickshell.env("OMARCHY_STOCK_BACKGROUNDS_DIR") || (Quickshell.env("HOME") + "/.config/omarchy/current/theme/backgrounds")
  property string userBackgroundsDir: Quickshell.env("OMARCHY_USER_BACKGROUNDS_DIR")
  property string currentBackground: Quickshell.env("HOME") + "/.config/omarchy/current/background"
  property string selectionFile: Quickshell.env("OMARCHY_WALLPAPER_SELECTION_FILE")
  property int selectedIndex: 0
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
    if (wallpaperModel.count === 0) return ""
    return wallpaperModel.get(selectedIndex, "filePath")
  }

  function select(index) {
    if (index < 0 || index >= wallpaperModel.count) return
    selectedIndex = index
    list.currentIndex = index
    list.positionViewAtIndex(index, ListView.Center)
  }

  function applySelected() {
    var path = currentPath()
    if (!path) return
    applyProc.command = ["bash", "-lc", "printf '%s\\n' " + shellQuote(path) + " > " + shellQuote(selectionFile)]
    applyProc.running = true
  }

  ListModel {
    id: wallpaperModel
  }

  function addBackground(path) {
    if (!path) return
    var fileName = path.split("/").pop()

    for (var i = wallpaperModel.count - 1; i >= 0; i--) {
      if (wallpaperModel.get(i).fileName === fileName)
        wallpaperModel.remove(i)
    }

    wallpaperModel.append({ filePath: path, fileName: fileName })
  }

  Process {
    id: loadBackgroundsProc
    command: ["bash", "-lc", "for dir in " + shellQuote(root.stockBackgroundsDir) + " " + shellQuote(root.userBackgroundsDir) + "; do [[ -d $dir ]] && find -L \"$dir\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) -print | sort; done"]
    stdout: SplitParser {
      onRead: function(data) {
        var paths = data.split("\n")
        for (var i = 0; i < paths.length; i++)
          root.addBackground(paths[i].trim())
      }
    }
  }

  Component.onCompleted: loadBackgroundsProc.running = true

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/current/theme/wallpaper-switcher-colors.json"
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
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-wallpaper-switcher"
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
        model: wallpaperModel
        spacing: root.sliceSpacing
        clip: false
        focus: true
        currentIndex: root.selectedIndex
        preferredHighlightBegin: (width - root.expandedWidth) / 2
        preferredHighlightEnd: (width + root.expandedWidth) / 2
        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: 120
        highlight: Item {}
        header: Item { width: (list.width - root.expandedWidth) / 2; height: 1 }
        footer: Item { width: (list.width - root.expandedWidth) / 2; height: 1 }

        Keys.onEscapePressed: Qt.quit()
        Keys.onReturnPressed: root.applySelected()
        Keys.onLeftPressed: root.select(Math.max(0, root.selectedIndex - 1))
        Keys.onRightPressed: root.select(Math.min(wallpaperModel.count - 1, root.selectedIndex + 1))

        Component.onCompleted: forceActiveFocus()

        delegate: Item {
          id: item
          required property int index
          required property string filePath
          required property string fileName

          width: index === root.selectedIndex ? root.expandedWidth : root.sliceWidth
          height: list.height
          z: index === root.selectedIndex ? 100 : 50 - Math.min(Math.abs(index - root.selectedIndex), 40)

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
            x: index === root.selectedIndex ? 4 : 2
            y: index === root.selectedIndex ? 10 : 5
            width: item.width
            height: item.height
            opacity: index === root.selectedIndex ? 0.5 : 0.32
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
              source: root.fileUrl(item.filePath)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: true
              smooth: true
              opacity: status === Image.Ready ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            Rectangle {
              anchors.fill: parent
              color: Qt.rgba(0, 0, 0, index === root.selectedIndex ? 0 : 0.42)
              Behavior on color { ColorAnimation { duration: 120 } }
            }
          }

          Shape {
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              fillColor: "transparent"
              strokeColor: index === root.selectedIndex ? root.accent : Qt.rgba(0, 0, 0, 0.65)
              strokeWidth: index === root.selectedIndex ? 3 : 1
              startX: item.topLeft; startY: 0
              PathLine { x: item.topRight; y: 0 }
              PathLine { x: item.bottomRight; y: item.height }
              PathLine { x: item.bottomLeft; y: item.height }
              PathLine { x: item.topLeft; y: 0 }
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.select(index)
            onClicked: index === root.selectedIndex ? root.applySelected() : root.select(index)
          }
        }
      }
    }
  }
}
