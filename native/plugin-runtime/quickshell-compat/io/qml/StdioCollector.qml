import QtQml

QtObject {
  id: root

  property bool waitForEnd: false
  property int maximumBytes: 262144
  readonly property string text: collectedText
  // Pure QML cannot expose QByteArray. Keeping data present preserves common
  // truthiness/string use without introducing a native parser or byte source.
  readonly property var data: collectedText
  property string collectedText: ""
  signal streamFinished()
  signal truncated()

  function utf8Bytes(value) {
    try { return unescape(encodeURIComponent(value)).length }
    catch (_) { return -1 }
  }

  function bounded(value) {
    var candidate = String(value === undefined || value === null ? "" : value)
    var limit = Math.max(0, Math.min(1048576, maximumBytes))
    var bytes = utf8Bytes(candidate)
    if (bytes >= 0 && bytes <= limit) return candidate
    if (bytes < 0) {
      truncated()
      return ""
    }
    var low = 0
    var high = Math.min(candidate.length, limit)
    while (low < high) {
      var middle = Math.ceil((low + high) / 2)
      var prefixBytes = utf8Bytes(candidate.slice(0, middle))
      if (prefixBytes >= 0 && prefixBytes <= limit) low = middle
      else high = middle - 1
    }
    truncated()
    return candidate.slice(0, low)
  }

  function setText(value) {
    collectedText = bounded(value)
  }

  function append(value) {
    setText(collectedText + String(value === undefined || value === null ? "" : value))
  }

  function clear() {
    collectedText = ""
  }
}
