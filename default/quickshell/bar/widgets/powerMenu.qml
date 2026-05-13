import QtQuick
import Quickshell
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "powerMenu"
  property var settings: ({})

  property bool popupOpen: false

  function closePopout() { popupOpen = false }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function run(command) {
    if (root.bar) root.bar.run(command)
    popupOpen = false
  }

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "⏻"
    fontSize: 14
    tooltipText: "Power menu"
    onPressed: function() { root.popupOpen = !root.popupOpen }
  }

  Common.PopupCard {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: 220
    contentHeight: column.implicitHeight + 28

    Column {
      id: column
      anchors.fill: parent
      spacing: 6

      Text {
        text: "Power"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: 12
        font.bold: true
      }

      Common.PillButton {
        width: parent.width
        iconText: ""
        text: "Lock"
        foreground: root.bar.foreground
        horizontalPadding: 10
        verticalPadding: 8
        onClicked: root.run("loginctl lock-session")
      }

      Common.PillButton {
        width: parent.width
        iconText: "󰒲"
        text: "Suspend"
        foreground: root.bar.foreground
        horizontalPadding: 10
        verticalPadding: 8
        onClicked: root.run("systemctl suspend")
      }

      Common.PillButton {
        width: parent.width
        iconText: ""
        text: "Log out"
        foreground: root.bar.foreground
        horizontalPadding: 10
        verticalPadding: 8
        onClicked: root.run("hyprctl dispatch exit")
      }

      Common.PillButton {
        width: parent.width
        iconText: ""
        text: "Reboot"
        foreground: root.bar.foreground
        horizontalPadding: 10
        verticalPadding: 8
        onClicked: root.run("systemctl reboot")
      }

      Common.PillButton {
        width: parent.width
        iconText: ""
        text: "Shut down"
        foreground: root.bar.urgent
        horizontalPadding: 10
        verticalPadding: 8
        onClicked: root.run("systemctl poweroff")
      }
    }
  }
}
