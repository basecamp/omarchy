import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "ReminderFlowModel.js" as ReminderFlowModel

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string step: "minutes"
  property string minutes: ""
  property string filterText: ""
  property string fontFamily: Style.font.menuFamily

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int cardWidth: Math.min(Style.space(300), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(contentMargin * 2 + headerHeight, panel.height - Style.gapsOut * 2)
  readonly property string promptText: root.step === "message" ? "Reminder message" : "Remind in minutes"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    root.opened = true
    root.step = "minutes"
    root.minutes = ""
    root.filterText = ""

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omarchy.reminders")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
  }

  function submit() {
    var selection = root.filterText

    if (root.step === "minutes") {
      var nextMinutes = ReminderFlowModel.validMinutes(selection)

      if (!selection.trim()) {
        root.dismiss()
        return
      }

      if (!nextMinutes) {
        Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-notification-send", "Invalid reminder", "Enter the number of minutes"])
        return
      }

      root.minutes = nextMinutes
      root.step = "message"
      root.filterText = ""
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      return
    }

    if (root.step === "message") {
      var args = [root.omarchyPath + "/bin/omarchy-reminder"].concat(ReminderFlowModel.reminderArgs(root.minutes, selection))
      root.dismiss()
      Quickshell.execDetached(args)
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-reminders"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.isFilterEditKey(event)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit()
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.filterText || (root.promptText + "...")
          color: root.foreground
          opacity: root.filterText ? 1 : 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          elide: Text.ElideRight
        }
      }
    }
  }
}
