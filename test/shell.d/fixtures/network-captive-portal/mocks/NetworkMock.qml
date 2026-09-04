pragma Singleton
import QtQuick
import Quickshell.Networking

QtObject {
  property int backend: NetworkBackendType.NetworkManager
  property bool wifiEnabled: true
  property bool canCheckConnectivity: true
  property bool connectivityCheckEnabled: true
  property int connectivity: NetworkConnectivity.Full
  property int checks: 0
  function checkConnectivity() { checks++ }

  property var devices: ({ values: [wifi] })
  property QtObject wifi: QtObject {
    property int type: DeviceType.Wifi
    property string name: "test-wifi"
    property bool connected: true
    property bool scannerEnabled: false
    property var networks: ({ values: [network] })
  }
  property QtObject network: QtObject {
    property string name: "Guest Wi-Fi"
    property bool connected: true
    property bool known: true
    property bool stateChanging: false
    property real signalStrength: 0.8
    property int security: WifiSecurityType.Open
    signal connectionFailed(int reason)
  }
}
