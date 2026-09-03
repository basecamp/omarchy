import QtQuick

Text {
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  color: foreground
  font.family: fontFamily
  font.bold: true
  font.pixelSize: Style.font.caption
  textFormat: Text.PlainText
}
