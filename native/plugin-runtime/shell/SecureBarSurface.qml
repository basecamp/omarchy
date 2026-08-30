import QtQuick
import Omarchy.PluginHost 1.0

Item {
  id: root

  required property var surfaceService
  required property string surfaceKey
  required property string generation
  required property int maximumWidth
  required property int maximumHeight

  implicitWidth: maximumWidth
  implicitHeight: maximumHeight

  RemotePluginSurface {
    id: remote
    anchors.fill: parent
    Component.onCompleted: root.surfaceService.attach(root.surfaceKey, remote)
  }
}
