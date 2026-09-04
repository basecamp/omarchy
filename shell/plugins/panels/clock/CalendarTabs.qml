import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string selected: "calendar"
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal tabRequested(string tab)

  readonly property var tabs: [
    { id: "calendar", label: "Calendar" },
    { id: "agenda", label: "Agenda" },
    { id: "plan", label: "Plan" }
  ]

  implicitWidth: tabsRow.implicitWidth
  implicitHeight: tabsRow.implicitHeight

  Row {
    id: tabsRow
    spacing: Style.spacing.xs

    Repeater {
      model: root.tabs

      Button {
        focusable: true
        required property var modelData
        width: Style.space(94)
        height: Style.space(30)
        text: modelData.label
        selected: root.selected === modelData.id
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: root.tabRequested(modelData.id)
      }
    }
  }
}
