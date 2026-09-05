import QtQuick
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var shell: null
  property string dictationState: "idle"

  function update(raw) {
    var data = Util.parseModuleJson(raw)
    dictationState = String(data.alt || data.class || "idle")
  }

  Process {
    command: ["omarchy-voxtype-status"]
    running: true
    stdout: SplitParser {
      onRead: function(data) { root.update(data) }
    }
  }
}
