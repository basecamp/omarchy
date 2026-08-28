import QtQuick
import Omarchy.PluginHost

HostProbeItem {
  implicitWidth: 1
  implicitHeight: 1

  Component.onCompleted: {
    console.info("host-module-quickshell-smoke:", probeMarker)
  }
}
