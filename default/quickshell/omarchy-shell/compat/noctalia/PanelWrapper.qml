import QtQuick
import Quickshell
import qs.Commons

// Wraps Noctalia panel entry points, which are plain Item content intended to
// be hosted inside Noctalia's SmartPanel. We host them as anchored PopupWindows
// so clicking a Noctalia bar widget behaves like native Omarchy popups instead
// of opening a tiled app window.
Item {
  id: root

  property string panelSource: ""
  property var pluginApi: null
  property var manifest: ({})
  property string omarchyPath: ""
  property var shell: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property bool popupOpen: false
  property bool closingFromShell: false

  readonly property var anchorItem: pluginApi ? pluginApi.panelAnchorItem : null
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPosition: {
    if (shell && shell.barConfig && shell.barConfig.position) return String(shell.barConfig.position)
    return "top"
  }

  function open(payloadJson) {
    popupOpen = true
  }

  function close() {
    closingFromShell = true
    popupOpen = false
    if (pluginApi) {
      pluginApi.panelOpenScreen = null
      pluginApi.panelAnchorItem = null
    }
    closingFromShell = false
  }

  function dismiss() {
    if (!popupOpen) return
    if (pluginApi && typeof pluginApi.closePanel === "function") pluginApi.closePanel(null)
    else if (shell && manifest && manifest.id && typeof shell.hide === "function") shell.hide(manifest.id)
    else close()
  }

  PopupWindow {
    id: popup
    visible: root.popupOpen
    color: "transparent"
    implicitWidth: Math.max(320, panelLoader.item && panelLoader.item.contentPreferredWidth
      ? panelLoader.item.contentPreferredWidth : 420)
    implicitHeight: Math.max(260, panelLoader.item && panelLoader.item.contentPreferredHeight
      ? panelLoader.item.contentPreferredHeight : 520)

    onVisibleChanged: {
      if (!visible && root.popupOpen && !root.closingFromShell) root.dismiss()
    }

    // Do not use HyprlandFocusGrab here. Noctalia panels are larger,
    // interactive surfaces with tabs and nested Flickables; focus grabs made
    // internal clicks (notably tab switches) look like outside clicks and also
    // interfered with wheel scrolling. Native Omarchy micro-popups can keep
    // focus-grab dismissal, but compat panels behave more like pinned panels.
    anchor {
      id: popupAnchor
      window: root.anchorWindow
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        var target = root.anchorItem
        var window = root.anchorWindow
        if (!target || !window) {
          popupAnchor.rect.x = 0
          popupAnchor.rect.y = 0
          return
        }

        var popupWidth = popup.implicitWidth
        var popupHeight = popup.implicitHeight
        var margin = 8
        var localX = target.width / 2 - popupWidth / 2
        var localY = target.height + margin

        if (root.barPosition === "bottom") {
          localY = -popupHeight - margin
        } else if (root.barPosition === "left") {
          localX = target.width + margin
          localY = target.height / 2 - popupHeight / 2
        } else if (root.barPosition === "right") {
          localX = -popupWidth - margin
          localY = target.height / 2 - popupHeight / 2
        }

        var point = window.contentItem.mapFromItem(target, localX, localY)
        popupAnchor.rect.x = Math.round(point.x)
        popupAnchor.rect.y = Math.round(point.y)
      }
    }

    Rectangle {
      anchors.fill: parent
      color: Color.mSurface
      border.color: Color.mOutline
      border.width: 1
      radius: 0

      Loader {
        id: panelLoader
        anchors.fill: parent
        source: root.panelSource
        onLoaded: root.injectPanelProps()
        onStatusChanged: {
          if (status === Loader.Error) {
            console.warn("noctalia panel failed for " + (root.manifest ? root.manifest.id : "") + ":", errorString())
          }
        }
      }
    }
  }

  onPluginApiChanged: injectPanelProps()
  onManifestChanged: injectPanelProps()

  function injectPanelProps() {
    var item = panelLoader.item
    if (!item) return
    if ("pluginApi" in item) item.pluginApi = root.pluginApi
    if ("manifest" in item) item.manifest = root.manifest
    if ("omarchyPath" in item) item.omarchyPath = root.omarchyPath
    if ("shell" in item) item.shell = root.shell
    if ("pluginRegistry" in item) item.pluginRegistry = root.pluginRegistry
    if ("barWidgetRegistry" in item) item.barWidgetRegistry = root.barWidgetRegistry
    if ("screen" in item) {
      var screens = Quickshell.screens
      item.screen = screens && screens.length > 0 ? screens[0] : null
    }
  }
}
