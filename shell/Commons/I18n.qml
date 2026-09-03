pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "I18nModel.js" as Model
import "I18nSystem.js" as System

// qs.Commons.I18n — the shell's translation primitive.
//
// This file owns everything that touches Qt: the environment, the cache file,
// system gettext loading, and reactivity. All lookup logic lives in
// I18nModel.js so it can be tested under node.
//
// Translation sources, lowest to highest precedence:
//   1. Startup snapshot (the persisted merge from the previous session)
//   2. System gettext catalogs — /usr/share/locale/<locale>/LC_MESSAGES/*.mo
//      (gtk30, gtk40, glib20, …) read via msgunfmt. This is the default
//      source: Linux already ships translations for the common UI
//      vocabulary, no packs or plugins required.
//   3. A plugin's own i18n.json — for strings the system catalogs do not
//      cover. Registered by shell.qml from manifest.__i18n.
//
// Call sites
//   I18n.tr("Connect")                          unbound: global merge
//   readonly property var _: I18n.domain("dev.foo.weather")
//   _.tr("Connect")  _.trc("verb", "Open")  _.ntr(n, "%1 city", "%1 cities", [n])
//
// With nothing registered every call returns its source string, so a stock
// install is unaffected. Catalogs arrive late — the msgunfmt process and the
// plugin registry finish after startup — so lookups read `revision` and any
// binding that called tr() re-evaluates when a catalog registers. To avoid
// a flash of English on every login, the merged catalogs are persisted to
// $XDG_CACHE_HOME/omarchy/i18n/<language>.json and loaded synchronously here,
// before the first frame. The Bash helper in default/bash/i18n reads the
// same file.

QtObject {
  id: root

  // ---------------------------------------------------------------------
  // Locale

  readonly property var candidates: Model.localeCandidates({
    LANGUAGE: Quickshell.env("LANGUAGE"),
    LC_ALL: Quickshell.env("LC_ALL"),
    LC_MESSAGES: Quickshell.env("LC_MESSAGES"),
    LANG: Quickshell.env("LANG")
  })

  // Primary language code ("ca" for ca_ES, or the first LANGUAGE entry).
  // Empty means English / C: nothing to translate and no cache to keep.
  readonly property string language: candidates.length > 0 ? candidates[0].split("_")[0] : ""

  // Where a pack's locale sits in the user's preference order, for use as
  // its registration precedence. -1 means the pack does not apply.
  function precedenceFor(locale) {
    var normalized = Model.normalizeLocale(locale)
    if (!normalized) return -1
    var index = candidates.indexOf(normalized)
    if (index === -1) index = candidates.indexOf(normalized.split("_")[0])
    return index
  }

  // ---------------------------------------------------------------------
  // Lookup

  // Bumped on every registry change. Read inside every lookup so QML
  // bindings that call tr() depend on it and repaint when catalogs change.
  property int revision: 0
  property var _registry: Model.createRegistry()

  function _lookup(source, options) {
    void root.revision
    return root._registry.translate(source, options)
  }

  function _lookupPlural(count, singular, plural, options) {
    void root.revision
    return root._registry.translatePlural(count, singular, plural, options)
  }

  function tr(source, args) {
    return _lookup(source, { args: args })
  }

  function trc(context, source, args) {
    return _lookup(source, { context: context, args: args })
  }

  function ntr(count, singular, plural, args) {
    return _lookupPlural(count, singular, plural, { args: args })
  }

  // Marks a string for extraction without translating it, for strings
  // defined away from where they are shown (a model returning a status).
  function noop(source) {
    return source
  }

  // A translator bound to one domain: lookups walk the domain, its
  // clonedFrom parents, then the global merge.
  function domain(id) {
    var d = String(id === undefined || id === null ? "" : id)
    return {
      id: d,
      tr: function(source, args) {
        return root._lookup(source, { domain: d, args: args })
      },
      trc: function(context, source, args) {
        return root._lookup(source, { domain: d, context: context, args: args })
      },
      ntr: function(count, singular, plural, args) {
        return root._lookupPlural(count, singular, plural, { domain: d, args: args })
      },
      noop: function(source) { return source }
    }
  }

  // ---------------------------------------------------------------------
  // Registration

  // Replace an owner's whole contribution atomically.
  //   catalogs  { domain: catalog }   one po2json-shaped object per domain
  //   options   { links: { childDomain: parentDomain }, precedence: int }
  function setCatalogs(ownerId, catalogs, options) {
    var result = root._registry.setCatalogs(String(ownerId), catalogs, options)
    root._changed()
    return result
  }

  function clearCatalogs(ownerId) {
    var removed = root._registry.clearOwner(String(ownerId))
    if (removed) root._changed()
    return removed
  }

  function _changed() {
    root.revision = root._registry.revision()
    root.cacheWriteTimer.restart()
  }

  // ---------------------------------------------------------------------
  // System gettext catalogs
  //
  // Runs once at startup: for the first candidate locale that has any of
  // the well-known desktop domains, msgunfmt concatenates them into PO
  // text, which I18nSystem.js folds into one catalog. Registered below the
  // plugin i18n.json source so an author can still override a string.
  // The merge is persisted into the startup snapshot, so subsequent logins
  // render translated on the first frame and this process only refreshes.

  readonly property var systemDomains: ["gtk30", "gtk40", "glib20", "gdk-pixbuf", "gnome-desktop-3.0"]

  function _systemCatalogCommand() {
    var candidates = []
    for (var i = 0; i < root.candidates.length; i++) {
      // /usr/share/locale directories never carry an encoding suffix.
      var bare = String(root.candidates[i]).replace(/\..*$/, "")
      if (bare && candidates.indexOf(bare) === -1) candidates.push(bare)
    }
    if (candidates.length === 0) return []

    var script = ""
      + "DOMAINS=\"" + root.systemDomains.join(" ") + "\"\n"
      + "for loc in " + candidates.join(" ") + "; do\n"
      + "  files=\"\"\n"
      + "  for d in $DOMAINS; do\n"
      + "    f=\"/usr/share/locale/$loc/LC_MESSAGES/$d.mo\"\n"
      + "    [ -f \"$f\" ] && files=\"$files '$f'\"\n"
      + "  done\n"
      + "  if [ -n \"$files\" ]; then\n"
      + "    echo \"X-OMARCHY-SYSTEM-LOCALE: $loc\"\n"
      + "    eval msgunfmt --no-wrap $files\n"
      + "    exit 0\n"
      + "  fi\n"
      + "done\n"
      + "exit 1\n"
    return ["bash", "-c", script]
  }

  property Process systemCatalogProcess: Process {
    command: root._systemCatalogCommand()
    running: true
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var output = systemCatalogStdout.text || ""
      var marker = output.indexOf("\n")
      if (marker === -1) return
      var catalog = System.buildCatalog([output.slice(marker + 1)])
      var keys = Object.keys(catalog).length
      if (keys > 0) {
        console.log("I18n: system gettext catalog for " + root.candidates.join(", ")
          + " (" + (keys - (catalog[""] ? 1 : 0)) + " entries)")
        root.setCatalogs("system:gettext", ({ "omarchy.system": catalog }), { precedence: 200 })
      }
    }
    stdout: StdioCollector {
      id: systemCatalogStdout
      waitForEnd: true
    }
  }

  // ---------------------------------------------------------------------
  // Startup cache

  readonly property string cacheDir: {
    var xdg = Quickshell.env("XDG_CACHE_HOME")
    var base = xdg ? String(xdg) : String(Quickshell.env("HOME")) + "/.cache"
    return base.replace(/\/$/, "") + "/omarchy/i18n"
  }
  readonly property string cachePath: language ? cacheDir + "/" + language + ".json" : ""

  property FileView cacheFile: FileView {
    path: root.cachePath
    // Synchronous on purpose: the whole point is having catalogs before the
    // bar's first frame. The file is small and local.
    blockLoading: true
    atomicWrites: true
    printErrors: false
    onLoaded: root._loadCache(text())
    // No cache yet, or unreadable: English until a pack registers.
    onLoadFailed: function(error) { }
  }

  function _loadCache(raw) {
    var text = String(raw || "").trim()
    if (!text) return
    try {
      var parsed = JSON.parse(text)
      if (root._registry.loadSnapshot(parsed)) root.revision = root._registry.revision()
    } catch (error) {
      console.warn("I18n: ignoring unreadable cache at " + root.cachePath + ": " + error)
    }
  }

  // Registrations arrive in bursts (one pack per locale, a rescan); coalesce
  // them into one write.
  property Timer cacheWriteTimer: Timer {
    interval: 250
    repeat: false
    onTriggered: root._writeCache()
  }

  function _writeCache() {
    if (!root.cachePath) return
    var snapshot = root._registry.snapshot()
    root.cacheFile.setText(JSON.stringify(snapshot) + "\n")
  }
}
