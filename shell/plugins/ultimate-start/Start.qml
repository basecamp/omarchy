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
  readonly property var entries: appLibrary ? appLibrary.sortedEntries(root.filter) : []

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    root.focusSearch = payload.focusSearch === true
    root.filter = ""
    if (searchField) searchField.text = ""
    root.opened = true
    if (appLibrary) appLibrary.refreshIcons()
    Qt.callLater(function() {
      if (root.focusSearch) searchField.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
    root.filter = ""
    if (searchField) searchField.text = ""
  }

  function launchEntry(entry) {
    if (!entry || !appLibrary) return
    appLibrary.launch(entry.id, appLibrary.entryName(entry))
    root.close()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 440
    implicitHeight: 560
    margins.bottom: 48
    margins.left: 8
    anchors.bottom: true
    anchors.left: true
    WlrLayershell.namespace: "omarchy-start"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: Tokens.surface.glass
      radius: Tokens.radius.large
      border.color: Tokens.border.subtle
      border.width: 1

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        SearchBox {
          id: searchField
          Layout.fillWidth: true
          onTextChanged: root.filter = text
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
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: root.entries
          delegate: Item {
            width: ListView.view.width
            height: 36
            RowLayout {
              anchors.fill: parent
              spacing: 10
              Image {
                width: 20
                height: 20
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
            iconText: "\u23FB"
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
