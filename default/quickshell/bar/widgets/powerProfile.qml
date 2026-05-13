import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "powerProfile"
  property var settings: ({})

  property bool popupOpen: false

  function closePopout() { popupOpen = false }

  readonly property var profileGlyphs: ({
    [PowerProfile.PowerSaver]: "󰌪",
    [PowerProfile.Balanced]: "󰂄",
    [PowerProfile.Performance]: "󰓅"
  })

  readonly property var profileLabels: ({
    [PowerProfile.PowerSaver]: "Power Saver",
    [PowerProfile.Balanced]: "Balanced",
    [PowerProfile.Performance]: "Performance"
  })

  readonly property bool available: PowerProfiles.profile !== undefined
  readonly property int current: PowerProfiles.profile

  visible: available
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function setProfile(profile) {
    PowerProfiles.profile = profile
  }

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.profileGlyphs[root.current] || ""
    tooltipText: "Power profile: " + (root.profileLabels[root.current] || "Unknown")
    onPressed: function() { root.popupOpen = !root.popupOpen }
  }

  Common.PopupCard {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: 240
    contentHeight: column.implicitHeight + 28

    Column {
      id: column
      anchors.fill: parent
      spacing: 6

      Text {
        text: "Power Profile"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: 12
        font.bold: true
      }

      Repeater {
        model: [
          { profile: PowerProfile.PowerSaver, label: "Power Saver", glyph: "󰌪" },
          { profile: PowerProfile.Balanced, label: "Balanced", glyph: "󰂄" },
          { profile: PowerProfile.Performance, label: "Performance", glyph: "󰓅" }
        ]

        Common.PillButton {
          required property var modelData

          width: parent.width
          iconText: modelData.glyph
          text: modelData.label
          foreground: root.bar.foreground
          horizontalPadding: 10
          verticalPadding: 8
          active: root.current === modelData.profile
          enabled: modelData.profile !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile
          opacity: enabled ? 1 : 0.4
          onClicked: { root.setProfile(modelData.profile); root.popupOpen = false }
        }
      }
    }
  }
}
