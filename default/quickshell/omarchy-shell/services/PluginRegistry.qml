pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: registry

  property string home: Quickshell.env("HOME")
  property string pluginsDir: home + "/.config/omarchy/plugins"
  property string stateFile: home + "/.config/omarchy/plugins.json"

  // Set by shell.qml at startup so we can also scan bundled first-party plugins.
  property string firstPartyDir: ""

  // { pluginId: manifest } — manifests have __sourceDir and __isFirstParty stamped in.
  property var installedPlugins: ({})
  // { pluginId: { enabled: bool } } — persisted to stateFile.
  property var pluginStates: ({})
  property int registryRevision: 0
  property bool scanning: false

  signal pluginsChanged()
  signal pluginLoadFailed(string id, string error)

  // ---------------------------------------------------------------- helpers

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
  }

  function fileUrl(path) {
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
  }

  function validateManifest(manifest, sourcePath) {
    if (!isPlainObject(manifest)) {
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
    if (!isPlainObject(manifest.entryPoints)) {
      console.warn("PluginRegistry: entryPoints must be an object at " + sourcePath)
      return null
    }
    return manifest
  }

  function entryPointUrl(manifest, kind) {
    if (!isPlainObject(manifest)) return ""
    var ep = manifest.entryPoints ? manifest.entryPoints[kind] : null
    if (!ep) return ""
    var dir = manifest.__sourceDir || ""
    if (!dir) return ""
    return fileUrl(dir + "/" + ep)
  }

  function isEnabled(id) {
    var state = pluginStates[String(id)]
    return !!(state && state.enabled)
  }

  function setEnabled(id, value) {
    var key = String(id)
    var next = {}
    for (var k in pluginStates) next[k] = pluginStates[k]
    next[key] = { enabled: !!value }
    pluginStates = next
    persistStates()
    registryRevision++
    pluginsChanged()
  }

  function manifestsOfKind(kind) {
    var result = []
    for (var id in installedPlugins) {
      var m = installedPlugins[id]
      if (m && Array.isArray(m.kinds) && m.kinds.indexOf(kind) !== -1) result.push(m)
    }
    return result
  }

  // ---------------------------------------------------------------- persistence

  property bool suppressStateReload: false

  function persistStates() {
    suppressStateReload = true
    stateFileView.setText(JSON.stringify({ version: 1, states: pluginStates }, null, 2) + "\n")
  }

  property FileView stateFileView: FileView {
    path: registry.stateFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (registry.suppressStateReload) {
        registry.suppressStateReload = false
        return
      }
      try {
        var data = JSON.parse(text() || "{}")
        registry.pluginStates = (data && data.states) || {}
      } catch (e) {
        console.warn("PluginRegistry: bad plugins.json:", e)
        registry.pluginStates = {}
      }
    }
    onFileChanged: reload()
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

    // Merge defaults into pluginStates: first-party defaults to enabled, third-party to disabled.
    var nextStates = {}
    for (var k in pluginStates) nextStates[k] = pluginStates[k]
    for (var fpid in firstParty) {
      if (!nextStates[fpid]) nextStates[fpid] = { enabled: true }
    }
    for (var tpid in thirdParty) {
      if (!nextStates[tpid]) nextStates[tpid] = { enabled: false }
    }

    var merged = {}
    for (var fk in firstParty) merged[fk] = firstParty[fk]
    for (var tk in thirdParty) merged[tk] = thirdParty[tk]

    pluginStates = nextStates
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
    var script = ""
      + "scan() { local dir=\"$1\"; local kind=\"$2\"; "
      + "  [[ -d \"$dir\" ]] || return 0; "
      + "  for sub in \"$dir\"/*/; do "
      + "    [[ -f \"$sub/manifest.json\" ]] || continue; "
      + "    printf '===%s::%s===\\n' \"$kind\" \"$sub\"; "
      + "    cat \"$sub/manifest.json\"; "
      + "    printf '\\n=== EOM ===\\n'; "
      + "  done; "
      + "}; "
      + "scan \"$0\" firstparty; "
      + "scan \"$1\" thirdparty"
    scanProcess.command = ["bash", "-lc", script, registry.firstPartyDir, registry.pluginsDir]
    scanProcess.running = true
  }

  function ensureUserDir() {
    initProcess.command = ["bash", "-lc", "mkdir -p \"$0\"", registry.pluginsDir]
    initProcess.running = true
  }

  Component.onCompleted: ensureUserDir()
}
