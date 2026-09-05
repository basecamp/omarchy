import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "components"
import "NotificationLogic.js" as NotificationLogic

Panel {
  id: root
  moduleName: "omarchy.notifications"
  ipcTarget: ""

  readonly property var notificationService: bar?.shell?.firstPartyServiceFor("omarchy.notifications")
  property var entries: []

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refreshHistory() {
    if (!readHistory.running) readHistory.running = true
  }

  onOpenedChanged: if (opened) refreshHistory()

  Connections {
    target: root.notificationService
    function onHistoryRevisionChanged() { if (root.opened) root.refreshHistory() }
  }

  Process {
    id: readHistory
    running: false
    command: ["bash", "-c", "awk 1 \"$1\"/*.json \"$2\"/*.json 2>/dev/null || true", "--",
      (Quickshell.env("HOME") || "") + "/.local/state/omarchy/notifications/history",
      (Quickshell.env("HOME") || "") + "/.local/state/omarchy/notifications"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.entries = NotificationLogic.historyRows(text, [], 1, 1000000)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰂚"
    active: root.entries.length > 0
    tooltipText: "Notification center"
    onPressed: root.toggle()
  }

  KeyboardPanel {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: fittedContentWidth(Style.space(410))
    contentHeight: fittedContentHeight(content.implicitHeight, Style.space(650))

    Column {
      id: content
      anchors.fill: parent
      spacing: Style.space(10)

      Item {
        width: parent.width
        height: Math.max(title.implicitHeight, clearButton.implicitHeight)

        Text {
          id: title
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Notifications"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Button {
          id: clearButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: root.entries.length > 0
          text: "Clear all"
          foreground: root.barForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: {
            if (root.notificationService) root.notificationService.clearHistory()
            root.entries = []
          }
        }
      }

      Text {
        visible: root.entries.length === 0
        width: parent.width
        topPadding: Style.space(24)
        text: "No notifications since startup"
        color: Qt.darker(root.barForeground, 1.5)
        horizontalAlignment: Text.AlignHCenter
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      Flickable {
        width: parent.width
        height: Math.min(historyColumn.implicitHeight, Style.space(580))
        contentWidth: width
        contentHeight: historyColumn.implicitHeight
        visible: root.entries.length > 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: historyColumn
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            model: root.entries

            NotificationCard {
              required property var modelData
              width: historyColumn.width
              app: String(modelData.app || "")
              appIcon: String(modelData.appIcon || "")
              summary: String(modelData.summary || "")
              body: String(modelData.body || "")
              image: String(modelData.image || "")
              glyph: String(modelData.glyph || "")
              urgency: Number(modelData.urgency || 1)
              timestamp: Number(modelData.timestamp || 0)
              cornerRadius: Style.cornerRadius
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              dismissible: false
              onCardClicked: if (root.notificationService) root.notificationService.activateHistoryEntry(modelData)
            }
          }
        }
      }
    }
  }
}
