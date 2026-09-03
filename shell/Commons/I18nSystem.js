// I18nSystem.js — system gettext catalogs as an Omarchy translation source.
//
// Linux distributions already ship translations for the common UI vocabulary
// ("Save", "Open", "Close", …) in /usr/share/locale/<locale>/LC_MESSAGES/*.mo.
// This module turns the PO text produced by `msgunfmt` into the po2json-shaped
// catalog the I18n registry understands, so the shell uses those translations
// by default. Plugin authors only ship an i18n.json for strings the system
// catalogs do not cover.
//
// No Qt or QML dependencies: QML loads it with `import "I18nSystem.js" as
// System`, tests require it under node. The Qt-side Process that runs
// msgunfmt lives in I18n.qml.
//
// Catalog build rules:
//   - fuzzy and untranslated entries are dropped
//   - GTK/Qt accelerator markers are normalized: "_Save" and "&Save" also
//     register under "Save" (plain keys win when both exist)
//   - the first domain wins on conflicts; later domains only fill gaps
//   - the gettext header (plural rules) of the first domain is kept

"use strict"

// ---------------------------------------------------------------------------
// Minimal PO reader (msgunfmt output): msgctxt, msgid, msgid_plural,
// msgstr[n], multi-line strings, flags.

function parsePoEntries(text) {
  var entries = []
  var cur = null
  var target = null // "msgid" | "msgid_plural" | "msgctxt" | "msgstr" | "msgstr[n]"

  function flush() {
    if (cur && (cur.msgid !== "" || cur.msgctxt !== null || cur.msgstr.length > 0)) {
      if (!cur.obsolete) entries.push(cur)
    }
    cur = null
  }

  function unescape(s) {
    return s.replace(/\\(n|t|r|"|\\)/g, function(_, c) {
      return { n: "\n", t: "\t", r: "\r", '"': '"', "\\": "\\" }[c]
    })
  }

  var lines = String(text || "").replace(/\r\n/g, "\n").split("\n")
  var pendingFlags = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]

    if (line.indexOf("#~") === 0) { if (cur) cur.obsolete = true; continue }
    if (line.indexOf("#") === 0) {
      // Comments (incl. flags) always precede the entry they describe:
      // finish any pending entry so flags never leak into the previous one.
      flush()
      if (line.indexOf("#,") === 0) {
        var flagParts = line.slice(2).trim().split(/\s*,\s*/)
        for (var fp = 0; fp < flagParts.length; fp++) {
          if (flagParts[fp]) pendingFlags.push(flagParts[fp])
        }
      }
      continue
    }

    function makeEntry() {
      var e = { msgctxt: null, msgid: "", msgid_plural: null, msgstr: [], flags: [], obsolete: false }
      for (var pf = 0; pf < pendingFlags.length; pf++) e.flags.push(pendingFlags[pf])
      pendingFlags = []
      return e
    }

    var m
    if ((m = line.match(/^msgctxt\s+"(.*)"\s*$/))) {
      flush()
      cur = makeEntry()
      cur.msgctxt = unescape(m[1])
      target = "msgctxt"
    } else if ((m = line.match(/^msgid\s+"(.*)"\s*$/))) {
      if (!cur || cur.msgid !== "" || cur.msgctxt === null) {
        flush()
        cur = makeEntry()
        cur.msgid = unescape(m[1])
      } else {
        cur.msgid = unescape(m[1])
      }
      target = "msgid"
    } else if ((m = line.match(/^msgid_plural\s+"(.*)"\s*$/))) {
      if (cur) { cur.msgid_plural = unescape(m[1]); target = "msgid_plural" }
    } else if ((m = line.match(/^msgstr\[(\d+)\]\s+"(.*)"\s*$/))) {
      if (cur) { cur.msgstr[Number(m[1])] = unescape(m[2]); target = "msgstr[" + m[1] + "]" }
    } else if ((m = line.match(/^msgstr\s+"(.*)"\s*$/))) {
      if (cur) { cur.msgstr[0] = unescape(m[1]); target = "msgstr[0]" }
    } else if ((m = line.match(/^"(.*)"\s*$/))) {
      if (cur && target) {
        var value = unescape(m[1])
        if (target === "msgid") cur.msgid += value
        else if (target === "msgid_plural") cur.msgid_plural += value
        else if (target === "msgctxt") cur.msgctxt += value
        else if (target.slice(0, 6) === "msgstr") cur.msgstr[Number(target.slice(7, -1))] += value
      }
    }
  }
  flush()
  return entries
}

// ---------------------------------------------------------------------------
// Accelerator normalization. GTK marks mnemonics with an underscore anywhere
// in the string ("_Save", "Sa_ve"); Qt/KDE prefix an ampersand ("&Save").
// The translated string keeps its own marker — only the lookup key changes.

function stripAccelerators(msgid) {
  var s = String(msgid)
  if (s.charAt(0) === "&") s = s.slice(1)
  return s.split("_").join("")
}

// ---------------------------------------------------------------------------
// Catalog builder. texts is an array of PO document strings (one per system
// domain, most preferred first). Returns the po2json-shaped catalog.

function buildCatalog(texts) {
  var catalog = {}
  var headerDone = false

  for (var t = 0; t < texts.length; t++) {
    var entries = parsePoEntries(texts[t])
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e.msgctxt) continue // contextual entries are not reachable via tr()
      if (e.flags.indexOf("fuzzy") !== -1) continue
      if (e.msgid === "") {
        // Gettext header: keep the first one (plural rules, language).
        if (!headerDone && e.msgstr[0]) {
          var header = {}
          e.msgstr[0].split("\n").forEach(function(row) {
            var idx = row.indexOf(": ")
            if (idx > 0) header[row.slice(0, idx)] = row.slice(idx + 2)
          })
          if (header["Content-Type"]) delete header["Content-Type"]
          catalog[""] = header
          headerDone = true
        }
        continue
      }
      var untranslated = !e.msgstr[0]
      if (untranslated && !e.msgid_plural) continue

      if (e.msgid_plural) {
        if (catalog[e.msgid] === undefined) {
          catalog[e.msgid] = { msgid_plural: e.msgid_plural, msgstr: e.msgstr.slice() }
        }
        // Plain variant without accelerators, on both msgid and msgstr:
        // "Pane" must yield "Panel"/"Paneles", not accelerator-marked text.
        var plainP = stripAccelerators(e.msgid)
        if (plainP !== e.msgid && plainP && catalog[plainP] === undefined) {
          catalog[plainP] = {
            msgid_plural: stripAccelerators(e.msgid_plural),
            msgstr: e.msgstr.map(function(s) { return stripAccelerators(s) })
          }
        }
      } else {
        var value = e.msgstr[0]
        if (catalog[e.msgid] === undefined) catalog[e.msgid] = value
        // Plain variant: "Save" must yield "Guardar", not "_Guardar" — the
        // mnemonic marker lives in both the msgid and the msgstr.
        var plain = stripAccelerators(e.msgid)
        if (plain !== e.msgid && plain && catalog[plain] === undefined) {
          var plainValue = stripAccelerators(value)
          if (plainValue) catalog[plain] = plainValue
        }
      }
    }
  }

  if (!headerDone) delete catalog[""]
  return catalog
}

var api = { parsePoEntries: parsePoEntries, stripAccelerators: stripAccelerators, buildCatalog: buildCatalog }

if (typeof module !== "undefined" && module.exports) module.exports = api
