import QtQuick
import qs.Ui
import qs.Commons

Column {
  id: root
  required property var bar
  required property string displayTitle
  required property string displayArtist
  required property bool displayPlaying
  required property bool displayCanGoPrevious
  required property bool displayCanPlayPause
  required property bool displayCanGoNext
  required property bool cursorActive
  required property int cursorIndex
  required property var actions
  signal controlHovered(int index)
  signal actionRequested(string action)

  readonly property bool hasMedia: displayTitle !== "" || displayArtist !== ""
  readonly property var enabledActions: [
    displayCanGoPrevious,
    displayCanPlayPause,
    displayCanGoNext
  ]
  width: parent ? parent.width : 0
  spacing: Style.space(6)
  visible: hasMedia

  PanelSectionHeader {
    text: "MEDIA"
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
  }

  Column {
    width: parent.width
    spacing: Style.space(1)

    Text {
      width: parent.width
      text: root.displayTitle || "Media"
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: root.displayArtist
      visible: text !== ""
      color: Qt.darker(root.bar.foreground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(6)

    Repeater {
      model: root.actions
      delegate: Button {
        required property string modelData
        required property int index
        iconText: index === 0 ? "󰒮" : (index === 1 ? (root.displayPlaying ? "󰏤" : "󰐊") : "󰒭")
        foreground: root.bar.foreground
        horizontalPadding: index === 1 ? Style.spacing.panelGap : Style.spacing.controlPaddingX
        verticalPadding: Style.spacing.controlPaddingY
        iconSize: index === 1 ? Style.font.iconLarge : Style.font.icon
        tooltipText: index === 0 ? "Previous track" : (index === 1 ? "Play/Pause" : "Next track")
        enabled: root.enabledActions[index]
        opacity: enabled ? 1.0 : 0.4
        hasCursor: root.cursorActive && root.cursorIndex === index
        onHovered: function(isHovered) { if (isHovered) root.controlHovered(index) }
        onClicked: if (enabled) root.actionRequested(modelData)
      }
    }
  }
}
