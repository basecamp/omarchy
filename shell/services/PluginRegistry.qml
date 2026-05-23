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
  signal pluginLoadFailed(string id, string error)

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
  // be either a layout entry inside `bar.layout.*` (bar widgets) or a top-level
  // entry in `plugins[]` (panels, overlays, services).
  //
  // Special cases (implicitly always enabled, no shell.json entry needed):
  //   - plugins whose `kinds` contains "bar" are mounted directly by the host.
  //   - first-party plugins are shell infrastructure (settings,
  //     image-picker, ...). Requiring users to add them to plugins[] just to
  //     summon them was a footgun: a stock shell.json with `plugins: []` would
  //     silently make `omarchy launch bar-settings` a no-op.
  function isEnabled(id) {
    var key = String(id)
    var manifest = installedPlugins[key]
    if (manifest) {
      if (Array.isArray(manifest.kinds) && manifest.kinds.indexOf("bar") !== -1) return true
      if (manifest.__isFirstParty) return true
    }
    var config = shellConfigProvider ? shellConfigProvider() : null
    return findEntryLocation(config, key).found
  }

  function findEntryLocation(config, id) {
    if (!Util.isPlainObject(config)) return { found: false }
    var key = Util.canonicalWidgetId(String(id))
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

  // Adding a plugin places it in the right section based on its declared
  // kinds. Bar widgets default to the right section; panels/overlays/menus/
  // services go into the plugins[] array.
  function setEnabled(id, value) {
    var key = Util.canonicalWidgetId(String(id))
    if (!shellConfigMutator) {
      console.warn("PluginRegistry.setEnabled called before shellConfigMutator wired")
      return
    }
    var manifest = installedPlugins[key]
    var isBarWidget = manifest && Array.isArray(manifest.kinds) && manifest.kinds.indexOf("bar-widget") !== -1
    shellConfigMutator(function(config) {
      // Ensure shape exists.
      if (!Util.isPlainObject(config.bar)) config.bar = { layout: { left: [], center: [], right: [] } }
      if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = { left: [], center: [], right: [] }
      if (!Array.isArray(config.plugins)) config.plugins = []
      var location = findEntryLocation(config, key)
      if (value && !location.found) {
        var entry = { id: key }
        if (isBarWidget) {
          if (!Array.isArray(config.bar.layout.right)) config.bar.layout.right = []
          config.bar.layout.right.push(entry)
        } else {
          config.plugins.push(entry)
        }
      } else if (!value && location.found) {
        if (location.kind === "bar") {
          config.bar.layout[location.section].splice(location.index, 1)
        } else {
          config.plugins.splice(location.index, 1)
        }
      }
    })
    registryRevision++
    pluginsChanged()
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
    onExited: registry.rescan()
  }

  function rescan() {
    if (scanning) return
    scanning = true
    // $0 = first-party dir, $1 = third-party dir. Some bash versions need the explicit -- separator.
    // First-party plugins may be grouped one level deeper, e.g. services/battery.
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

  Component.onCompleted: ensureUserDir()
}
