// The four switch-shortcut presets shown as pills in the panel. Keep this in
// sync with SWITCHER_OPTIONS in config/hypr/input.lua.
var SWITCHERS = [
  { id: "alt_shift", label: "Alt+Shift" },
  { id: "ctrl_shift", label: "Ctrl+Shift" },
  { id: "right_alt", label: "Right Alt" },
  { id: "both_shift", label: "Both Shift" }
]

// xkb layout code -> ISO 639-1 language code. GNOME's input-source indicator
// shows the language a layout belongs to, not the xkb country/variant code,
// since several xkb codes can map to the same language and should read the
// same way in the bar. Codes not listed here fall back to the xkb code
// itself (still upper-cased) so unusual or rare layouts don't break.
var LANGUAGE_CODES = {
  us: "en", gb: "en", au: "en", ca: "en", nz: "en", ie: "en", za: "en",
  ir: "fa", de: "de", at: "de", ch: "de",
  fr: "fr", be: "nl", nl: "nl",
  es: "es", mx: "es", latam: "es", it: "it", pt: "pt", br: "pt",
  ru: "ru", ua: "uk", by: "be", pl: "pl", cz: "cs", sk: "sk", hu: "hu",
  ro: "ro", bg: "bg", rs: "sr", hr: "hr", si: "sl", ee: "et", lv: "lv", lt: "lt",
  se: "sv", no: "no", dk: "da", fi: "fi", is: "is",
  gr: "el", tr: "tr", il: "he", sa: "ar", ara: "ar",
  in: "hi", pk: "ur", bd: "bn", th: "th", vn: "vi",
  cn: "zh", tw: "zh", hk: "zh", jp: "ja", kr: "ko"
}

// The code shown in the bar for a configured layout, e.g. "US" -> "EN".
function languageCode(code) {
  var key = String(code || "").toLowerCase()
  return (LANGUAGE_CODES[key] || key).toUpperCase()
}

// Normalizes any array-like value (a real array, a QML JS list model, null,
// or undefined) into a plain JS array, so the rest of this file never has
// to special-case where the data came from.
function toArray(values) {
  if (!values) return []
  if (Array.isArray(values)) return values.slice()

  var length = Number(values.length || 0)
  if (!isFinite(length) || length <= 0) return []

  var list = []
  for (var i = 0; i < length; i++) list.push(values[i])
  return list
}

// Safe JSON.parse: empty input or a parse error returns the given fallback
// instead of throwing, so a CLI hiccup never crashes the panel.
function parseJson(text, fallback) {
  var trimmed = String(text || "").trim()
  if (trimmed === "") return fallback
  try {
    return JSON.parse(trimmed)
  } catch (e) {
    return fallback
  }
}

// `omarchy-keyboard-layout status` output -> { layouts, switcher, active, show_bar_icon }
function parseStatus(text) {
  var parsed = parseJson(text, null)
  if (!parsed || typeof parsed !== "object") {
    return { layouts: [], switcher: "alt_shift", active: "", show_bar_icon: true }
  }

  return {
    layouts: toArray(parsed.layouts),
    switcher: parsed.switcher || "alt_shift",
    active: parsed.active || "",
    show_bar_icon: parsed.show_bar_icon !== false
  }
}

// `omarchy-keyboard-layout available` output -> array of {code, label}
function parseAvailable(text) {
  var parsed = parseJson(text, [])
  return toArray(parsed)
}

// Plain list of xkb codes already configured, used to exclude them from
// the "Add language" search results.
function configuredCodes(status) {
  var codes = []
  var layouts = toArray(status && status.layouts)
  for (var i = 0; i < layouts.length; i++) {
    if (layouts[i] && layouts[i].code) codes.push(layouts[i].code)
  }
  return codes
}

// Lower relevance rank = better match. Exact code match beats a label/code
// that merely starts with the query, which in turn beats a match buried
// elsewhere in the string.
function matchRank(item, needle) {
  var label = String(item.label || "").toLowerCase()
  var code = String(item.code || "").toLowerCase()
  if (code === needle) return 0
  if (label.indexOf(needle) === 0) return 1
  if (code.indexOf(needle) === 0) return 2
  return 3
}

// Available languages not already configured, filtered by a free-text
// query against the label or xkb code (case-insensitive substring), and
// ranked so the closest match (exact code, then prefix match) rises to the
// top instead of relying on plain alphabetical order.
function filterAvailable(available, status, query) {
  var configured = configuredCodes(status)
  var needle = String(query || "").trim().toLowerCase()

  var list = toArray(available).filter(function(item) {
    if (!item || !item.code) return false
    if (configured.indexOf(item.code) !== -1) return false
    if (needle === "") return true
    return String(item.label || "").toLowerCase().indexOf(needle) !== -1
      || String(item.code || "").toLowerCase().indexOf(needle) !== -1
  })

  if (needle === "") return list

  return list.sort(function(a, b) {
     var ra = matchRank(a, needle)
     var rb = matchRank(b, needle)
     if (ra !== rb) return ra - rb
     var la = String(a && a.label || "")
     var lb = String(b && b.label || "")
     var cmp = la.localeCompare(lb)
     if (cmp !== 0) return cmp
     return String(a && a.code || "").localeCompare(String(b && b.code || ""))
   })
}

// The four presets, for the pill row -- a fresh copy each time so callers
// can't accidentally mutate the shared list.
function switcherPresets() {
  return SWITCHERS.slice()
}

// Display label for a preset id (falls back to the raw id if it's ever
// unrecognized, rather than showing nothing).
function switcherLabel(id) {
  for (var i = 0; i < SWITCHERS.length; i++) {
    if (SWITCHERS[i].id === id) return SWITCHERS[i].label
  }
  return id || ""
}

// The configured layout at a given position, or null if the index is out
// of range (e.g. the list just got shorter after a remove).
function layoutAt(status, index) {
  var layouts = toArray(status && status.layouts)
  return index >= 0 && index < layouts.length ? layouts[index] : null
}

// The layout currently in use. Falls back to the first configured layout
// if the reported active code doesn't match any of them (e.g. right after
// a fresh add, before the next status refresh confirms it).
function activeLayout(status) {
  var layouts = toArray(status && status.layouts)
  for (var i = 0; i < layouts.length; i++) {
    if (layouts[i] && layouts[i].code === (status && status.active)) return layouts[i]
  }
  return layouts.length > 0 ? layouts[0] : null
}

if (typeof module !== "undefined") {
  module.exports = {
    toArray: toArray,
    parseStatus: parseStatus,
    parseAvailable: parseAvailable,
    configuredCodes: configuredCodes,
    filterAvailable: filterAvailable,
    switcherPresets: switcherPresets,
    switcherLabel: switcherLabel,
    layoutAt: layoutAt,
    activeLayout: activeLayout,
    languageCode: languageCode
  }
}
