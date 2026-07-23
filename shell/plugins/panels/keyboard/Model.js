// The four switch-shortcut presets shown as pills in the panel. Keep this in
// sync with SWITCHER_OPTIONS in default/hypr/input.lua.
var SWITCHERS = [
  { id: "alt_shift", label: "Alt+Shift" },
  { id: "ctrl_shift", label: "Ctrl+Shift" },
  { id: "right_alt", label: "Right Alt" },
  { id: "both_shift", label: "Both Shift" }
]

// xkb layout code -> ISO 639-1 language code. GNOME's input-source indicator
// shows the language, not the xkb country code (e.g. "en" for both the "us"
// and "gb" layouts, "fa" for "ir"), so the bar matches that instead of just
// upper-casing the xkb code. Codes not listed here fall back to the xkb code
// itself (still upper-cased) so unusual/rare layouts don't break.
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

function languageCode(code) {
  var key = String(code || "").toLowerCase()
  return (LANGUAGE_CODES[key] || key).toUpperCase()
}

function toArray(values) {
  if (!values) return []
  if (Array.isArray(values)) return values.slice()

  var length = Number(values.length || 0)
  if (!isFinite(length) || length <= 0) return []

  var list = []
  for (var i = 0; i < length; i++) list.push(values[i])
  return list
}

function parseJson(text, fallback) {
  var trimmed = String(text || "").trim()
  if (trimmed === "") return fallback
  try {
    return JSON.parse(trimmed)
  } catch (e) {
    return fallback
  }
}

// `omarchy-keyboard-layout status` output -> { layouts, switcher, active }
function parseStatus(text) {
  var parsed = parseJson(text, null)
  if (!parsed || typeof parsed !== "object") {
    return { layouts: [], switcher: "alt_shift", active: "" }
  }

  return {
    layouts: toArray(parsed.layouts),
    switcher: parsed.switcher || "alt_shift",
    active: parsed.active || ""
  }
}

// `omarchy-keyboard-layout available` output -> array of {code, label}
function parseAvailable(text) {
  var parsed = parseJson(text, [])
  return toArray(parsed)
}

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

  return list.sort(function(a, b) { return matchRank(a, needle) - matchRank(b, needle) })
}

function switcherPresets() {
  return SWITCHERS.slice()
}

function switcherLabel(id) {
  for (var i = 0; i < SWITCHERS.length; i++) {
    if (SWITCHERS[i].id === id) return SWITCHERS[i].label
  }
  return id || ""
}

function layoutAt(status, index) {
  var layouts = toArray(status && status.layouts)
  return index >= 0 && index < layouts.length ? layouts[index] : null
}

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
