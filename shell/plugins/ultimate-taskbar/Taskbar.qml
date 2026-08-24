import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: ""
  property var barWidgetRegistry: null
  property var barConfig: ({})
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  property string home: Quickshell.env("HOME")
  property bool barHidden: false
  property int barSize: Math.max(48, Style.bar.sizeHorizontal + 22)
  property bool vertical: false
  property string position: "bottom"
  property string fontFamily: Style.font.family
  property color foreground: Tokens.text.primary
  property color barForeground: Tokens.text.primary
  // Windows 7 Superbar glass: graphite, not Tokyo Night navy. Alpha + layer
  // blur is the translucency. Do not fill with Tokens.surface.glass.
  // Defaults match default/ultimate/chrome-tokens.json so the first frame is
  // correct before FileView lands, and so a missing file cannot bleach chrome.
  property color chromeBar: Qt.rgba(0.11, 0.11, 0.12, 0.62)
  readonly property color chromeHover: Qt.rgba(1, 1, 1, 0.10)
  readonly property color chromeActive: Qt.rgba(1, 1, 1, 0.16)
  readonly property color chromePressed: Qt.rgba(1, 1, 1, 0.22)
  property color chromeMenu: Qt.rgba(0.11, 0.11, 0.12, 0.88)
  property color chromeGlow: "#e8943a"
  property color chromeStart: "#9cbc0d"
  property color chromeEdge: "#55ffffff"
  property color background: chromeBar
  property var moduleSlots: []
  readonly property var windowService: shell ? shell.windowService : null
  readonly property var appLibrary: shell ? shell.appLibrary : null
  readonly property var groups: windowService ? windowService.groups : []

  function applyChromeTokens(body) {
    var t
    try {
      t = JSON.parse(body || "{}")
    } catch (e) {
      return
    }
    if (!t || typeof t !== "object") return
    var r = Number(t.glassRed)
    var g = Number(t.glassGreen)
    var b = Number(t.glassBlue)
    var pct = Number(t.glassAlphaPct)
    if (isNaN(r)) r = 28
    if (isNaN(g)) g = 28
    if (isNaN(b)) b = 30
    if (isNaN(pct)) pct = 62
    root.chromeBar = Qt.rgba(r / 255, g / 255, b / 255, pct / 100)
    root.chromeMenu = Qt.rgba(r / 255, g / 255, b / 255, 0.88)
    if (t.chromeGlowHex) root.chromeGlow = t.chromeGlowHex
    if (t.chromeStartHex) root.chromeStart = t.chromeStartHex
    if (t.chromeEdgeHex) root.chromeEdge = t.chromeEdgeHex
  }

  function registerSlot(pluginId, item) {
    if (!item) return
    var next = moduleSlots.slice()
    next.push({ moduleName: String(pluginId || ""), activeItem: item })
    moduleSlots = next
  }

  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot.moduleName !== id || !slot.activeItem) continue
      var item = slot.activeItem
      if (typeof item.open === "function" && typeof item.close === "function" && item.opened !== undefined)
        return item
    }
    return null
  }

  function summonBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item) return false
    item.open()
    return true
  }

  function hideBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item) return false
    item.close()
    return true
  }

  function isBarWidgetOpen(pluginId) {
    var item = findPanelWidget(pluginId)
    return !!item && item.opened === true
  }

  function panelWidgetIdAt(region, index) {
    var names = ["omarchy.audio", "omarchy.bluetooth", "omarchy.network", "omarchy.monitor", "omarchy.power"]
    return names[Math.round(Number(index)) - 1] || ""
  }

  function run(command) {
    if (command) Util.execDetached(command)
  }

  function debugBarGeometry() {
    return []
  }

  function toggleTransparency() {
    return
  }

  function togglePin(group) {
    if (root.windowService) root.windowService.togglePin(group)
  }

  function moduleWidgets(pluginId) {
    var id = String(pluginId || "")
    var items = []
    if (!id) return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem && slot.moduleName === id) items.push(slot.activeItem)
    }
    return items
  }

  function switchPanelFrom(owner, direction) {
    if (!owner) return false
    var currentIndex = -1
    var panels = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      if (typeof slot.activeItem.open !== "function" || typeof slot.activeItem.close !== "function") continue
      if (slot.activeItem.opened === undefined) continue
      if (slot.activeItem === owner) currentIndex = panels.length
      panels.push(slot)
    }
    if (currentIndex < 0 || panels.length < 2) return false
    var step = direction < 0 ? -1 : 1
    var next = panels[(currentIndex + step + panels.length) % panels.length]
    if (!next || !next.activeItem) return false
    next.activeItem.open()
    return true
  }

  FileView {
    path: (root.omarchyPath || Quickshell.env("OMARCHY_PATH")) + "/default/ultimate/chrome-tokens.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyChromeTokens(text())
    onFileChanged: reload()
  }

  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = String(line).trim() === "yes" } }
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        id: barWindow
        required property var modelData
        screen: modelData
        visible: !remapGuard.remapping && !root.barHidden
        // Exclusive zone needs 1 or 3 anchors. Auto guessed the thickness
        // onto the wrong edge on Hyprland 0.56; Normal + exclusiveZone pins
        // the bottom inset the snap math reads as reserved[3].
        exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Normal
        exclusiveZone: root.barHidden ? 0 : implicitHeight
        color: root.background
        implicitHeight: root.barSize
        implicitWidth: 0
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "omarchy-taskbar"
        WlrLayershell.layer: WlrLayer.Top
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        HoverHandler {
          onHoveredChanged: {
            if (root.shell && root.shell.transientCoordinator)
              root.shell.transientCoordinator.setExempt("taskbar", hovered)
          }
          Component.onDestruction: {
            if (root.shell && root.shell.transientCoordinator)
              root.shell.transientCoordinator.setExempt("taskbar", false)
          }
        }

        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          z: 2
          color: root.chromeEdge
        }

        ScreenMoveRemap {
          id: remapGuard
          window: barWindow
        }

        RowLayout {
          anchors.fill: parent
          spacing: 0

          StartButton {
            bar: root
            Layout.preferredWidth: 76
            Layout.fillHeight: true
          }

          TaskView {
            bar: root
            Layout.preferredWidth: 44
            Layout.fillHeight: true
          }

          Repeater {
            model: root.groups
            delegate: TaskButton {
              bar: root
              hostWindow: barWindow
              group: modelData
              Layout.preferredWidth: 52
              Layout.fillHeight: true
            }
          }

          Item { Layout.fillWidth: true }

          TrayCluster {
            bar: root
            Layout.fillHeight: true
          }

          ShowDesktop {
            bar: root
            Layout.preferredWidth: 8
            Layout.fillHeight: true
          }
        }
      }
    }
  }
}
