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
  property string command: ""

  readonly property var appLibrary: shell ? shell.appLibrary : null
  readonly property var matches: appLibrary ? appLibrary.sortedEntries(root.command) : []

  function open(payloadJson) {
    root.command = ""
    if (root.shell && root.shell.transientCoordinator)
      root.shell.transientCoordinator.request(root)
    root.opened = true
    Qt.callLater(function() { field.forceActiveFocus() })
  }

  function close() {
    if (root.shell && root.shell.transientCoordinator)
      root.shell.transientCoordinator.release(root)
    root.opened = false
    root.command = ""
  }

  function run() {
    var query = String(root.command || "").trim()
    if (!query) return
    if (matches.length > 0 && appLibrary) {
      var entry = matches[0].entry || matches[0]
      appLibrary.launch(entry.id, appLibrary.entryName(entry))
    } else {
      Util.execDetached("uwsm-app -- " + query)
    }
    root.close()
  }

  PanelWindow {
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 420
    implicitHeight: 88
    WlrLayershell.namespace: "omarchy-run"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      anchors.margins: 8
      color: Tokens.surface.glass
      radius: Tokens.radius.medium
      border.color: Tokens.border.subtle
      border.width: 1

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Text {
          text: "Run"
          color: Tokens.text.secondary
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        SearchBox {
          id: field
          Layout.fillWidth: true
          text: root.command
          onTextChanged: root.command = text
          Keys.onReturnPressed: root.run()
          Keys.onEscapePressed: root.close()
        }
      }
    }

    PanelKeyCatcher {
      anchors.fill: parent
      blocked: field.activeFocus
      onCloseRequested: root.close()
    }
  }
}
