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
    if (catalogs.indexOf(candidates[i]) !== -1) return candidates[i]
  }
  return ""
}

function interpolate(value, args) {
  var output = String(value === undefined || value === null ? "" : value)
  var values = Array.isArray(args) ? args : []
  for (var i = 0; i < values.length; i++) {
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
