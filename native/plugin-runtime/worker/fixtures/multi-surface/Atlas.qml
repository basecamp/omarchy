import QtQuick
import "Shared.js" as Shared

Rectangle {
  width: 320
  height: 200
  color: "#8f4b24"
  property int sharedActivationCount: Shared.activate()
  property bool opened: false
  function open() { opened = true; color = "#24905b" }
}
