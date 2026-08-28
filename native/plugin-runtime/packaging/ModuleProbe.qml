import QtQuick 2.15
import Omarchy.PluginHost 1.0

Item {
  PluginHostInfo {
    id: pluginHost
  }

  Component.onCompleted: {
    if (!pluginHost.runtimeVersion || pluginHost.available)
      Qt.exit(1)
    console.info("plugin-package-module-ok", pluginHost.runtimeVersion)
    Qt.quit()
  }
}
