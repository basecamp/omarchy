function entryName(entry) {
  return String((entry && entry.name) || (entry && entry.id) || "")
}

function entrySubtext(entry) {
  return String((entry && entry.genericName) || "")
}

function entrySortKey(entry) {
  return entryName(entry).toLowerCase()
}

function keywordText(entry) {
  try {
    if (entry && entry.keywords && typeof entry.keywords.join === "function") return entry.keywords.join(" ")
  } catch (e) {
  }
  return ""
}

function entrySearchText(entry) {
  if (!entry) return ""
  return [entry.name, entry.genericName, entry.comment, keywordText(entry), entry.id].join(" ").toLowerCase()
}

function wordText(value) {
  return String(value || "")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[._:/\\-]+/g, " ")
    .toLowerCase()
}

function words(value) {
  var values = wordText(value).split(/[^a-z0-9]+/)
  var result = []
  for (var i = 0; i < values.length; i++) {
    if (values[i]) result.push(values[i])
  }
  return result
}

function entryAcronym(entry) {
  var values = words([entry && entry.name, entry && entry.genericName, keywordText(entry), entry && entry.id].join(" "))
  var result = ""
  for (var i = 0; i < values.length; i++) result += values[i].charAt(0)
  return result
}

// fzf-style subsequence match: every character of `term` must appear in
// `text` in order, not necessarily adjacent. Returns -1 when `term` is not a
// subsequence of `text`. Otherwise a quality score (higher is better): +3 for
// a matched char at a word boundary, +2 for each char continuing an unbroken
// run, minus how far into `text` the first match sits. Scoped to the app
// name only wherever it's called — running it over the full search haystack
// (keywords/comment/id) turns most short queries into false hits, e.g.
// "contact" is an in-order subsequence of Calculator's own keywords.
function fuzzySubsequenceScore(text, term) {
  var hay = String(text || "")
  var needle = String(term || "")
  if (!needle || !hay) return -1

  var hi = 0, ni = 0, firstIndex = -1, run = 0, bonus = 0
  while (hi < hay.length && ni < needle.length) {
    if (hay.charAt(hi) === needle.charAt(ni)) {
      if (firstIndex < 0) firstIndex = hi
      var prev = hi > 0 ? hay.charAt(hi - 1) : ""
      var boundary = hi === 0 || /[^a-z0-9]/i.test(prev)
      run += 1
      bonus += (boundary ? 3 : 0) + (run > 1 ? 2 : 0)
      ni += 1
    } else {
      run = 0
    }
    hi += 1
  }
  if (ni < needle.length) return -1
  return bonus - firstIndex
}

var MIN_FUZZY_TERM_LENGTH = 3

function termMatches(entry, term) {
  if (!term) return true

  var name = entryName(entry).toLowerCase()
  var id = String((entry && entry.id) || "").toLowerCase()
  var haystack = entrySearchText(entry)

  if (name.indexOf(term) >= 0) return true
  if (id.indexOf(term) >= 0) return true
  if (haystack.indexOf(term) >= 0) return true
  if (term.length <= 5 && entryAcronym(entry).indexOf(term) >= 0) return true

  return term.length >= MIN_FUZZY_TERM_LENGTH && fuzzySubsequenceScore(name, term) >= 0
}

function allTermsMatch(entry, query) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termMatches(entry, terms[i])) return false
  }
  return true
}

function fuzzyScore(entry, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return 0
  if (!allTermsMatch(entry, q)) return -1

  var name = entryName(entry).toLowerCase()
  var id = String((entry && entry.id) || "").toLowerCase()
  var haystack = entrySearchText(entry)
  var directName = name.indexOf(q)
  var directId = id.indexOf(q)
  if (directName === 0) return 10000 - name.length
  if (directId === 0) return 9500 - id.length
  if (directName > 0) return 8000 - directName * 10 - name.length
  if (directId > 0) return 7600 - directId * 10 - id.length

  var hayIndex = haystack.indexOf(q)
  if (hayIndex >= 0) return 6000 - hayIndex

  var acronym = entryAcronym(entry)
  var acronymIndex = acronym.indexOf(q)
  if (acronymIndex === 0) return 5000 - acronym.length
  if (acronymIndex > 0) return 4600 - acronymIndex * 10 - acronym.length

  if (q.length >= MIN_FUZZY_TERM_LENGTH) {
    var fuzzy = fuzzySubsequenceScore(name, q)
    if (fuzzy >= 0) return 2000 + Math.max(0, Math.min(900, fuzzy))
  }

  return 4000 - name.length
}

function sortedEntries(values, query, hiddenCallback) {
  var q = String(query || "").trim()
  var rows = []

  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry || entry.noDisplay) continue
    if (hiddenCallback && hiddenCallback(entry)) continue
    var name = entryName(entry)
    if (!name) continue
    var score = fuzzyScore(entry, q)
    if (score < 0) continue
    rows.push({ entry: entry, score: score, key: entrySortKey(entry), name: name.toLowerCase() })
  }

  rows.sort(function(a, b) {
    if (q && a.score !== b.score) return b.score - a.score
    if (a.key < b.key) return -1
    if (a.key > b.key) return 1
    if (a.name < b.name) return -1
    if (a.name > b.name) return 1
    return 0
  })

  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    entryName: entryName,
    entrySubtext: entrySubtext,
    entrySortKey: entrySortKey,
    entrySearchText: entrySearchText,
    entryAcronym: entryAcronym,
    fuzzySubsequenceScore: fuzzySubsequenceScore,
    fuzzyScore: fuzzyScore,
    sortedEntries: sortedEntries
  }
}
