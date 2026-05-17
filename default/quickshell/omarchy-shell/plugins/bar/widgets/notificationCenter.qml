import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "notificationCenter"
  property var settings: ({})

  property bool popupOpen: false
  function closePopout() { popupOpen = false }

  // Always default to the pending tab when there's anything unseen, no
  // matter how the popup was opened (click, keybind/IPC, or the closePopout
  // path). Keeps the spec from drifting based on the user's last manual
  // tab selection.
  onPopupOpenChanged: {
    if (popupOpen) {
      activeTab = pendingCount > 0 ? "pending" : "past"
    }
  }

  // Look up the long-running notifications service through the shell host.
  readonly property var hostShell: bar && bar.shell ? bar.shell : null
  readonly property var notificationService: hostShell && typeof hostShell.firstPartyServiceFor === "function"
    ? hostShell.firstPartyServiceFor("omarchy.notifications")
    : null

  function isChromiumDerived(app, appIcon) {
    var source = (String(app || "") + "\n" + String(appIcon || "")).toLowerCase()
    return source.indexOf("chrom") >= 0 || source.indexOf("brave") >= 0 ||
           source.indexOf("vivaldi") >= 0 || source.indexOf("microsoft-edge") >= 0 ||
           source.indexOf("opera") >= 0
  }

  function sanitizeBody(s, app, appIcon) {
    var text = String(s || "").replace(/<img[^>]*>/gi, "")
    if (!isChromiumDerived(app, appIcon)) return text

    return text
      .replace(/^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>\s*/i, "")
      .replace(/^\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i, "")
  }

  readonly property int pendingCount: notificationService ? notificationService.pendingModel.count : 0
  readonly property int pastCount: notificationService ? notificationService.pastModel.count : 0
  readonly property bool dnd: notificationService ? notificationService.doNotDisturb : false

  // Which tab is active in the popup. Auto-selects pending when there's
  // something unseen; otherwise opens past.
  property string activeTab: "pending"

  readonly property string icon: {
    if (dnd) return "󰂛"
    if (pendingCount > 0) return "󱅫"
    return "󰂚"
  }

  // Theme palette (mirrors HistoryPanel's tokens so the popup matches the
  // rest of the notification stack).
  readonly property color colForeground: Color.foreground
  readonly property color colDim: Qt.darker(Color.foreground, 1.4)
  readonly property color colBorder: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18)
  readonly property color colSurface: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
  readonly property color colAccent: Color.accent
  readonly property int cardRadius: notificationService ? notificationService.cornerRadius : 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.pendingCount > 0 && !root.dnd
    tooltipText: root.dnd ? "Do Not Disturb"
      : (root.pendingCount > 0 ? root.pendingCount + " pending" : "No notifications")

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.notificationService) {
          root.notificationService.setDoNotDisturb(!root.notificationService.doNotDisturb)
        }
      } else {
        root.popupOpen = !root.popupOpen
      }
    }
  }

  // Service-side IPC (omarchy-shell-ipc notifications showHistory) flips
  // historyOpenRequested; we toggle our local popup state from here so the
  // keybind path lands in the same PopupCard the click path uses.
  Connections {
    target: root.notificationService
    ignoreUnknownSignals: true
    function onHistoryOpenRequested() {
      root.popupOpen = true
    }
  }

  Common.PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: 440
    contentHeight: 540

    ColumnLayout {
      anchors.fill: parent
      spacing: 10

      // ----------------------------------------- header
      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          text: "Notifications"
          font.family: root.bar ? root.bar.fontFamily : ""
          color: root.colForeground
          font.pixelSize: 14
          font.bold: true
        }

        Item { Layout.fillWidth: true }

        Rectangle {
          id: dndPill
          Layout.preferredHeight: 24
          Layout.preferredWidth: dndLabel.implicitWidth + dndGlyph.implicitWidth + 18
          radius: Math.min(12, root.cardRadius + 6)
          color: dndOn ? root.colAccent : root.colSurface
          border.color: dndOn ? root.colAccent : root.colBorder
          border.width: 1

          readonly property bool dndOn: !!root.notificationService && root.notificationService.doNotDisturb

          Row {
            anchors.centerIn: parent
            spacing: 4

            Text {
              id: dndGlyph
              text: dndPill.dndOn ? "󰂛" : "󰂚"
              font.family: root.bar ? root.bar.fontFamily : ""
              color: dndPill.dndOn ? Color.background : root.colDim
              font.pixelSize: 12
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: dndLabel
              text: dndPill.dndOn ? "DND on" : "DND off"
              font.family: root.bar ? root.bar.fontFamily : ""
              color: dndPill.dndOn ? Color.background : root.colDim
              font.pixelSize: 10
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.notificationService) root.notificationService.setDoNotDisturb(!dndPill.dndOn)
          }
        }
      }

      // ----------------------------------------- tabs
      RowLayout {
        Layout.fillWidth: true
        spacing: 0

        Repeater {
          model: [
            { key: "pending", label: "Pending",  count: root.pendingCount },
            { key: "past",    label: "Recently", count: root.pastCount }
          ]
          delegate: Rectangle {
            required property var modelData
            readonly property bool isActive: root.activeTab === modelData.key

            Layout.fillWidth: true
            Layout.preferredHeight: 30
            color: "transparent"

            Text {
              anchors.centerIn: parent
              text: modelData.label + (modelData.count > 0 ? "  " + modelData.count : "")
              font.family: root.bar ? root.bar.fontFamily : ""
              color: parent.isActive ? root.colForeground : root.colDim
              font.pixelSize: 12
              font.bold: parent.isActive
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 2
              color: parent.isActive ? root.colAccent : root.colBorder
              opacity: parent.isActive ? 1 : 0.4
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.activeTab = modelData.key
            }
          }
        }
      }

      // ----------------------------------------- action row
      RowLayout {
        Layout.fillWidth: true
        visible: (root.activeTab === "pending" && root.pendingCount > 0)
              || (root.activeTab === "past" && root.pastCount > 0)
        spacing: 8

        Item { Layout.fillWidth: true }

        Rectangle {
          Layout.preferredWidth: actionLabel.implicitWidth + 16
          Layout.preferredHeight: 22
          radius: Math.min(6, root.cardRadius)
          color: actionArea.containsMouse ? root.colBorder : "transparent"
          border.color: root.colBorder
          border.width: 1

          Text {
            id: actionLabel
            anchors.centerIn: parent
            text: root.activeTab === "pending" ? "Mark all as seen" : "Clear recent"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.colForeground
            font.pixelSize: 10
          }

          MouseArea {
            id: actionArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (!root.notificationService) return
              if (root.activeTab === "pending") root.notificationService.markAllSeen()
              else root.notificationService.clearPast()
            }
          }
        }
      }

      // ----------------------------------------- list
      ListView {
        id: listView
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 8

        readonly property bool onPending: root.activeTab === "pending"
        model: !root.notificationService ? null
              : (onPending ? root.notificationService.pendingModel : root.notificationService.pastModel)
        visible: count > 0

        delegate: Rectangle {
          id: rowCard
          required property int index
          required property string app
          required property string appIcon
          required property string summary
          required property string body
          required property string image
          required property int urgency
          required property double timestamp

          readonly property bool hasMedia: image.length > 0 && (
            image.indexOf("image://icon//") === 0 || image.indexOf("file://") === 0)
          readonly property string smallIconSource: image.length > 0 ? image : appIcon
          readonly property bool hasIcon: !hasMedia && smallIconSource.length > 0
          readonly property string sanitizedBody: root.sanitizeBody(body, app, appIcon)

          width: listView.width
          implicitHeight: rowContent.implicitHeight + 20
          radius: root.cardRadius
          color: "transparent"
          border.color: root.colBorder
          border.width: 1

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { /* no-op */ }
          }

          RowLayout {
            id: rowContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Item {
              Layout.preferredWidth: 32
              Layout.preferredHeight: 32
              Layout.alignment: Qt.AlignVCenter
              // Hide on icon load failure so unresolved themed-icon names
              // don't render Qt's broken-image placeholder.
              visible: (rowCard.hasIcon || rowCard.hasMedia) && rowIconImage.status !== Image.Error

              Image {
                id: rowIconImage
                anchors.fill: parent
                source: rowCard.hasMedia ? rowCard.image : rowCard.smallIconSource
                fillMode: rowCard.hasMedia ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                sourceSize.width: 32 * Screen.devicePixelRatio
                sourceSize.height: 32 * Screen.devicePixelRatio
                asynchronous: true
                smooth: true
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2

              Text {
                Layout.fillWidth: true
                visible: rowCard.summary.length > 0
                text: rowCard.summary
                font.family: root.bar ? root.bar.fontFamily : ""
                color: root.colForeground
                font.pixelSize: 13
                font.bold: true
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 1
              }

              Text {
                Layout.fillWidth: true
                visible: rowCard.sanitizedBody.length > 0
                text: rowCard.sanitizedBody
                font.family: root.bar ? root.bar.fontFamily : ""
                textFormat: Text.PlainText
                color: root.colDim
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
              }
            }

            Rectangle {
              Layout.preferredWidth: 18
              Layout.preferredHeight: 18
              Layout.alignment: Qt.AlignVCenter
              radius: Math.min(4, root.cardRadius)
              color: rowCloseArea.containsMouse ? root.colBorder : "transparent"

              Text {
                anchors.centerIn: parent
                text: "✕"
                font.family: root.bar ? root.bar.fontFamily : ""
                color: root.colDim
                font.pixelSize: 11
              }

              MouseArea {
                id: rowCloseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!root.notificationService) return
                  if (listView.onPending) root.notificationService.dismissPending(rowCard.index)
                  else root.notificationService.dismissPast(rowCard.index)
                }
              }
            }
          }
        }
      }

      // ----------------------------------------- empty state
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: listView.count === 0

        ColumnLayout {
          anchors.centerIn: parent
          spacing: 6

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: "󰂚"
            font.family: root.bar ? root.bar.fontFamily : ""
            color: root.colBorder
            font.pixelSize: 36
          }

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.activeTab === "pending"
              ? "Nothing waiting for you"
              : "Nothing recent"
            font.family: root.bar ? root.bar.fontFamily : ""
              ? "Nothing waiting for you"
              : "No past notifications"
            color: root.colDim
            font.pixelSize: 12
          }
        }
      }
    }
  }
}
