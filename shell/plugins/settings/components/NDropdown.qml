import QtQuick
import QtQuick.Controls
import qs.Commons

// Themed ComboBox + popup. Anchors below the trigger, paints with the host
// shell's foreground/background palette, and inherits the shell-wide corner
// radius so nothing renders rounded when the user has set sharp corners.
Item {
  id: root

  property string label: ""
  property string value: ""
  property var options: []
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property int cornerRadius: 0
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight
  property bool showLabel: true

  signal changed(string value)

  implicitWidth: Style.spacing.dropdownWidth
  implicitHeight: showLabel ? rowHeight + Style.spacing.huge : rowHeight

  Column {
    anchors.fill: parent
    spacing: Style.spacing.labelGap

    Text {
      visible: root.showLabel && root.label !== ""
      text: root.label
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    ComboBox {
      id: combo
      width: parent.width
      height: root.rowHeight
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      model: root.options
      currentIndex: {
        for (var i = 0; i < model.length; i++) if (model[i] === root.value) return i
        return -1
      }
      onActivated: function(index) {
        if (index >= 0 && index < model.length) root.changed(model[index])
      }

      background: Rectangle {
        color: combo.activeFocus
          ? Style.focusFillFor(root.foreground, root.accent)
          : (combo.hovered
            ? Style.hoverFillFor(root.foreground, root.accent)
            : Style.normalFillFor(root.foreground, root.accent))
        border.color: combo.activeFocus
          ? Style.focusBorderFor(root.foreground, root.accent)
          : (combo.hovered
            ? Style.hoverBorderFor(root.foreground, root.accent)
            : Style.normalBorderFor(root.foreground, root.accent))
        border.width: combo.activeFocus
          ? Style.focusBorderWidth
          : (combo.hovered ? Style.hoverBorderWidth : Style.normalBorderWidth)
        radius: root.cornerRadius
      }

      contentItem: Text {
        leftPadding: Style.spacing.controlGap
        rightPadding: Style.space(24)
        text: combo.displayText
        color: root.foreground
        font: combo.font
        verticalAlignment: Text.AlignVCenter
      }

      indicator: Text {
        x: combo.width - width - Style.spacing.controlGap
        y: combo.topPadding + (combo.availableHeight - height) / 2
        text: "▾"
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      popup: Popup {
        // Anchor the popup directly under the field, full width, sharp/round
        // matching the shell radius. Override the native white-with-blue look.
        y: combo.height
        width: combo.width
        implicitHeight: Math.min(contentItem.implicitHeight, root.popupRowHeight * 8)
        padding: Style.spacing.hairline

        background: Rectangle {
          color: root.background
          border.color: Style.normalBorderFor(root.foreground, root.accent)
          border.width: Style.normalBorderWidth
          radius: root.cornerRadius
        }

        contentItem: ListView {
          clip: true
          implicitHeight: contentHeight
          model: combo.delegateModel
          currentIndex: combo.highlightedIndex
          boundsBehavior: Flickable.StopAtBounds
        }
      }

      delegate: ItemDelegate {
        required property var modelData
        required property int index

        width: combo.width
        height: root.popupRowHeight
        padding: 0

        contentItem: Text {
          text: String(modelData)
          color: index === combo.highlightedIndex ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          leftPadding: Style.spacing.controlPaddingX
          rightPadding: Style.spacing.controlPaddingX
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }

        background: Rectangle {
          color: index === combo.highlightedIndex
            ? Style.hoverFillFor(root.foreground, root.accent)
            : "transparent"
          radius: 0
        }
      }
    }
  }
}
