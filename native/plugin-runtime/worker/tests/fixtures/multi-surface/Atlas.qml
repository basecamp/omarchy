import QtQuick
import "Shared.js" as Shared

Rectangle {
  width: 320
  height: 200
  color: "#8f4b24"
  property int sharedActivationCount: Shared.activate()
  function receiveSurfaceIntent(data) {
    if (data && data.color) color = data.color
  }
}
