import QtQuick
import qs.Commons

// ErrorState: the failure surface with the doctrine's recovery path baked
// in — what happened, a human explanation, and [Retry] / [Details]
// (PRODUCT_DOCTRINE.md: never `Process exited with status 1`).
Column {
  id: root

  property string title: ""
  property string explanation: ""

  // Raw technical detail, revealed only on request (progressive disclosure,
  // Rule 5). Set to "" to hide the Details affordance entirely.
  property string detail: ""

  property bool hasCursor: false

  signal retryClicked()
  signal detailsToggled(bool visible)

  readonly property bool _hot: mouse.containsMouse || hasCursor
  property bool _detailsOpen: false

  spacing: Style.space(8)

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    text: "\u26a0"
    color: Tokens.state.danger
    font.family: Style.font.family
    font.pixelSize: Style.font.display
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    visible: root.title !== ""
    text: root.title
    color: Tokens.text.primary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.bold: true
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    visible: root.explanation !== ""
    text: root.explanation
    color: Tokens.text.secondary
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignHCenter
    width: Math.min(root.width || 0, 420)
    wrapMode: Text.WordWrap
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(8)

    Button {
      text: "Try again"
      focusable: true
      onClicked: root.retryClicked()
    }

    Button {
      visible: root.detail !== ""
      text: root._detailsOpen ? "Hide details" : "Details"
      focusable: true
      onClicked: {
        root._detailsOpen = !root._detailsOpen
        root.detailsToggled(root._detailsOpen)
      }
    }
  }

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    visible: root._detailsOpen && root.detail !== ""
    width: Math.min(root.width || 480, 480)
    height: detailText.implicitHeight + Style.space(12)
    radius: Math.max(4, Math.round(Style.cornerRadius * 0.5))
    color: Tokens.surface.raised

    Text {
      id: detailText
      anchors.fill: parent
      anchors.margins: Style.space(6)
      text: root.detail
      color: Tokens.text.secondary
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WrapAnywhere
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.ArrowCursor
  }
}
