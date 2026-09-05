import QtQuick
import Omarchy.PluginHost 1.0

Item {
  RemotePluginSurface {
    id: remoteSurface
    visible: false
  }

  Component.onCompleted: {
    if (!PluginManager.runtimeVersion || PluginManager.available ||
        PluginManager.count !== 0 ||
        remoteSurface.connected || remoteSurface.ready)
      Qt.exit(1)
    Qt.quit()
  }
}
