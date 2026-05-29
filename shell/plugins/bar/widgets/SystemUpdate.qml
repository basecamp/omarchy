import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.system-update"

  property bool updateAvailable: false
  property int updateCount: 0
  property string updateOutput: ""
  property var updateLines: []
  property var omarchyUpdateLines: []
  property var otherUpdateLines: []
  property bool popupOpen: false
  property bool buttonHovered: false
  property bool popupHovered: popup.containsMouse

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
  readonly property string availableStatePath: stateHome + "/omarchy/updates/available"
  readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
  readonly property color urgent: root.bar ? root.bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  function close() { popupOpen = false }

  function refresh() {
    updateOutput = ""
    if (!updateProc.running) updateProc.running = true
  }

  function clear() {
    updateOutput = ""
    updateLines = []
    omarchyUpdateLines = []
    otherUpdateLines = []
    updateCount = 0
    updateAvailable = false
    popupOpen = false
  }

  function runUpdate() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-update")
  }

  function packageName(line) {
    return String(line || "").trim().split(/\s+/)[0] || ""
  }

  function versionMatch(line) {
    return String(line || "").trim().match(/^\S+\s+(.+?)\s+->\s+(.+)$/)
  }

  function versionFrom(line) {
    var match = versionMatch(line)
    return match ? match[1] : ""
  }

  function versionTo(line) {
    var match = versionMatch(line)
    return match ? match[2] : ""
  }

  function isOmarchyPackage(line) {
    var pkg = packageName(line)
    return pkg === "omarchy" || pkg.indexOf("omarchy-") === 0
  }

  function countLabel(count) {
    return count === 1 ? "1 update" : count + " updates"
  }

  function parseUpdateText(text) {
    var lines = String(text || "").split(/\r?\n/).filter(function(line) {
      return line.trim().length > 0
    })
    var omarchyLines = []
    var otherLines = []

    for (var i = 0; i < lines.length; i++) {
      if (isOmarchyPackage(lines[i])) omarchyLines.push(lines[i])
      else otherLines.push(lines[i])
    }

    omarchyUpdateLines = omarchyLines
    otherUpdateLines = otherLines
    updateLines = omarchyLines.concat(otherLines)
    updateCount = updateLines.length
    updateAvailable = updateCount > 0
    if (!updateAvailable) popupOpen = false
  }

  function applyUpdateOutput(exitCode) {
    var output = String(updateStdout.text || updateOutput || "")
    parseUpdateText(exitCode === 0 ? output : "")
  }

  function showPopup() {
    hideTimer.stop()
    if (updateAvailable) popupOpen = true
  }

  function scheduleHide() {
    hideTimer.restart()
  }

  onButtonHoveredChanged: buttonHovered ? showPopup() : scheduleHide()
  onPopupHoveredChanged: popupHovered ? hideTimer.stop() : scheduleHide()
  onUpdateAvailableChanged: if (!updateAvailable) popupOpen = false

  visible: updateAvailable
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "omarchy.system-update"

    function refresh(): void {
      root.refresh()
    }

    function clear(): void {
      root.clear()
    }
  }

  Process {
    id: updateProc
    command: ["bash", "-lc", "omarchy-update-available"]
    stdout: StdioCollector { id: updateStdout; waitForEnd: true; onStreamFinished: root.updateOutput = text }
    onExited: function(exitCode) {
      root.applyUpdateOutput(exitCode)
    }
  }

  FileView {
    id: availableState
    path: root.availableStatePath
    watchChanges: true
    printErrors: false
    onLoaded: root.parseUpdateText(text())
    onLoadFailed: root.clear()
    onFileChanged: reload()
  }

  Timer {
    interval: 21600000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: hideTimer
    interval: 220
    onTriggered: {
      if (!root.buttonHovered && !root.popupHovered) root.popupOpen = false
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.updateAvailable ? "\uf021" : ""
    fontSize: Style.font.caption
    tooltipText: ""
    onPressed: root.runUpdate()
  }

  HoverHandler {
    id: hoverHandler
    target: button
    onHoveredChanged: root.buttonHovered = hovered
  }

  PopupCard {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen && root.updateAvailable
    triggerMode: "hover"
    contentWidth: popup.fittedContentWidth(Style.space(460))
    contentHeight: popup.fittedContentHeight(panelColumn.implicitHeight, Style.space(640))

    Flickable {
      id: updateFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: panelColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: panelColumn
        width: updateFlick.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "System update"
          meta: countLabel(root.updateCount) + " available"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: "\uf021"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Button {
          width: parent.width
          text: "Run omarchy update"
          iconText: "\uf021"
          foreground: root.foreground
          accent: root.urgent
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          iconSize: Style.font.body
          bordered: true
          onClicked: root.runUpdate()
        }

        PanelSeparator {
          visible: root.updateLines.length > 0
          foreground: root.foreground
        }

        UpdateSection {
          title: "Omarchy"
          lines: root.omarchyUpdateLines
          important: true
          width: parent.width
        }

        PanelSeparator {
          visible: root.omarchyUpdateLines.length > 0 && root.otherUpdateLines.length > 0
          foreground: root.foreground
        }

        UpdateSection {
          title: "Other packages"
          lines: root.otherUpdateLines
          width: parent.width
        }
      }
    }
  }

  component UpdateSection: Column {
    id: section

    property string title: ""
    property var lines: []
    property bool important: false

    visible: lines.length > 0
    spacing: Style.space(8)

    PanelSectionHeader {
      width: section.width
      text: section.title.toUpperCase() + " (" + section.lines.length + ")"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Column {
      width: section.width
      spacing: Style.space(6)

      Repeater {
        model: section.lines

        delegate: UpdateRow {
          width: parent.width
          line: modelData
          important: section.important
        }
      }
    }
  }

  component UpdateRow: CursorSurface {
    id: row

    property string line: ""
    property bool important: false
    readonly property string packageTitle: root.packageName(line)
    readonly property string fromVersion: root.versionFrom(line)
    readonly property string toVersion: root.versionTo(line)
    readonly property bool hasVersions: fromVersion !== "" && toVersion !== ""

    foreground: root.foreground
    accent: root.urgent
    implicitHeight: Math.max(Style.spacing.popupRowHeight, rowContent.implicitHeight + Style.spacing.rowPaddingX)

    ColumnLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.space(1)

      Text {
        Layout.fillWidth: true
        text: row.packageTitle
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      RowLayout {
        visible: row.hasVersions
        Layout.fillWidth: true
        spacing: Style.space(7)

        Text {
          Layout.fillWidth: true
          text: row.fromVersion
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          text: "\u2192"
          color: row.important ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        Text {
          Layout.fillWidth: true
          text: row.toVersion
          color: row.important ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          elide: Text.ElideRight
        }
      }

      Text {
        visible: !row.hasVersions
        Layout.fillWidth: true
        text: row.line
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WrapAnywhere
      }
    }
  }
}
