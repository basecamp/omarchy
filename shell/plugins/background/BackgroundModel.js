function parseAvailableMemoryKiB(raw) {
  var match = /^MemAvailable:\s+(\d+)\s+kB$/m.exec(String(raw || ""))
  return match ? Number(match[1]) : -1
}

function isLowMemory(availableMemoryKiB, limitKiB) {
  var available = Number(availableMemoryKiB)
  var limit = Number(limitKiB)
  return isFinite(available) && available >= 0 && isFinite(limit) && available < limit
}

if (typeof module !== "undefined") {
  module.exports = {
    parseAvailableMemoryKiB: parseAvailableMemoryKiB,
    isLowMemory: isLowMemory
  }
}
