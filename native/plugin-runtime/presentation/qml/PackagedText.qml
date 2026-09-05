import QtQuick

QtObject {
  property string path: ""
  property int maximumBytes: 524288
  property bool preload: true
  property string contents: ""
  signal loaded()

  function text() { return contents }
  function reload() { load() }
  function load() {
    contents = runtime.readPackagedText(path, maximumBytes)
    loaded()
  }

  Component.onCompleted: if (preload && path) load()
  onPathChanged: if (preload && path) load()
}
