// I18nModel.js — the pure-JS core of qs.Commons.I18n.
//
// No Qt or QML dependencies, so it runs under node for tests and QML loads it
// with `import "I18nModel.js" as Model`. Keep it that way: everything that
// touches FileView, Quickshell.env, or the plugin registry lives in I18n.qml.
//
// Vocabulary
//   domain    a namespace for keys, normally a plugin id ("omarchy.menu");
//             "omarchy.shell" and "omarchy.cli" are reserved for code with no id
//   owner     whoever registered a set of catalogs, normally a language pack;
//             owners are replaced atomically and can be cleared
//   catalog   one JSON object per domain, po2json/Jed shape: a "" header entry
//             plus msgid -> msgstr, or msgid -> [forms] for plurals
//   link      child domain -> parent domain, from a clone's omarchy.clonedFrom

var CONTEXT_SEPARATOR = "\u0004"

// ---------------------------------------------------------------------------
// Locale selection

function normalizeLocale(value) {
  var locale = String(value || "").trim()
  if (!locale) return ""
  locale = locale.split(".")[0].split("@")[0].replace(/-/g, "_")
  if (locale === "C" || locale === "POSIX") return ""
  var parts = locale.split("_")
  var language = parts[0].toLowerCase()
  if (!language) return ""
  return parts.length > 1 && parts[1] ? language + "_" + parts[1].toUpperCase() : language
}

// Ordered preference list from the gettext environment variables. LANGUAGE is
// a colon-separated list and wins outright; the others are single values.
// Each entry expands to [regional, language] so "ca_ES" also tries "ca".
// "en" is the source language: nothing after it can apply, so the list stops.
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
    if (language === "en") break
  }
  return candidates
}

// ---------------------------------------------------------------------------
// Interpolation: %1, %2 ... Single pass, so an argument that itself contains
// "%2" is inserted verbatim and never re-expanded. Unknown indices stay as-is.

function interpolate(value, args) {
  var output = String(value === undefined || value === null ? "" : value)
  var values = Array.isArray(args) ? args : []
  return output.replace(/%([1-9][0-9]*)/g, function(match, rawIndex) {
    var index = Number(rawIndex) - 1
    return index < values.length ? String(values[index]) : match
  })
}

function contextKey(context, source) {
  var ctx = String(context === undefined || context === null ? "" : context)
  var key = String(source === undefined || source === null ? "" : source)
  return ctx ? ctx + CONTEXT_SEPARATOR + key : key
}

// ---------------------------------------------------------------------------
// Plural rules. The catalog header carries a gettext Plural-Forms line:
//   "nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);"
// The expression is a C integer expression over n. It is evaluated by a small
// recursive-descent parser rather than eval/Function, so a hostile catalog
// cannot run code and a malformed one is rejected rather than half-applied.

var ENGLISH_PLURAL = { nplurals: 2, plural: function(n) { return n !== 1 ? 1 : 0 } }

function tokenizePlural(text) {
  var tokens = []
  var i = 0
  while (i < text.length) {
    var c = text.charAt(i)
    if (c === " " || c === "\t" || c === "\n") { i++; continue }
    if (c >= "0" && c <= "9") {
      var j = i
      while (j < text.length && text.charAt(j) >= "0" && text.charAt(j) <= "9") j++
      tokens.push({ type: "num", value: Number(text.slice(i, j)) })
      i = j
      continue
    }
    if (c === "n") { tokens.push({ type: "n" }); i++; continue }
    var two = text.substr(i, 2)
    if (["||", "&&", "==", "!=", "<=", ">="].indexOf(two) !== -1) {
      tokens.push({ type: "op", value: two }); i += 2; continue
    }
    if ("?:()<>+-*/%!".indexOf(c) !== -1) { tokens.push({ type: "op", value: c }); i++; continue }
    throw new Error("unexpected character in plural expression: " + c)
  }
  return tokens
}

function parsePluralExpression(text) {
  var tokens = tokenizePlural(text)
  var pos = 0

  function peek() { return tokens[pos] }
  function take(value) {
    var t = tokens[pos]
    if (!t || (value !== undefined && (t.type !== "op" || t.value !== value))) {
      throw new Error("plural expression: expected " + (value || "token") + " at " + pos)
    }
    pos++
    return t
  }
  function isOp(value) { var t = peek(); return t && t.type === "op" && t.value === value }

  function primary() {
    var t = peek()
    if (!t) throw new Error("plural expression: unexpected end")
    if (t.type === "num") { pos++; var v = t.value; return function() { return v } }
    if (t.type === "n") { pos++; return function(n) { return n } }
    if (isOp("(")) { take("("); var e = ternary(); take(")"); return e }
    throw new Error("plural expression: unexpected " + t.value)
  }
  function unary() {
    if (isOp("!")) { take("!"); var e = unary(); return function(n) { return e(n) ? 0 : 1 } }
    return primary()
  }
  function binary(next, ops, apply) {
    return function parse() {
      var left = next()
      while (peek() && peek().type === "op" && ops.indexOf(peek().value) !== -1) {
        var op = take().value
        var right = next()
        left = (function(l, r, o) { return function(n) { return apply(o, l(n), r(n)) } })(left, right, op)
      }
      return left
    }
  }
  var mul = binary(unary, ["*", "/", "%"], function(o, a, b) {
    if (o === "*") return a * b
    if (b === 0) return 0
    return o === "/" ? Math.floor(a / b) : a % b
  })
  var add = binary(mul, ["+", "-"], function(o, a, b) { return o === "+" ? a + b : a - b })
  var rel = binary(add, ["<", ">", "<=", ">="], function(o, a, b) {
    if (o === "<") return a < b ? 1 : 0
    if (o === ">") return a > b ? 1 : 0
    if (o === "<=") return a <= b ? 1 : 0
    return a >= b ? 1 : 0
  })
  var eq = binary(rel, ["==", "!="], function(o, a, b) { return (o === "==" ? a === b : a !== b) ? 1 : 0 })
  var and = binary(eq, ["&&"], function(o, a, b) { return a && b ? 1 : 0 })
  var or = binary(and, ["||"], function(o, a, b) { return a || b ? 1 : 0 })
  function ternary() {
    var cond = or()
    if (!isOp("?")) return cond
    take("?")
    var yes = ternary()
    take(":")
    var no = ternary()
    return function(n) { return cond(n) ? yes(n) : no(n) }
  }

  var fn = ternary()
  if (pos !== tokens.length) throw new Error("plural expression: trailing tokens")
  return fn
}

// Returns { nplurals, plural(n) } or null when the header is absent/invalid.
function parsePluralForms(header) {
  var text = String(header || "")
  var countMatch = text.match(/nplurals\s*=\s*(\d+)/)
  var exprMatch = text.match(/plural\s*=\s*([^;]+)/)
  if (!countMatch || !exprMatch) return null
  var nplurals = Number(countMatch[1])
  if (!(nplurals >= 1)) return null
  var expr
  try { expr = parsePluralExpression(exprMatch[1]) } catch (e) { return null }
  return {
    nplurals: nplurals,
    plural: function(n) {
      var count = Math.abs(Math.floor(Number(n) || 0))
      var index = Number(expr(count))
      if (!(index >= 0)) index = 0
      if (index >= nplurals) index = nplurals - 1
      return index
    }
  }
}

// ---------------------------------------------------------------------------
// Catalog validation. A catalog is a plain object; the "" entry is a header
// object; every other value is a string or an array of strings. Anything else
// is dropped entry-by-entry so one bad line does not lose the whole file.

function sanitizeCatalog(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null
  var out = {}
  for (var key in raw) {
    if (!Object.prototype.hasOwnProperty.call(raw, key)) continue
    var value = raw[key]
    if (key === "") {
      if (value && typeof value === "object" && !Array.isArray(value)) out[""] = value
      continue
    }
    if (typeof value === "string") { out[key] = value; continue }
    if (Array.isArray(value) && value.length > 0) {
      var ok = true
      for (var i = 0; i < value.length; i++) if (typeof value[i] !== "string") { ok = false; break }
      if (ok) out[key] = value.slice()
    }
  }
  return out
}

function headerPluralForms(catalog) {
  var header = catalog && catalog[""]
  if (!header) return null
  return parsePluralForms(header["plural-forms"] || header["Plural-Forms"])
}

// ---------------------------------------------------------------------------
// Registry. Holds every owner's catalogs and links, and derives:
//   merged[domain]  one catalog per domain, owners folded by precedence
//   global          every domain folded into one map, parents before children
//   parents         child domain -> parent domain
// Derived state is rebuilt on every change; catalogs are small and changes
// are rare (login, plugin toggles), so simplicity wins over incrementality.

function createRegistry() {
  var owners = {}          // ownerId -> { catalogs, links, precedence, order }
  var nextOrder = 0
  var state = { revision: 0, merged: {}, global: {}, parents: {}, plurals: {} }

  // The startup cache is registered as an ordinary owner at the lowest
  // precedence so it can answer lookups for the frames before the real packs
  // register. It is only ever a stand-in: once a live pack has registered,
  // the cache copy is dropped and no longer reloadable, so disabling that
  // pack actually reverts the interface instead of falling back to a stale
  // duplicate of the strings it just removed.
  var CACHE_OWNER = "cache"
  var liveOwnerSeen = false

  // Fold a list of owners into { merged, parents, plurals, global }.
  function computeState(list) {
    // Lower precedence number wins. Among equals, the later registration
    // wins, which is what lets a pack refresh itself by re-registering.
    list = list.slice().sort(function(a, b) {
      return a.precedence !== b.precedence ? b.precedence - a.precedence : a.order - b.order
    })

    var merged = {}
    var parents = {}
    var domainOrder = []
    for (var i = 0; i < list.length; i++) {
      var owner = list[i]
      for (var domain in owner.catalogs) {
        if (!merged[domain]) { merged[domain] = {}; domainOrder.push(domain) }
        var cat = owner.catalogs[domain]
        for (var key in cat) merged[domain][key] = cat[key]
      }
      for (var child in owner.links) parents[child] = owner.links[child]
    }

    var plurals = {}
    for (var d = 0; d < domainOrder.length; d++) {
      plurals[domainOrder[d]] = headerPluralForms(merged[domainOrder[d]])
    }

    // Global merge: a domain's ancestors are folded before it, so a clone's
    // translation shadows the original's for unbound callers.
    var global = {}
    var folded = {}
    function fold(domain, depth) {
      if (folded[domain] || depth > 16) return
      folded[domain] = true
      if (parents[domain] && merged[parents[domain]]) fold(parents[domain], depth + 1)
      var cat = merged[domain]
      for (var key in cat) if (key !== "") global[key] = { value: cat[key], domain: domain }
    }
    for (var o = 0; o < domainOrder.length; o++) fold(domainOrder[o], 0)

    return { merged: merged, global: global, parents: parents, plurals: plurals }
  }

  function ownerList(excludeId) {
    var list = []
    for (var id in owners) if (id !== excludeId) list.push(owners[id])
    return list
  }

  function rebuild() {
    var next = computeState(ownerList())
    state.merged = next.merged
    state.global = next.global
    state.parents = next.parents
    state.plurals = next.plurals
    state.revision++
  }

  // Domain chain for a bound caller: the domain, then its parents.
  function chain(domain) {
    var out = []
    var seen = {}
    var current = domain ? String(domain) : ""
    while (current && !seen[current] && out.length < 16) {
      seen[current] = true
      out.push(current)
      current = state.parents[current]
    }
    return out
  }

  // Per-key lookup. Returns { value, domain } or null.
  function lookup(key, domain) {
    var domains = chain(domain)
    for (var i = 0; i < domains.length; i++) {
      var cat = state.merged[domains[i]]
      if (cat && Object.prototype.hasOwnProperty.call(cat, key) && key !== "") {
        return { value: cat[key], domain: domains[i] }
      }
    }
    return Object.prototype.hasOwnProperty.call(state.global, key) ? state.global[key] : null
  }

  function translate(source, options) {
    var opts = options || {}
    var fallback = String(source === undefined || source === null ? "" : source)
    var key = contextKey(opts.context, fallback)
    var hit = lookup(key, opts.domain)
    var value = hit ? hit.value : fallback
    if (Array.isArray(value)) value = value[0]
    return interpolate(value, opts.args)
  }

  function translatePlural(count, singular, plural, options) {
    var opts = options || {}
    var n = Number(count) || 0
    var key = contextKey(opts.context, String(singular === undefined || singular === null ? "" : singular))
    var hit = lookup(key, opts.domain)
    var text
    if (hit && Array.isArray(hit.value)) {
      var rule = state.plurals[hit.domain] || ENGLISH_PLURAL
      var index = rule.plural(n)
      text = hit.value[index] !== undefined ? hit.value[index] : hit.value[hit.value.length - 1]
    } else if (hit && typeof hit.value === "string") {
      text = hit.value
    } else {
      text = ENGLISH_PLURAL.plural(n) === 0 ? singular : plural
    }
    return interpolate(text, opts.args)
  }

  // Replace an owner's whole contribution atomically.
  //   catalogs   { domain: catalog }
  //   options    { links: { child: parent }, precedence: number }
  function setCatalogs(ownerId, catalogs, options) {
    var opts = options || {}
    var clean = {}
    var raw = catalogs && typeof catalogs === "object" ? catalogs : {}
    for (var domain in raw) {
      var cat = sanitizeCatalog(raw[domain])
      if (cat) clean[String(domain)] = cat
    }
    var links = {}
    var rawLinks = opts.links && typeof opts.links === "object" ? opts.links : {}
    for (var child in rawLinks) {
      if (typeof rawLinks[child] === "string" && rawLinks[child] && rawLinks[child] !== child) {
        links[String(child)] = rawLinks[child]
      }
    }
    var existing = owners[ownerId]
    owners[ownerId] = {
      catalogs: clean,
      links: links,
      precedence: typeof opts.precedence === "number" ? opts.precedence : 0,
      order: nextOrder++
    }
    if (ownerId !== CACHE_OWNER) {
      liveOwnerSeen = true
      delete owners[CACHE_OWNER]
    }
    rebuild()
    return existing ? "replaced" : "added"
  }

  function clearOwner(ownerId) {
    if (!owners[ownerId]) return false
    delete owners[ownerId]
    rebuild()
    return true
  }

  // Serializable view of the merged state, for the startup cache. The
  // snapshot excludes the cache owner: otherwise disabling every pack would
  // write the old cache back out and the translations would return at the
  // next login.
  function snapshot(options) {
    var exclude = options && options.exclude !== undefined ? options.exclude : CACHE_OWNER
    var view = computeState(ownerList(exclude))
    var catalogs = {}
    for (var domain in view.merged) catalogs[domain] = view.merged[domain]
    var links = {}
    for (var child in view.parents) links[child] = view.parents[child]
    return { version: 1, catalogs: catalogs, links: links }
  }

  function loadSnapshot(snap, ownerId) {
    if (!snap || typeof snap !== "object" || snap.version !== 1) return false
    // Writing the cache re-triggers the FileView that loads it. Without this
    // a pack's own registration would come straight back in as a cache owner
    // that outlives it.
    if (liveOwnerSeen && (ownerId || CACHE_OWNER) === CACHE_OWNER) return false
    setCatalogs(ownerId || CACHE_OWNER, snap.catalogs, { links: snap.links, precedence: 1000 })
    return true
  }

  return {
    setCatalogs: setCatalogs,
    clearOwner: clearOwner,
    lookup: lookup,
    chain: chain,
    translate: translate,
    translatePlural: translatePlural,
    snapshot: snapshot,
    loadSnapshot: loadSnapshot,
    domains: function() { var out = []; for (var d in state.merged) out.push(d); return out },
    owners: function() { var out = []; for (var o in owners) out.push(o); return out },
    revision: function() { return state.revision }
  }
}

if (typeof module !== "undefined") module.exports = {
  CONTEXT_SEPARATOR: CONTEXT_SEPARATOR,
  normalizeLocale: normalizeLocale,
  localeCandidates: localeCandidates,
  interpolate: interpolate,
  contextKey: contextKey,
  parsePluralForms: parsePluralForms,
  sanitizeCatalog: sanitizeCatalog,
  createRegistry: createRegistry
}
