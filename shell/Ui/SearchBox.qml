import QtQuick
import qs.Commons

// Search field: kit TextField with a magnifier glyph, a clear button once text
// is present, and `Esc clears` behavior. Start menu, Settings search, and
// every filterable list use this one component.
//
// Do not `import QtQuick.Controls` here: that shadows qs.Ui.TextField with the
// stock QQC field, which paints a solid near-white bar on dark glass.
TextField {
  id: root

  property bool showClearButton: true

  signal cleared()

  font.pixelSize: Style.font.body
  leftPadding: Style.space(28)
  rightPadding: showClearButton && text.length > 0 ? Style.space(28) : horizontalPadding

  // Magnifier glyph.
  Text {
    visible: root.text.length === 0
    text: "\u2315"
    color: Tokens.text.secondary
    font.family: Style.font.family
    font.pixelSize: root.font.pixelSize
    anchors.left: parent.left
    anchors.leftMargin: Style.space(9)
    anchors.verticalCenter: parent.verticalCenter
  }

  // Clear affordance. Mouse-only operation rule: never make the user select
  // all and delete to reset a search.
  IconButton {
    visible: root.showClearButton && root.text.length > 0
    iconText: "\u00d7"
    size: 20
    glyphSize: Style.font.body
    anchors.right: parent.right
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    onClicked: {
      root.text = ""
      root.cleared()
      root.forceActiveFocus()
    }
  }

  Keys.onEscapePressed: {
    if (text.length > 0) {
      text = ""
      root.cleared()
    } else {
      focus = false
    }
  }
}
