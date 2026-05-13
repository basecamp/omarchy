pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Noctalia compat shim. activate-linux and a few other plugins display
// distro/host info. We parse /etc/os-release lazily.
QtObject {
  id: root

  property string osPretty: ""
  property string osName: ""
  property string osVersion: ""
  property string hostname: ""

  property Process osReleaseProc: Process {
    command: ["bash", "-c",
      "( . /etc/os-release && printf '%s\\t%s\\t%s\\n' \"$PRETTY_NAME\" \"$NAME\" \"$VERSION_ID\" ); hostname"]
    onExited: {
      var text = String(osReleaseStdout.text || "").trim().split("\n")
      if (text.length >= 1) {
        var fields = text[0].split("\t")
        root.osPretty = fields[0] || ""
        root.osName = fields[1] || ""
        root.osVersion = fields[2] || ""
      }
      if (text.length >= 2) root.hostname = text[1].trim()
    }
    stdout: StdioCollector {
      id: osReleaseStdout
      waitForEnd: true
    }
  }

  Component.onCompleted: osReleaseProc.running = true
}
