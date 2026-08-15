function parseEmojis(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    return Array.isArray(data) ? data : []
  } catch (e) {
    return []
  }
}

function normalizeRecentEmojis(values, limit) {
  var source = Array.isArray(values) ? values : []
  var max = limit === undefined || limit === null ? source.length : Number(limit)
  if (isNaN(max)) max = source.length
  max = Math.max(0, Math.floor(max))

  var out = []
  var seen = {}

  for (var i = 0; i < source.length && out.length < max; i++) {
    var emoji = typeof source[i] === "string" ? source[i] : ""
    if (!emoji || seen[emoji]) continue
    seen[emoji] = true
    out.push(emoji)
  }

  return out
}

function parseRecentEmojis(raw) {
  try {
    return normalizeRecentEmojis(JSON.parse(String(raw || "")))
  } catch (e) {
    return []
  }
}

function addRecentEmoji(recentEmojis, emoji, limit, emojis) {
  var recent = normalizeRecentEmojis([emoji].concat(Array.isArray(recentEmojis) ? recentEmojis : []))
  if (!Array.isArray(emojis)) return normalizeRecentEmojis(recent, limit)

  var valid = {}
  for (var i = 0; i < emojis.length; i++) {
    var item = emojis[i]
    if (item && item.e) valid[item.e] = true
  }

  var out = []
  for (var j = 0; j < recent.length; j++) {
    if (valid[recent[j]]) out.push(recent[j])
  }
  return normalizeRecentEmojis(out, limit)
}

function normalizedQuery(query) {
  return String(query || "").trim().toLowerCase()
}

function keywordText(item) {
  return String((item && item.k) || "").toLowerCase()
}

function filterEmojis(emojis, query, limit) {
  var values = Array.isArray(emojis) ? emojis : []
  var needle = normalizedQuery(query)
  var max = limit === undefined || limit === null ? 1000 : Number(limit)
  if (isNaN(max)) max = 1000
  max = Math.max(0, max)
  if (max === 0) return []

  var out = []

  for (var i = 0; i < values.length; i++) {
    var item = values[i]
    if (!item || !item.e) continue
    if (!needle || keywordText(item).indexOf(needle) >= 0) {
      out.push(item)
      if (out.length >= max) break
    }
  }

  return out
}

function displayEmojis(emojis, recentEmojis, query, recentLimit, limit) {
  var values = Array.isArray(emojis) ? emojis : []
  var out = filterEmojis(values, query, limit)
  var recent = normalizeRecentEmojis(recentEmojis)
  var maxRecent = Number(recentLimit)
  if (isNaN(maxRecent)) maxRecent = 0
  maxRecent = Math.max(0, Math.floor(maxRecent))
  if (normalizedQuery(query) || recent.length === 0 || maxRecent === 0 || out.length === 0) return out

  var byEmoji = {}
  for (var i = 0; i < values.length; i++) {
    var item = values[i]
    if (item && item.e && byEmoji[item.e] === undefined) byEmoji[item.e] = item
  }

  var promoted = []
  var promotedEmoji = {}
  for (var j = 0; j < recent.length && promoted.length < maxRecent; j++) {
    var emoji = recent[j]
    if (byEmoji[emoji] === undefined) continue
    promoted.push(byEmoji[emoji])
    promotedEmoji[emoji] = true
  }

  for (var k = 0; k < out.length; k++) {
    if (!promotedEmoji[out[k].e]) promoted.push(out[k])
  }

  return promoted.slice(0, out.length)
}

if (typeof module !== "undefined") {
  module.exports = {
    parseEmojis: parseEmojis,
    parseRecentEmojis: parseRecentEmojis,
    addRecentEmoji: addRecentEmoji,
    normalizedQuery: normalizedQuery,
    filterEmojis: filterEmojis,
    displayEmojis: displayEmojis
  }
}
