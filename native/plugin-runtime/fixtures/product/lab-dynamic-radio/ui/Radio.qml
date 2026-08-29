import QtQuick
import QtQml as Qml

Rectangle {
  id: root
  width: 640
  height: 480
  color: call && call.finished && call.ok ? "#176b3a" : "#552020"
  property var call: null
  property string status: "LOADING"
  function finish() {
    if (!call || !call.finished) return
    status = call.ok ? "RADIO AUTHORIZED" : "RADIO DENIED"
  }
  Qml.Component.onCompleted: {
    call = runtime.invoke("fetch", {
      demandScope: '{"methods":["GET"],"origins":["https://all.api.radio-browser.info"]}',
      payload: {operation: "radio-directory.world", limit: 1}
    })
    if (call && call.finished) finish()
  }
  Qml.Connections { target: root.call; function onFinishedChanged() { root.finish() } }
  Qml.Connections {
    target: runtime
    function onPermissionsChanged() {
      if (runtime.permissionState("network.fetch", "fetch") !== "granted")
        root.status = "RADIO REVOKED"
    }
  }
  Text { anchors.centerIn: parent; text: root.status; color: "white"; font.pixelSize: 28 }
}
