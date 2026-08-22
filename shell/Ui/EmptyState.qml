import QtQuick
import qs.Commons

// EmptyState: the "nothing here yet" surface for lists, search results, and
// panels. A labeled empty state is a visible affordance (Rule 4) — it tells
// the user the surface exists and what belongs in it.
Column {
  id: root

  property string iconText: "\u25cb"
  property string title: ""
  property string message: ""

  spacing: Style.space(8)

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    text: root.iconText
    color: Tokens.text.disabled
    font.family: Style.font.family
    font.pixelSize: Style.font.display
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    visible: root.title !== ""
    text: root.title
    color: Tokens.text.secondary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.bold: true
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    visible: root.message !== ""
    text: root.message
    color: Tokens.text.disabled
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignHCenter
    width: Math.min(root.width || 0, 420)
    wrapMode: Text.WordWrap
  }
}
