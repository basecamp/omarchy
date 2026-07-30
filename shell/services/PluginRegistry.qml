import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Instance, not a singleton — see BarWidgetRegistry for rationale.
QtObject {
  id: registry

  property string home: Quickshell.env("HOME")
  property string pluginsDir: home + "/.config/omarchy/plugins"

  // Set by shell.qml at startup so we can also scan bundled first-party plugins.
  property string firstPartyDir: ""

  // Wired by shell.qml so the registry can read the canonical shell.json
  // without owning file IO itself. shellConfigProvider returns the current
  // effective shell config; shellConfigMutator takes a function that receives
  // a deep-cloned config it can mutate in place and persists the result.
  property var shellConfigProvider: null
  property var shellConfigMutator: null

  // { pluginId: manifest } — manifests have __sourceDir and __isFirstParty stamped in.
  property var installedPlugins: ({})
  property int registryRevision: 0
  property bool scanning: false

  signal pluginsChanged()
  signal scanFinished()
  signal pluginLoadFailed(string id, string error)
  signal localPluginChanged(string id)

  // ---------------------------------------------------------------- helpers

  function isSafeEntryPoint(value) {
    if (typeof value !== "string" || value.length === 0) return false
    if (value.charAt(0) === "/") return false
    if (value.indexOf("..") !== -1) return false
    return true
  }

  function validateManifest(manifest, sourcePath) {
    if (!Util.isPlainObject(manifest)) {
      console.warn("PluginRegistry: manifest is not an object at " + sourcePath)
      return null
    }
    if (manifest.schemaVersion !== 1) {
      console.warn("PluginRegistry: unsupported schemaVersion at " + sourcePath)
      return null
    }
    var required = ["id", "name", "version", "kinds", "entryPoints"]
    for (var i = 0; i < required.length; i++) {
      if (manifest[required[i]] === undefined) {
        console.warn("PluginRegistry: missing required field '" + required[i] + "' at " + sourcePath)
        return null
      }
    }
    var id = String(manifest.id)
    if (!id || id.indexOf("/") !== -1 || id.indexOf("..") !== -1 || id.charAt(0) === "/") {
      console.warn("PluginRegistry: invalid plugin id '" + id + "' at " + sourcePath)
      return null
    }
    if (!Array.isArray(manifest.kinds) || manifest.kinds.length === 0) {
      console.warn("PluginRegistry: kinds must be a non-empty array at " + sourcePath)
      return null
    }
    if (!Util.isPlainObject(manifest.entryPoints)) {
      console.warn("PluginRegistry: entryPoints must be an object at " + sourcePath)
      return null
    }
    if (manifest.barWidget !== undefined && Util.isPlainObject(manifest.barWidget)
        && manifest.barWidget.defaultSection !== undefined) {
      var defaultSection = String(manifest.barWidget.defaultSection)
      if (["left", "center", "right"].indexOf(defaultSection) === -1) {
        console.warn("PluginRegistry: invalid barWidget.defaultSection at " + sourcePath)
        return null
      }
    }
    // Every entry point must be a relative path inside the plugin's source
    // directory. Reject the whole manifest if anything looks like an attempt
    // to escape the plugin's sandbox.
    for (var key in manifest.entryPoints) {
      if (!isSafeEntryPoint(manifest.entryPoints[key])) {
        console.warn("PluginRegistry: unsafe entryPoint '" + key + "'='"
          + manifest.entryPoints[key] + "' at " + sourcePath)
        return null
      }
    }
    return manifest
  }

  function entryPointUrl(manifest, kind) {
    if (!Util.isPlainObject(manifest)) return ""
    var ep = manifest.entryPoints ? manifest.entryPoints[kind] : null
    if (!ep) return ""
    var dir = manifest.__sourceDir || ""
    if (!dir) return ""
    // Defense in depth: even after validateManifest, confirm the resolved
    // path stays inside the plugin's sourceDir.
    var resolved = dir.replace(/\/$/, "") + "/" + String(ep)
    var expectedPrefix = dir.replace(/\/$/, "") + "/"
    if (resolved.indexOf(expectedPrefix) !== 0) {
      console.warn("PluginRegistry: entry point escapes sourceDir: " + resolved)
      return ""
    }
    return Util.fileUrl(resolved)
  }

  // Enabled = the plugin id is referenced somewhere in shell.json. That can
  // be either the active bar option in `bar.id`, a layout entry inside
  // `bar.layout.*` (bar widgets), or a top-level entry in `plugins[]` (panels,
  // overlays, services).
  //
  // Special cases (implicitly always enabled, no shell.json entry needed):
  //   - the built-in bar option (`omarchy.bar`) is active when `bar.id` is
  //     missing or set to `omarchy.bar`.
  //   - first-party non-bar plugins are shell infrastructure (settings,
  //     image-picker, ...). Requiring users to add them to plugins[] just to
  //     summon them was a footgun: a stock shell.json with `plugins: []` would
  //     silently make `omarchy launch bar-settings` a no-op. Turning one off
  //     is therefore recorded the other way round, in `disabledPlugins[]`.
  function isEnabled(id) {
    var key = String(id)
    var manifest = installedPlugins[key]
    var config = shellConfigProvider ? shellConfigProvider() : null
    if (manifest) {
      if (Array.isArray(manifest.kinds) && manifest.kinds.indexOf("bar") !== -1) {
        var selectedBar = ""
        if (Util.isPlainObject(config) && Util.isPlainObject(config.bar))
          selectedBar = Util.canonicalWidgetId(String(config.bar.id || ""))
        if (!selectedBar) selectedBar = "omarchy.bar"
        return selectedBar === key
      }
      if (isDisabled(config, key)) return false
      if (manifest.__isFirstParty) return true
    }
    return findEntryLocation(config, key).found
  }

  function isDisabled(config, id) {
    return Util.isPlainObject(config) && Array.isArray(config.disabledPlugins)
      && config.disabledPlugins.indexOf(Util.canonicalWidgetId(String(id))) !== -1
  }

  function resolveEnabledId(id) {
    var key = Util.canonicalWidgetId(String(id || ""))
    // Callers keep using the built-in id after cloning; the enabled local
    // manifest is the implementation that should receive the call.
    for (var candidate in installedPlugins) {
      var manifest = installedPlugins[candidate]
      var metadata = manifest && Util.isPlainObject(manifest.omarchy) ? manifest.omarchy : null
      if (metadata && String(metadata.clonedFrom || "") === key && isEnabled(candidate))
        return candidate
    }
    return key
  }

  // A bar widget is on when it sits in the bar, whoever shipped it. That is a
  // different question from isEnabled(), which decides whether the widget's
  // component is loaded at all — a built-in stays loadable so it can be put
  // back, and so a plugin that is both a widget and a menu (omarchy.menu)
  // cannot be locked out of the shell by taking its button off the bar.
  function inBar(id) {
    var config = shellConfigProvider ? shellConfigProvider() : null
    return findEntryLocation(config, id).kind === "bar"
  }

  function defaultBarWidgetSection(manifest) {
    var metadata = manifest && Util.isPlainObject(manifest.barWidget) ? manifest.barWidget : null
    var section = metadata ? String(metadata.defaultSection || "") : ""
    return ["left", "center", "right"].indexOf(section) !== -1 ? section : "center"
  }

  function findEntryLocation(config, id) {
    if (!Util.isPlainObject(config)) return { found: false }
    var key = Util.canonicalWidgetId(String(id))
    if (Util.isPlainObject(config.bar)) {
      var selectedBar = Util.canonicalWidgetId(String(config.bar.id || ""))
      if (selectedBar === key) return { found: true, kind: "bar-option" }
    }
    if (Util.isPlainObject(config.bar) && Util.isPlainObject(config.bar.layout)) {
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) {
        var arr = config.bar.layout[sections[s]]
        if (!Array.isArray(arr)) continue
        for (var i = 0; i < arr.length; i++) {
          if (arr[i] && Util.canonicalWidgetId(arr[i].id) === key) return { found: true, kind: "bar", section: sections[s], index: i }
        }
      }
    }
    if (Array.isArray(config.plugins)) {
      for (var j = 0; j < config.plugins.length; j++) {
        if (config.plugins[j] && Util.canonicalWidgetId(config.plugins[j].id) === key) return { found: true, kind: "plugin", index: j }
      }
    }
    return { found: false }
  }

  // Bar widgets use the default section declared in their manifest, falling
  // back to center. Panels/overlays/menus/services go into the plugins[] array.
  // Built-ins are already loaded, so shell.json only ever records the
  // deviation: an added third-party plugin in plugins[], a switched-off
  // built-in in disabledPlugins[].
  function setEnabled(id, value) {
    var key = Util.canonicalWidgetId(String(id))
    if (!shellConfigMutator) {
      console.warn("PluginRegistry.setEnabled called before shellConfigMutator wired")
      return false
    }
    var manifest = installedPlugins[key]
    if (value && !manifest) {
      console.warn("PluginRegistry.setEnabled: unknown plugin " + key)
      return false
    }
    var isBarOption = manifest && Array.isArray(manifest.kinds) && manifest.kinds.indexOf("bar") !== -1
    var isBarWidget = manifest && Array.isArray(manifest.kinds) && manifest.kinds.indexOf("bar-widget") !== -1
    var hasNonWidgetKind = manifest && Array.isArray(manifest.kinds)
      && manifest.kinds.some(function(kind) { return kind !== "bar-widget" })
    shellConfigMutator(function(config) {
      // Ensure shape exists.
      if (!Util.isPlainObject(config.bar)) config.bar = { layout: { left: [], center: [], right: [] } }
      if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = { left: [], center: [], right: [] }
      if (!Array.isArray(config.plugins)) config.plugins = []

      if (isBarOption) {
        if (value) {
          config.bar.id = key
        } else if (Util.canonicalWidgetId(String(config.bar.id || "")) === key) {
          delete config.bar.id
        }
        return
      }

      var isFirstParty = manifest && manifest.__isFirstParty
      var location = findEntryLocation(config, key)

      if (value) {
        // Leave shell.json without the key once nothing is switched off, so a
        // config that never disabled anything reads as it always did.
        if (Array.isArray(config.disabledPlugins)) {
          config.disabledPlugins = config.disabledPlugins.filter(function(entry) { return entry !== key })
          if (config.disabledPlugins.length === 0) delete config.disabledPlugins
        }
        if (location.found) return
        var entry = { id: key }
        if (isBarWidget) {
          var section = defaultBarWidgetSection(manifest)
          if (!Array.isArray(config.bar.layout[section])) config.bar.layout[section] = []
          config.bar.layout[section].push(entry)
        } else if (!isFirstParty) {
          config.plugins.push(entry)
        }
        return
      }

      if (location.kind === "bar") config.bar.layout[location.section].splice(location.index, 1)
      else if (location.kind === "plugin") config.plugins.splice(location.index, 1)
      // Dropping the layout entry is the whole story for a widget. Anything
      // else built-in loads by default, so switching it off has to be stated.
      if (isFirstParty && (!isBarWidget || hasNonWidgetKind) && !isDisabled(config, key)) {
        if (!Array.isArray(config.disabledPlugins)) config.disabledPlugins = []
        config.disabledPlugins.push(key)
      }
    })
    registryRevision++
    pluginsChanged()
    return true
  }

  // ---------------------------------------------------------------- scanning

  // Output format produced by the rescan script:
  //   ===<kind>::<absolute-source-dir>===
  //   ... raw manifest.json content ...
  //   === EOM ===
  // (repeating for every manifest found)
  function parseScanOutput(text) {
    var lines = String(text || "").split("\n")
    var firstParty = {}
    var thirdParty = {}
    var currentSource = null
    var currentKind = null
    var currentJson = []

    function flush() {
      if (!currentSource) return
      var raw = currentJson.join("\n").trim()
      try {
        var manifest = JSON.parse(raw)
        manifest.__sourceDir = currentSource
        manifest.__isFirstParty = (currentKind === "firstparty")
        var validated = validateManifest(manifest, currentSource + "/manifest.json")
        if (validated) {
          if (currentKind === "firstparty") firstParty[validated.id] = validated
          else thirdParty[validated.id] = validated
        }
      } catch (e) {
        console.warn("PluginRegistry: bad manifest at " + currentSource + ": " + e)
      }
      currentSource = null
      currentKind = null
      currentJson = []
    }

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var startMatch = line.match(/^===([a-z]+)::(.+)===$/)
      if (startMatch) {
        flush()
        currentKind = startMatch[1]
        currentSource = startMatch[2].replace(/\/$/, "")
        currentJson = []
        continue
      }
      if (line === "=== EOM ===") {
        flush()
        continue
      }
      if (currentSource) currentJson.push(line)
    }
    flush()

    var merged = {}
    for (var fk in firstParty) merged[fk] = firstParty[fk]
    // Third-party plugins never shadow first-party ids. The whole
    // `omarchy.*` namespace is reserved for built-ins, including bar widgets
    // registered outside the manifest-based plugin registry.
    for (var tk in thirdParty) {
      if (firstParty[tk] || String(tk).indexOf("omarchy.") === 0) {
        console.warn("PluginRegistry: plugin " + tk
          + " rejected: id is reserved for first-party Omarchy plugins")
        continue
      }
      merged[tk] = thirdParty[tk]
    }

    installedPlugins = merged
    registryRevision++
    scanning = false
    pluginsChanged()
    scanFinished()
  }

  property Process scanProcess: Process {
    onExited: function(exitCode) {
      var output = scanStdout.text || ""
      registry.parseScanOutput(output)
    }
    stdout: StdioCollector {
      id: scanStdout
      waitForEnd: true
    }
  }

  property Process initProcess: Process {
    onExited: {
      localPluginWatcher.running = true
      registry.rescan()
    }
  }

  property Process localPluginWatcher: Process {
    command: [
      "inotifywait",
      "-m",
      "-r",
      "-q",
      "-e",
      "close_write,create,delete,move",
      "--format",
      "%w%f",
      registry.pluginsDir
    ]
    stdout: SplitParser {
      onRead: function(path) {
        var pluginId = registry.localPluginIdForPath(path)
        if (pluginId) registry.localPluginChanged(pluginId)
      }
    }
    onExited: localPluginWatcherRestart.restart()
  }

  property Timer localPluginWatcherRestart: Timer {
    interval: 1000
    onTriggered: localPluginWatcher.running = true
  }

  function rescan() {
    if (scanning) return
    scanning = true
    // $0 = first-party dir, $1 = third-party dir. Some bash versions need the explicit -- separator.
    // First-party plugins may be grouped one level deeper, e.g. panels/audio
    // or services/battery.
    // First-party bar widgets can also carry sibling manifests such as
    // widgets/Clock.manifest.json so multiple widgets can live in one source
    // directory without wrapper folders.
    // Third-party plugins stay at the top level of ~/.config/omarchy/plugins.
    var script = ""
      + "emit_manifest() { local kind=\"$1\"; local manifest=\"$2\"; local sub; "
      + "  if [[ ${manifest##*/} == \"manifest.json\" ]]; then sub=\"${manifest%/manifest.json}\"; else sub=\"$(dirname -- \"$manifest\")\"; fi; "
      + "  printf '===%s::%s===\\n' \"$kind\" \"$sub\"; "
      + "  cat \"$manifest\"; "
      + "  printf '\\n=== EOM ===\\n'; "
      + "}; "
      + "scan_firstparty() { local dir=\"$1\"; "
      + "  [[ -d \"$dir\" ]] || return 0; "
      + "  while IFS= read -r manifest; do emit_manifest firstparty \"$manifest\"; done < <(find \"$dir\" -mindepth 2 -maxdepth 3 -type f \\( -name manifest.json -o -name '*.manifest.json' \\) | sort); "
      + "}; "
      + "scan_thirdparty() { local dir=\"$1\"; "
      + "  [[ -d \"$dir\" ]] || return 0; "
      + "  for sub in \"$dir\"/*/; do "
      + "    [[ -f \"$sub/manifest.json\" ]] || continue; "
      + "    emit_manifest thirdparty \"$sub/manifest.json\"; "
      + "  done; "
      + "}; "
      + "scan_firstparty \"$0\"; "
      + "scan_thirdparty \"$1\""
    scanProcess.command = ["bash", "-c", script, registry.firstPartyDir, registry.pluginsDir]
    scanProcess.running = true
  }

  function ensureUserDir() {
    initProcess.command = ["bash", "-c", "mkdir -p \"$0\"", registry.pluginsDir]
    initProcess.running = true
  }

  function localPluginIdForPath(filePath) {
    var base = pluginsDir.replace(/\/$/, "") + "/"
    var path = String(filePath || "").trim()
    if (path.indexOf(base + "local.") !== 0) return ""

    var relative = path.slice(base.length)
    if (relative.indexOf("/.git/") !== -1 || relative.endsWith("/.git")) return ""

    var slash = relative.indexOf("/")
    return slash === -1 ? relative : relative.slice(0, slash)
  }

  Component.onCompleted: ensureUserDir()
}
