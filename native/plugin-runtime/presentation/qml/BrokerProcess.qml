import QtQuick

QtObject {
  id: root

  property bool running: false
  property var command: []
  property StdioCollector stdout: null
  property StdioCollector stderr: null
  property var call: null
  property int serial: 0
  signal exited(int exitCode)

  function decode(value) {
    if (typeof value === "string") return value
    if (call && typeof call.utf8Text === "string") return call.utf8Text
    return ""
  }

  function finish(exitCode, output, error) {
    if (stdout) {
      stdout.text = output || ""
      stdout.streamFinished()
    }
    if (stderr) {
      stderr.text = error || ""
      stderr.streamFinished()
    }
    running = false
    exited(exitCode)
  }

  function observe(nextCall, transform) {
    call = nextCall
    if (!call) {
      finish(1, "", "Broker request was rejected")
      return
    }
    var observed = call
    var ticket = ++serial
    var done = function() {
      if (!observed.finished) return
      try { observed.finishedChanged.disconnect(done) } catch (_) {}
      if (observed !== root.call || ticket !== root.serial) return
      if (!observed.ok) {
        root.finish(1, "", String(observed.error || "Request failed"))
        return
      }
      var value = root.decode(observed.value)
      root.finish(0, transform ? transform(value) : value, "")
    }
    if (observed.finished) done()
    else observed.finishedChanged.connect(done)
  }

  function start() {
    finish(1, "", "No broker operation was selected")
  }

  onRunningChanged: if (running) Qt.callLater(start)
}
