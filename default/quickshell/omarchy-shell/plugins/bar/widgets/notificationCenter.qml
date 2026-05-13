import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "notificationCenter"
  property var settings: ({})

  property bool popupOpen: false

  function closePopout() { popupOpen = false }
  property var stored: []
  property bool dnd: false

  readonly property int count: stored.length
  readonly property string icon: {
    if (dnd) return "󰂛"
    if (count > 0) return "󱅫"
    return "󰂚"
  }

  property bool replaceMako: settings && settings.replaceMako === true

  Loader {
    active: root.replaceMako
    sourceComponent: serverComponent
  }

  Component {
    id: serverComponent

    NotificationServer {
      id: server
      keepOnReload: false
      bodySupported: true
      actionsSupported: true
      imageSupported: true

      onNotification: function(notification) {
        if (root.dnd) {
          notification.expire()
          return
        }
        notification.tracked = true
        var snapshot = {
          id: notification.id,
          app: notification.appName,
          summary: notification.summary,
          body: notification.body,
          time: new Date(),
          ref: notification
        }
        var next = root.stored.slice()
        next.unshift(snapshot)
        if (next.length > 30) next.pop()
        root.stored = next
      }
    }
  }

  function dismiss(index) {
    var item = stored[index]
    if (item && item.ref && !item.ref.closed) item.ref.dismiss()
    var next = stored.slice()
    next.splice(index, 1)
    stored = next
  }

  function clearAll() {
    for (var i = 0; i < stored.length; i++) {
      if (stored[i].ref && !stored[i].ref.closed) stored[i].ref.dismiss()
    }
    stored = []
  }

  function relativeTime(date) {
    if (!date) return ""
    var diff = (Date.now() - date.getTime()) / 1000
    if (diff < 60) return "just now"
    if (diff < 3600) return Math.floor(diff / 60) + "m"
    if (diff < 86400) return Math.floor(diff / 3600) + "h"
    return Math.floor(diff / 86400) + "d"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.count > 0 && !root.dnd
    tooltipText: root.dnd ? "Do Not Disturb" : (root.count > 0 ? root.count + " notifications" : "No notifications")

    onPressed: function(b) {
      if (b === Qt.RightButton) root.dnd = !root.dnd
      else root.popupOpen = !root.popupOpen
    }
  }

  Common.PopupCard {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: 340
    contentHeight: Math.min(420, listColumn.implicitHeight + 60)

    Column {
      id: listColumn
      anchors.fill: parent
      spacing: 8

      Row {
        width: parent.width
        spacing: 8

        Text {
          text: "Notifications"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 13
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }

        Item { width: parent.width - 220; height: 1 }

        Common.PillButton {
          iconText: root.dnd ? "󰂛" : ""
          text: root.dnd ? "DND" : ""
          foreground: root.bar.foreground
          horizontalPadding: 8
          verticalPadding: 4
          active: root.dnd
          onClicked: root.dnd = !root.dnd
        }

        Common.PillButton {
          iconText: "󰎟"
          foreground: root.bar.foreground
          horizontalPadding: 8
          verticalPadding: 4
          enabled: root.count > 0
          opacity: enabled ? 1 : 0.4
          onClicked: root.clearAll()
        }
      }

      Flickable {
        width: parent.width
        height: Math.min(320, contentHeight)
        contentHeight: feedColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: feedColumn
          width: parent.width
          spacing: 4

          Repeater {
            model: root.stored

            Rectangle {
              required property var modelData
              required property int index

              width: feedColumn.width
              radius: 4
              color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.06)
              implicitHeight: notifContent.implicitHeight + 16

              Column {
                id: notifContent
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2

                Row {
                  width: parent.width

                  Text {
                    text: modelData ? (modelData.app || "App") : ""
                    color: Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    elide: Text.ElideRight
                    width: parent.width - timeText.implicitWidth - dismissBtn.width - 12
                  }

                  Text {
                    id: timeText
                    text: modelData ? root.relativeTime(modelData.time) : ""
                    color: Qt.darker(root.bar.foreground, 1.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: 10
                  }

                  Item { width: 6; height: 1 }

                  Common.PillButton {
                    id: dismissBtn
                    iconText: "󰅖"
                    foreground: root.bar.foreground
                    horizontalPadding: 4
                    verticalPadding: 0
                    iconSize: 10
                    onClicked: root.dismiss(index)
                  }
                }

                Text {
                  text: modelData ? (modelData.summary || "") : ""
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: 11
                  font.bold: true
                  wrapMode: Text.WordWrap
                  width: parent.width
                }

                Text {
                  visible: modelData && modelData.body !== ""
                  text: modelData ? (modelData.body || "") : ""
                  color: Qt.darker(root.bar.foreground, 1.2)
                  font.family: root.bar.fontFamily
                  font.pixelSize: 10
                  wrapMode: Text.WordWrap
                  width: parent.width
                  maximumLineCount: 3
                  elide: Text.ElideRight
                }
              }
            }
          }
        }
      }

      Text {
        visible: root.stored.length === 0
        text: root.dnd ? "Do Not Disturb is on" : "Nothing new"
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: 11
      }
    }
  }
}
