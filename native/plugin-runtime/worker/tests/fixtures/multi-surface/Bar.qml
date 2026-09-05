import QtQuick
import "Shared.js" as Shared

Rectangle {
  width: 72
  height: 48
  color: "#245b8f"
  property int sharedActivationCount: Shared.activate()
}
