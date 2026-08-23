import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string filter: ""
  property bool focusSearch: false

  readonly property var appLibrary: shell ? shell.appLibrary : null
  readonly property var modeProfile: shell ? shell.modeProfileService : null
  readonly property var windowService: shell ? shell.windowService : null
  readonly property var pins: windowService ? windowService.pins : []
  readonly property bool hideDeveloperTools: !(modeProfile && modeProfile.feature("developerToolsInStart"))
  readonly property var entries: appLibrary ? appLibrary.visibleEntries(root.filter, root.hideDeveloperTools) : []

  property var focusedWhenOpened: null
  property bool raiseUnderCursorOnClose: false
  property bool launchingFromStart: false

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    root.focusSearch = payload.focusSearch === true
    root.filter = ""
    root.focusedWhenOpened = ToplevelManager.activeToplevel
    root.raiseUnderCursorOnClose = false
    root.launchingFromStart = false
    if (root.shell && root.shell.transientCoordinator)
      root.shell.transientCoordinator.request(root)
    root.opened = true
    if (appLibrary) appLibrary.refreshIcons()
  }

  function close() {
    var raise = root.raiseUnderCursorOnClose && !root.launchingFromStart
    root.raiseUnderCursorOnClose = false
    root.launchingFromStart = false
    if (root.shell && root.shell.transientCoordinator)
      root.shell.transientCoordinator.release(root)
    if (!root.opened) {
      root.filter = ""
      return
    }
    root.opened = false
    root.filter = ""
    root.focusedWhenOpened = null
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide("omarchy.ultimate-start")
    if (raise && root.shell && root.shell.windowService
        && typeof root.shell.windowService.activateAtCursorSoon === "function")
      root.shell.windowService.activateAtCursorSoon()
  }

  function launchEntry(entry) {
    if (!entry || !appLibrary) return
    root.launchingFromStart = true
    root.raiseUnderCursorOnClose = false
    appLibrary.launch(entry.id, appLibrary.entryName(entry))
    root.close()
  }

  Connections {
    target: ToplevelManager
    enabled: root.opened
    function onActiveToplevelChanged() {
      var next = ToplevelManager.activeToplevel
      if (!next)
        return
      if (next !== root.focusedWhenOpened) {
        if (!root.launchingFromStart)
          root.raiseUnderCursorOnClose = true
        root.close()
      }
    }
  }

  // The Start card is the only mapped overlay. A full-screen MouseArea (or
  // HyprlandFocusGrab) swallows the outside click. Windows click-outside
  // must close Start and still raise the window or Superbar item underneath.
  // Loader unmaps the card when closed so keepLoaded cannot leave a sink.
  Loader {
    active: root.opened
    sourceComponent: PanelWindow {
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 440
    implicitHeight: 560
    anchors.left: true
    anchors.bottom: true
    margins.left: 8
    margins.bottom: 48
    WlrLayershell.namespace: "omarchy-start"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Rectangle {
      anchors.fill: parent
      clip: true
      color: Tokens.surface.glass
      radius: Tokens.radius.large
      border.color: Tokens.border.subtle
      border.width: 1

      HoverHandler {
        onHoveredChanged: {
          if (root.shell && root.shell.transientCoordinator)
            root.shell.transientCoordinator.setExempt("start", hovered)
        }
        Component.onDestruction: {
          if (root.shell && root.shell.transientCoordinator)
            root.shell.transientCoordinator.setExempt("start", false)
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        SearchBox {
          id: searchField
          Layout.fillWidth: true
          onTextChanged: root.filter = text
          Component.onCompleted: searchField.forceActiveFocus()
          Keys.onReturnPressed: {
            if (root.entries.length > 0) root.launchEntry(root.entries[0])
          }
          Keys.onEscapePressed: root.close()
        }

        Text {
          visible: root.pins.length > 0 && root.filter.length === 0
          text: "Pinned"
          color: Tokens.text.secondary
          font.pixelSize: Style.font.bodySmall
          font.family: Style.font.family
        }

        Flow {
          visible: root.filter.length === 0 && root.pins.length > 0
          Layout.fillWidth: true
          spacing: 8
          Repeater {
            model: root.pins
            delegate: Button {
              text: modelData.name || modelData.desktopId
              onClicked: {
                if (root.appLibrary) root.appLibrary.launch(modelData.desktopId || modelData.id, modelData.name)
                root.close()
              }
            }
          }
        }

        ListView {
          visible: root.entries.length > 0
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: root.entries
          delegate: Item {
            width: ListView.view.width
            height: 36
            clip: true
            RowLayout {
              anchors.fill: parent
              spacing: 10
              Image {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter
                width: 20
                height: 20
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: 20 * Screen.devicePixelRatio
                sourceSize.height: 20 * Screen.devicePixelRatio
                source: root.appLibrary ? root.appLibrary.iconSource(modelData.icon) : ""
              }
              Text {
                Layout.fillWidth: true
                text: root.appLibrary ? root.appLibrary.entryName(modelData) : ""
                color: Tokens.text.primary
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.launchEntry(modelData)
            }
          }
        }

        EmptyState {
          visible: root.entries.length === 0
          Layout.fillWidth: true
          Layout.fillHeight: true
          title: root.filter.length > 0 ? "No matching apps" : "Search for apps"
          message: root.filter.length > 0 ? "Try a different name." : "Chrome, Files, and other programs show here. Terminal and Vim stay available from search."
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Button {
            text: modeProfile && modeProfile.mode === "desktop" ? "Power User Mode" : "Desktop Mode"
            onClicked: {
              if (!modeProfile) return
              modeProfile.setMode(modeProfile.mode === "desktop" ? "power-user" : "desktop")
            }
          }

          Item { Layout.fillWidth: true }

          IconButton {
            iconText: "\uF023"
            tooltipText: "Lock"
            onClicked: { Util.execDetached("omarchy-system-lock"); root.close() }
          }
          IconButton {
            iconText: "\u21BB"
            tooltipText: "Restart"
            onClicked: { Util.execDetached("omarchy-system-reboot"); root.close() }
          }
          IconButton {
            iconText: "\u23FB"
            tooltipText: "Shut down"
            danger: true
            onClicked: { Util.execDetached("omarchy-system-shutdown"); root.close() }
          }
        }
      }
    }

      PanelKeyCatcher {
        anchors.fill: parent
        blocked: searchField.activeFocus
        onCloseRequested: root.close()
      }
    }
  }
}
