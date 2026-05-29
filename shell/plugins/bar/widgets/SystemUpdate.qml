import QtQuick
import QtQuick.Controls
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

  function packageName(line) {
    return String(line || "").trim().split(/\s+/)[0] || ""
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
    onPressed: function() { root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-update") }
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
    contentHeight: popup.fittedContentHeight(panelColumn.implicitHeight, Style.space(520))

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

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: "\uf021"
            color: root.bar ? root.bar.urgent : Color.urgent
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            verticalAlignment: Text.AlignVCenter
          }

          Column {
            width: parent.width - Style.space(28)
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: countLabel(root.updateCount) + " available"
              color: Color.popups.text
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              width: parent.width
              text: "Click to run omarchy update"
              color: Qt.darker(Color.popups.text, 1.35)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        UpdateSection {
          title: "Omarchy"
          lines: root.omarchyUpdateLines
          width: parent.width
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

    visible: lines.length > 0
    spacing: Style.space(6)

    Text {
      width: section.width
      text: section.title
      color: root.bar ? root.bar.foreground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Repeater {
      model: section.lines

      delegate: Text {
        width: section.width
        text: modelData
        color: Color.popups.text
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WrapAnywhere
      }
    }
  }
}
