import QtQuick
import Omarchy.PluginHost 1.0

Item {
  PluginHostInfo {
    id: pluginHost
  }

  PluginSurfaceService {
    id: surfaceService
  }

  RemotePluginSurface {
    id: remoteSurface
    visible: false
  }

  Component.onCompleted: {
    if (!pluginHost.runtimeVersion || pluginHost.available ||
        surfaceService.available || surfaceService.surfaces.length !== 0 ||
        remoteSurface.connected || remoteSurface.ready)
      Qt.exit(1)
    Qt.quit()
  }
}
