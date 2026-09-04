import QtQuick

Text {
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real letterSpacing: 0

  color: foreground
  font.family: fontFamily
  font.bold: true
  font.pixelSize: Style.font.caption
  font.letterSpacing: letterSpacing
  textFormat: Text.PlainText
}
