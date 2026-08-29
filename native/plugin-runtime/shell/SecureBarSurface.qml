import QtQuick
import Omarchy.PluginHost 1.0

Item {
  id: root

  required property var host
  required property var surfaceService
  property string moduleName: ""
  readonly property var declaration: host.declarationFor(moduleName)

  visible: declaration !== null
  implicitWidth: declaration ? declaration.maximumWidth : 0
  implicitHeight: declaration ? declaration.maximumHeight : 0

  RemotePluginSurface {
    id: remote
    anchors.fill: parent
    Component.onCompleted: if (root.declaration)
      root.surfaceService.attach(root.declaration.surfaceKey, remote)
  }
}
