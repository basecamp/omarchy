// Pure data-shaping helpers for the Snippets bar widget. Node-loadable (see
// the module.exports guard at the bottom) so this file is unit-tested
// directly, the same convention shell/plugins/clipboard/ClipboardHistory.js
// and shell/plugins/menu/MenuModel.js use.
//
// This module is a read/search-side helper for Panel.qml and a mirror, for
// testing and live preview rendering, of the validation and import-conflict
// rules bin/omarchy-snippets-save/-import-preview/-import-apply enforce in
// bash with jq. The bash CLI is the actual writer and the source of truth at
// runtime -- see docs/snippet-manager.md and the plan's storage section for
// why QML never writes snippets.json directly.

function blank(text) {
  return String(text === undefined || text === null ? "" : text).trim().length === 0
}

function validName(name) {
  return !blank(name)
}

function validContent(content) {
  return !blank(content)
}

function normalizeSnippet(value) {
  if (!value || typeof value !== "object") return null
  var name = String(value.name || "")
  var content = String(value.content || "")
  if (blank(name) || blank(content)) return null
  var snippet = { name: name, content: content }
  if (value.id !== undefined && value.id !== null) snippet.id = String(value.id)
  return snippet
}

function parseStore(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.snippets)) return []
    var next = []
    for (var i = 0; i < parsed.snippets.length; i++) {
      var snippet = normalizeSnippet(parsed.snippets[i])
      if (snippet) next.push(snippet)
    }
    return next
  } catch (e) {
    return []
  }
}

function duplicateName(snippets, name, excludeId) {
  var values = Array.isArray(snippets) ? snippets : []
  for (var i = 0; i < values.length; i++) {
    var snippet = values[i]
    if (!snippet) continue
    if (excludeId !== undefined && excludeId !== null && String(snippet.id) === String(excludeId)) continue
    if (snippet.name === name) return true
  }
  return false
}

function searchableText(snippet) {
  if (!snippet) return ""
  return String(snippet.name || "") + " " + String(snippet.content || "")
}

// Rows for the search/list view. Each row carries a single-line content
// preview (whitespace collapsed, same idea as Clipboard's previewText) so
// the row can show "name — preview" and let Qt elide whatever doesn't fit,
// without the row growing to a second line.
function contentPreview(content) {
  return String(content || "").replace(/\s+/g, " ").trim()
}

function displayRows(snippets, query) {
  var values = Array.isArray(snippets) ? snippets : []
  var needle = String(query || "").trim().toLowerCase()
  var rows = []
  for (var i = 0; i < values.length; i++) {
    var snippet = values[i]
    if (!snippet) continue
    if (needle && searchableText(snippet).toLowerCase().indexOf(needle) < 0) continue
    rows.push({ id: snippet.id, name: snippet.name, preview: contentPreview(snippet.content) })
  }
  return rows
}

// Deterministic "Keep both" suffixing: "<name> (Imported)", then
// "<name> (Imported 2)", "(Imported 3)", ... per docs/snippet-manager.md
// section 18. `existingNames` is anything with an `indexOf`-free membership
// check -- pass an array of names or an object used as a set.
function nextUniqueName(existingNames, baseName) {
  var has
  if (Array.isArray(existingNames)) {
    has = function(name) { return existingNames.indexOf(name) >= 0 }
  } else {
    var set = existingNames || {}
    has = function(name) { return Object.prototype.hasOwnProperty.call(set, name) }
  }

  var n = 1
  while (true) {
    var candidate = n === 1 ? baseName + " (Imported)" : baseName + " (Imported " + n + ")"
    if (!has(candidate)) return candidate
    n++
  }
}

// Mirrors bin/omarchy-snippets-import-preview's jq reduce: same name + same
// content is skipped silently (never surfaced as a decision); same name +
// different content is a conflict. Intra-file duplicate names are compared
// against the running state, so a second occurrence of a brand-new name in
// the same file is checked against the first occurrence rather than the
// pre-import store. See docs/snippet-manager.md section 35.
function classifyImport(existingSnippets, importedSnippets) {
  var map = {}
  var existing = Array.isArray(existingSnippets) ? existingSnippets : []
  for (var i = 0; i < existing.length; i++) {
    if (existing[i]) map[existing[i].name] = existing[i].content
  }

  var conflicts = []
  var newCount = 0
  var imported = Array.isArray(importedSnippets) ? importedSnippets : []
  for (var j = 0; j < imported.length; j++) {
    var item = imported[j]
    if (!item) continue
    var name = item.name
    if (Object.prototype.hasOwnProperty.call(map, name)) {
      if (map[name] === item.content) continue
      conflicts.push({ name: name, existingContent: map[name], importedContent: item.content })
      map[name] = item.content
    } else {
      newCount++
      map[name] = item.content
    }
  }

  return { newCount: newCount, conflicts: conflicts }
}

if (typeof module !== "undefined") {
  module.exports = {
    blank: blank,
    validName: validName,
    validContent: validContent,
    normalizeSnippet: normalizeSnippet,
    parseStore: parseStore,
    duplicateName: duplicateName,
    searchableText: searchableText,
    contentPreview: contentPreview,
    displayRows: displayRows,
    nextUniqueName: nextUniqueName,
    classifyImport: classifyImport
  }
}
