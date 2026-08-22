import QtQuick
import qs.Commons

// Toast: transient notification card for operation results (Rule 6 — every
// consequential operation reports its result with a recovery path). The
// visual card only; queueing and screen placement belong to the
// notification service/surface.
//
// `tone` picks the semantic state color stripe; actions render as buttons.
Card {
  id: root

  property string title: ""
  property string message: ""

  // "accent" | "success" | "danger" | "warning" | "info"
  property string tone: "accent"

  // Optional action labels; each click emits `actionClicked(index)` and
  // dismisses unless the handler keeps it alive.
  property var actions: []

  signal actionClicked(int index)
  signal dismissed()

  readonly property color _tone: tone === "danger" ? Tokens.state.danger
    : tone === "success" ? Tokens.state.success
    : tone === "warning" ? Tokens.state.warning
    : tone === "info" ? Tokens.state.info
    : Tokens.accent.primary

  elevation: "raised"
  implicitWidth: 360
  implicitHeight: column.implicitHeight + Style.spacing.controlPaddingY * 2

  // State stripe: color plus the title carrying meaning, so the tone is
  // never signaled by color alone.
  Rectangle {
    width: Style.space(3)
    height: parent.height
    radius: parent.radius
    color: root._tone
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.controlPaddingX
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    Text {
      text: root.title
      color: Tokens.text.primary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
      width: parent.width
      elide: Text.ElideRight
    }

    Text {
      visible: root.message !== ""
      text: root.message
      color: Tokens.text.secondary
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      width: parent.width
      wrapMode: Text.WordWrap
    }

    Row {
      spacing: Style.space(8)

      Repeater {
        model: root.actions

        delegate: Button {
          required property var modelData
          required property int index
          text: typeof modelData === "string" ? modelData : String(modelData.label || "")
          focusable: true
          onClicked: {
            root.actionClicked(index)
            root.dismissed()
          }
        }
      }
    }
  }
}
