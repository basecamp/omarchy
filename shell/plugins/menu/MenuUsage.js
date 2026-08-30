function normalizeRecord(record) {
  var count = Math.max(0, Number(record && record.count) || 0)
  var lastUsedAt = Math.max(0, Number(record && record.lastUsedAt) || 0)
  return count > 0 ? { count: count, lastUsedAt: lastUsedAt } : null
}

function parse(rawText) {
  var next = {}
  try {
    var parsed = JSON.parse(String(rawText || "{}"))
    var source = parsed && parsed.version === 1 && parsed.records && typeof parsed.records === "object" ? parsed.records : {}
    for (var id in source) {
      var record = normalizeRecord(source[id])
      if (id && record) next[id] = record
    }
  } catch (e) {
    next = {}
  }
  return next
}

function count(records, itemId) {
  var record = records && records[String(itemId || "")]
  return record ? Math.max(0, Number(record.count) || 0) : 0
}

function lastUsedAt(records, itemId) {
  var record = records && records[String(itemId || "")]
  return record ? Math.max(0, Number(record.lastUsedAt) || 0) : 0
}

function record(records, itemId, now) {
  var id = String(itemId || "")
  var next = Object.assign({}, records || {})
  if (!id) return next
  next[id] = {
    count: count(next, id) + 1,
    lastUsedAt: Math.max(0, Number(now) || 0)
  }
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    parse: parse,
    count: count,
    lastUsedAt: lastUsedAt,
    record: record
  }
}
