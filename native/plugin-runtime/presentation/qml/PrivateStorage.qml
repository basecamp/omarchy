import QtQuick

QtObject {
  id: root

  property int quotaBytes: 1048576
  property int itemBytes: 4096
  property var activeCalls: []

  function decodeText(value) {
    var bytes = null
    if (value instanceof ArrayBuffer) bytes = new Uint8Array(value)
    else if (ArrayBuffer.isView(value))
      bytes = new Uint8Array(value.buffer, value.byteOffset, value.byteLength)
    if (!bytes || bytes.length < 8 || bytes[0] !== 1 || bytes[1] !== 0
        || bytes[2] !== 0 || bytes[3] !== 0) return null
    var length = (((bytes[4] << 24) >>> 0) + (bytes[5] << 16)
      + (bytes[6] << 8) + bytes[7]) >>> 0
    if (length === 0 || length > itemBytes || bytes.length !== length + 8) return null
    var encoded = ""
    for (var index = 8; index < bytes.length; ++index)
      encoded += "%" + bytes[index].toString(16).padStart(2, "0")
    try { return decodeURIComponent(encoded) } catch (_) { return null }
  }

  function watch(call, success, failure) {
    if (!call) {
      failure("request-rejected")
      return
    }
    activeCalls = activeCalls.concat([call])
    var done = function() {
      if (!call.finished) return
      try { call.finishedChanged.disconnect(done) } catch (_) {}
      root.activeCalls = root.activeCalls.filter(function(item) { return item !== call })
      if (call.ok) success(call.value)
      else failure(String(call.error || "request-failed"))
    }
    if (call.finished) done()
    else call.finishedChanged.connect(done)
  }

  function readText(key, success, failure) {
    watch(runtime.invoke("storage.private", "read", {
      key: key, quotaBytes: quotaBytes, itemBytes: itemBytes
    }), function(value) { success(decodeText(value)) }, failure)
  }

  function writeText(key, value, success, failure) {
    watch(runtime.invoke("storage.private", "write", {
      key: key, quotaBytes: quotaBytes, itemBytes: itemBytes, value: String(value)
    }), success, failure)
  }
}
