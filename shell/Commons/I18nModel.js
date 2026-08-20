function normalizeLocale(value) {
  var locale = String(value || "").trim()
  if (!locale) return ""
  locale = locale.split(":")[0].split(".")[0].split("@")[0].replace(/-/g, "_")
  if (locale === "C" || locale === "POSIX") return ""
  var parts = locale.split("_")
  var language = parts[0].toLowerCase()
  if (!language) return ""
  return parts.length > 1 ? language + "_" + parts[1].toUpperCase() : language
}

function localeCandidates(environment) {
  var env = environment || {}
  var raw = env.LANGUAGE || env.LC_ALL || env.LC_MESSAGES || env.LANG || ""
  var requested = env.LANGUAGE ? String(raw).split(":") : [raw]
  var candidates = []
  for (var i = 0; i < requested.length; i++) {
    var normalized = normalizeLocale(requested[i])
    if (!normalized) continue
    var language = normalized.split("_")[0]
    if (candidates.indexOf(normalized) === -1) candidates.push(normalized)
    if (candidates.indexOf(language) === -1) candidates.push(language)
  }
  return candidates
}

function selectCatalog(environment, available) {
  var catalogs = Array.isArray(available) ? available : []
  var candidates = localeCandidates(environment)
  for (var i = 0; i < candidates.length; i++) {
    var candidate = candidates[i]
    // "en" is the untranslated source language, not a catalog. Once it is
    // reached in the preference order, stop rather than let a lower-priority
    // language override the language the caller actually asked for.
    if (candidate === "en") return ""
    if (catalogs.indexOf(candidate) !== -1) return candidate
  }
  return ""
}

function interpolate(value, args) {
  var output = String(value === undefined || value === null ? "" : value)
  var values = Array.isArray(args) ? args : []
  // Replace higher indices first so "%1" can't consume the leading digit of
  // "%10", "%11", etc. before those placeholders get their turn.
  for (var i = values.length - 1; i >= 0; i--) {
    output = output.split("%" + (i + 1)).join(String(values[i]))
  }
  return output
}

function translate(source, translations, args) {
  var fallback = String(source === undefined || source === null ? "" : source)
  var catalog = translations && typeof translations === "object" ? translations : {}
  var translated = Object.prototype.hasOwnProperty.call(catalog, fallback) ? catalog[fallback] : fallback
  return interpolate(translated, args)
}

if (typeof module !== "undefined") module.exports = {
  normalizeLocale: normalizeLocale,
  localeCandidates: localeCandidates,
  selectCatalog: selectCatalog,
  interpolate: interpolate,
  translate: translate
}
