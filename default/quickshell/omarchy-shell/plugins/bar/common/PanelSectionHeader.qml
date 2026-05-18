import QtQuick

// Small-caps-style label that introduces a panel section ("DNS provider",
// "Wi-Fi networks", "Output device", "Paired devices"). Sits between a
// PanelSeparator and the content rows.
Text {
  id: root

  property color foreground: "#cacccc"
  property string fontFamily: "JetBrainsMono Nerd Font"
  property real fontSize: 10

  color: Qt.darker(foreground, 1.4)
  font.family: fontFamily
  font.pixelSize: fontSize
  font.bold: true
}
