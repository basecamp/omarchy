function parse(value) {
  var parsed
  var raw = String(value || "[]")
  // Allow eight groups of 21 maximum-length URLs, including JSON escaping.
  // Never truncate serialized JSON: that invalidates every saved collection.
  if (raw.length > 3 * 1024 * 1024) return []
  try {
    parsed = JSON.parse(raw)
  } catch (error) {
    return []
  }
  if (!Array.isArray(parsed)) return []

  var result = []
  var seen = Object.create(null)
  for (var i = 0; i < parsed.length && result.length < 8; i++) {
    var candidate = parsed[i]
    if (!candidate || typeof candidate !== "object") continue
    var id = String(candidate.id || "").replace(/[^a-zA-Z0-9_-]/g, "").substring(0, 48)
    var name = String(candidate.name || "").replace(/\s+/g, " ").trim().substring(0, 32)
    if (id === "" || name === "" || seen[id] || !Array.isArray(candidate.sourceUrls)) continue
    if (id === "omarchy" || id === "chefs-choice") continue
    var urls = []
    for (var sourceIndex = 0; sourceIndex < candidate.sourceUrls.length && urls.length < 21; sourceIndex++) {
      var url = String(candidate.sourceUrls[sourceIndex] || "").trim().substring(0, 2048)
      if (/^https:\/\//.test(url) && urls.indexOf(url) === -1) urls.push(url)
    }
    seen[id] = true
    result.push({ id: id, name: name, sourceUrls: urls })
  }
  return result
}

function withBuiltIn(groups) {
  return [{
    id: "omarchy",
    name: "Omarchy",
    sourceUrls: ["https://omarchy.org/news/rss.xml"]
  }].concat(groups || [])
}

function containsSource(groups, url) {
  return (groups || []).some(function(group) {
    return (group.sourceUrls || []).indexOf(url) >= 0
  })
}

function subscribedIds(catalog, standaloneIds, groups) {
  return ["omarchy"].concat((catalog || []).filter(function(source) {
    return standaloneIds.indexOf(source.id) >= 0 || containsSource(groups, source.url)
  }).map(function(source) { return source.id }))
}

function visibleSources(sources, standaloneIds, hiddenUrls) {
  return (sources || []).filter(function(source) {
    if (source.id === "omarchy") return false
    if (source.category === "custom") return hiddenUrls.indexOf(source.url) < 0
    return standaloneIds.indexOf(source.id) >= 0
  })
}

function replaceSource(groups, oldUrl, newUrl) {
  return (groups || []).map(function(group) {
    var urls = []
    ;(group.sourceUrls || []).forEach(function(original) {
      var url = original === oldUrl ? newUrl : original
      if (url && urls.indexOf(url) === -1) urls.push(url)
    })
    // Removing a subscription must not delete the user's named collection.
    return { id: group.id, name: group.name, sourceUrls: urls }
  })
}

function buildItemIndex(items, collections, itemLimit) {
  var limit = Math.max(1, Number(itemLimit) || 1)
  var next = Object.create(null)
  next.all = []
  var collectionsByUrl = Object.create(null)
  var groups = collections || []
  for (var collectionIndex = 0; collectionIndex < groups.length; collectionIndex++) {
    var collectionKey = "collection:" + String(groups[collectionIndex].id || "")
    next[collectionKey] = []
    var sourceUrls = groups[collectionIndex].sourceUrls || []
    for (var urlIndex = 0; urlIndex < sourceUrls.length; urlIndex++) {
      var sourceUrl = String(sourceUrls[urlIndex] || "")
      if (!collectionsByUrl[sourceUrl]) collectionsByUrl[sourceUrl] = []
      collectionsByUrl[sourceUrl].push(collectionKey)
    }
  }

  var articles = items || []
  for (var i = 0; i < articles.length; i++) {
    var item = articles[i]
    if (next.all.length < limit) next.all.push(item)
    var sourceId = String(item.sourceId || "omarchy")
    if (!next[sourceId]) next[sourceId] = []
    if (next[sourceId].length < limit) next[sourceId].push(item)
    var collectionKeys = collectionsByUrl[String(item.sourceUrl || "")] || []
    for (var keyIndex = 0; keyIndex < collectionKeys.length; keyIndex++) {
      var key = collectionKeys[keyIndex]
      if (next[key].length < limit) next[key].push(item)
    }
  }
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    parse: parse,
    containsSource: containsSource,
    subscribedIds: subscribedIds,
    visibleSources: visibleSources,
    withBuiltIn: withBuiltIn,
    replaceSource: replaceSource,
    buildItemIndex: buildItemIndex
  }
}
