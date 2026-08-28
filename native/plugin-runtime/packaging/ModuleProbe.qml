import QtQuick 2.15
import Omarchy.PluginHost 1.0

Item {
  PluginHostInfo {
    id: pluginHost
  }

  RemotePluginSurface {
    id: remoteSurface
    visible: false
  }

  Component.onCompleted: {
    if (!pluginHost.runtimeVersion || pluginHost.available ||
        remoteSurface.connected || remoteSurface.ready)
      Qt.exit(1)
    console.info("plugin-package-module-ok", pluginHost.runtimeVersion,
                 remoteSurface.inspectionState)
    Qt.quit()
  }
}
