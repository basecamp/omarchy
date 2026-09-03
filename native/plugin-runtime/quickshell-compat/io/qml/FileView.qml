import QtQml

QtObject {
  id: root

  property string path: ""
  property bool preload: true
  property bool blockLoading: false
  property bool blockAllReads: false
  property bool printErrors: true
  property bool blockWrites: false
  property bool atomicWrites: true
  property bool watchChanges: false
  property int maximumBytes: 524288
  readonly property bool loaded: loadedState
  property bool loadedState: false
  property string loadedText: ""
  signal loaded()
  signal loadFailed(int error)
  signal saved()
  signal saveFailed(int error)
  signal fileChanged()

  function packagedPath(value) {
    var candidate = String(value || "")
    if (candidate.indexOf("file:///plugin/") === 0)
      candidate = candidate.slice("file:///plugin/".length)
    if (!candidate || candidate.length > 240 || candidate[0] === "/"
        || candidate.indexOf("\\") !== -1 || candidate.indexOf("\0") !== -1)
      return ""
    var parts = candidate.split("/")
    for (var index = 0; index < parts.length; ++index) {
      if (!parts[index] || parts[index] === "." || parts[index] === "..")
        return ""
    }
    return candidate
  }

  function fail(error) {
    loadedState = false
    loadedText = ""
    loadFailed(error)
  }

  function reload() {
    if (blockAllReads) {
      fail(FileViewError.PermissionDenied)
      return
    }
    var relative = packagedPath(path)
    if (!relative) {
      fail(FileViewError.PermissionDenied)
      return
    }
    var limit = Math.max(1, Math.min(524288, maximumBytes))
    var value = runtime.readPackagedText(relative, limit)
    if (!value) {
      fail(FileViewError.FileNotFound)
      return
    }
    loadedText = value
    loadedState = true
    loaded()
  }

  function text() {
    if (!loadedState) reload()
    return loadedText
  }

  function data() {
    return text()
  }

  function setText(value) {
    saveFailed(FileViewError.PermissionDenied)
  }

  function setData(value) {
    saveFailed(FileViewError.PermissionDenied)
  }

  Component.onCompleted: if (preload && path) reload()
  onPathChanged: {
    loadedState = false
    loadedText = ""
    if (preload && path) reload()
  }
}
