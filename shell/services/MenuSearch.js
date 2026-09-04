// Chunk selection follows fuzzel's match_fzf algorithm.
// Copyright (c) 2019 Daniel Eklöf, SPDX-License-Identifier: MIT.
// https://codeberg.org/dnkl/fuzzel/src/branch/master/match.c

function searchableToken(value) {
  return String(value || "").replace(/[._:/\\-]+/g, " ")
}

function leafIdFor(id) {
  var parts = String(id || "").split(".")
  return parts.length > 0 ? parts[parts.length - 1] : id
}

function nameSearchFields(entry) {
  if (!entry) return []
  var fields = [String(entry.label || ""), searchableToken(leafIdFor(entry.id))]
  var values = Array.isArray(entry.aliases) ? entry.aliases : []
  for (var i = 0; i < values.length; i++) fields.push(searchableToken(values[i]))
  return fields
}

function nameSearchText(entry) {
  return nameSearchFields(entry).join(" ").toLowerCase()
}

function termInWords(term, text) {
  var words = String(text || "").toLowerCase().split(/\s+/)
  for (var i = 0; i < words.length; i++) {
    if (words[i] === term) return true
  }
  return false
}

function descriptionMatches(query, text) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termInWords(terms[i], text)) return false
  }
  return true
}

function fzfMatch(text, pattern) {
  var haystack = String(text || "").toLowerCase()
  var needle = String(pattern || "").toLowerCase()
  if (!needle) return null

  var chunks = []
  var needleStart = 0
  var searchStart = 0

  while (needleStart < needle.length) {
    var bestStart = -1
    var bestLength = 0

    for (var start = searchStart; start < haystack.length; start++) {
      var length = 0
      while (needleStart + length < needle.length &&
             start + length < haystack.length &&
             needle[needleStart + length] === haystack[start + length]) {
        length += 1
      }

      if (length > bestLength) {
        bestStart = start
        bestLength = length
      }
      if (needleStart + length === needle.length) break
    }

    if (bestLength === 0) return null
    chunks.push({ start: bestStart, length: bestLength })
    needleStart += bestLength
    searchStart = bestStart + bestLength
  }

  var longestChunk = 0
  for (var i = 0; i < chunks.length; i++) longestChunk = Math.max(longestChunk, chunks[i].length)
  var firstStart = chunks[0].start

  return {
    longestChunk: longestChunk,
    wordBoundaries: firstStart === 0 || /\s/.test(haystack[firstStart - 1]) ? 1 : 0,
    chunkCount: chunks.length,
    firstStart: firstStart,
    textLength: haystack.length
  }
}

function compareFuzzy(a, b) {
  if (a.longestChunk !== b.longestChunk) return b.longestChunk - a.longestChunk
  if (a.wordBoundaries !== b.wordBoundaries) return b.wordBoundaries - a.wordBoundaries
  if (a.chunkCount !== b.chunkCount) return a.chunkCount - b.chunkCount
  if (a.firstStart !== b.firstStart) return a.firstStart - b.firstStart
  return a.textLength - b.textLength
}

function bestFieldMatch(fields, term) {
  var best = null
  for (var i = 0; i < fields.length; i++) {
    var match = fzfMatch(fields[i], term)
    if (match && (!best || compareFuzzy(match, best) < 0)) best = match
  }
  return best
}

function fzfFieldsRank(query, fields) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  var rank = { longestChunk: 0, wordBoundaries: 0, chunkCount: 0, firstStart: 0, textLength: 0 }

  for (var i = 0; i < terms.length; i++) {
    if (!terms[i]) continue
    var match = bestFieldMatch(fields, terms[i])
    if (!match) return null
    rank.longestChunk = Math.max(rank.longestChunk, match.longestChunk)
    rank.wordBoundaries += match.wordBoundaries
    rank.chunkCount += match.chunkCount
    rank.firstStart += match.firstStart
    rank.textLength += match.textLength
  }

  return rank
}

function acronym(entry) {
  return String((entry && entry.acronym) || "").toLowerCase()
}

function matchesQuery(entry, query, visible) {
  if (!entry || entry.id === "root" || !visible) return false

  var nameText = nameSearchText(entry)
  var nameFields = nameSearchFields(entry)
  var descriptionText = String(entry.description || "").toLowerCase()
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  var entryAcronym = entry.kind === "app" ? acronym(entry) : ""

  for (var i = 0; i < terms.length; i++) {
    var term = terms[i]
    if (!term) continue
    if (nameText.indexOf(term) >= 0) continue
    if (termInWords(term, descriptionText)) continue
    if (entry.kind === "app") {
      if (term.length <= 5 && entryAcronym.indexOf(term) >= 0) continue
    } else if (bestFieldMatch(nameFields, term)) {
      continue
    }
    return false
  }

  return true
}

function rank(entry, query) {
  var needle = String(query || "").toLowerCase().trim()
  var label = String(entry.label || "").toLowerCase()
  var nameText = nameSearchText(entry)
  var nameFields = nameSearchFields(entry)
  var descriptionText = String(entry.description || "").toLowerCase()
  var tier = 80
  var fuzzy = null

  if (label === needle) tier = entry.parent === "root" ? 2 : 0
  else if (entry.kind === "app" && label.split(/\s+/).indexOf(needle) >= 0) tier = 0
  else if (label.indexOf(needle) === 0) tier = 10
  else if (label.indexOf(needle) >= 0) tier = 30
  else if (nameText.indexOf(needle) >= 0) tier = 40
  else if (descriptionMatches(needle, descriptionText)) tier = 60
  else if (entry.kind === "app") {
    if (needle.length <= 5 && acronym(entry).indexOf(needle) >= 0) tier = 75
  } else {
    fuzzy = fzfFieldsRank(needle, nameFields)
    if (fuzzy) tier = 70
  }

  var kindOrder = 0
  if (entry.kind === "menu" || entry.kind === "link") kindOrder = -2
  if (entry.kind === "app") kindOrder = -5

  return { tier: tier, fuzzy: fuzzy, kindOrder: kindOrder }
}

function compareRanks(a, b) {
  if (a.tier !== b.tier) return a.tier - b.tier
  if (a.fuzzy && b.fuzzy) {
    var fuzzyOrder = compareFuzzy(a.fuzzy, b.fuzzy)
    if (fuzzyOrder !== 0) return fuzzyOrder
  }
  return a.kindOrder - b.kindOrder
}

if (typeof module !== "undefined") {
  module.exports = {
    searchableToken: searchableToken,
    leafIdFor: leafIdFor,
    nameSearchFields: nameSearchFields,
    nameSearchText: nameSearchText,
    fzfMatch: fzfMatch,
    matchesQuery: matchesQuery,
    rank: rank,
    compareRanks: compareRanks
  }
}
