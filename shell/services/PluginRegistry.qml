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
  property string lastEnableError: ""

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

  function barEntryId(entry) {
    return Util.canonicalWidgetId(String(Util.isPlainObject(entry) ? entry.id : entry || ""))
  }

  function findBarLocation(config, id, section) {
    if (!Util.isPlainObject(config) || !Util.isPlainObject(config.bar)
        || !Util.isPlainObject(config.bar.layout)) return { found: false }
    var key = Util.canonicalWidgetId(String(id))
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      if (section && sections[s] !== section) continue
      var entries = config.bar.layout[sections[s]]
      if (!Array.isArray(entries)) continue
      for (var i = 0; i < entries.length; i++) {
        if (barEntryId(entries[i]) === key)
          return { found: true, kind: "bar", section: sections[s], index: i }
      }
    }
    return { found: false }
  }

  // A caller naming a widget that has been cloned means the clone that took
  // its place, the way resolveEnabledId routes calls to it.
  function findRelativeBarLocation(config, id, section) {
    var location = findBarLocation(config, id, section)
    if (location.found) return location
    if (!Util.isPlainObject(config) || !Util.isPlainObject(config.bar)) return { found: false }
    var clone = activeCloneFor(config, Util.canonicalWidgetId(String(id)))
    return clone ? findBarLocation(config, clone, section) : { found: false }
  }

  function findEntryLocation(config, id) {
    if (!Util.isPlainObject(config)) return { found: false }
    var key = Util.canonicalWidgetId(String(id))
    if (Util.isPlainObject(config.bar)) {
      var selectedBar = Util.canonicalWidgetId(String(config.bar.id || ""))
      if (selectedBar === key) return { found: true, kind: "bar-option" }
    }
    if (Util.isPlainObject(config.bar) && Util.isPlainObject(config.bar.layout)) {
      var barLocation = findBarLocation(config, key, "")
      if (barLocation.found) return barLocation
    }
    if (Array.isArray(config.plugins)) {
      for (var j = 0; j < config.plugins.length; j++) {
        if (config.plugins[j] && Util.canonicalWidgetId(config.plugins[j].id) === key) return { found: true, kind: "plugin", index: j }
      }
    }
    return { found: false }
  }

  function barTarget(config, placement, fallbackSection) {
    var target = placement || {}
    var section = ["left", "center", "right"].indexOf(String(target.section || "")) !== -1
      ? String(target.section) : fallbackSection
    var relativeId = String(target.before || target.after || "")
    if (relativeId) {
      var relative = findRelativeBarLocation(config, relativeId, section && target.section ? section : "")
      if (!relative.found) return { error: "could not find target widget " + relativeId }
      return {
        section: relative.section,
        index: relative.index + (target.after ? 1 : 0)
      }
    }

    if (!Array.isArray(config.bar.layout[section])) config.bar.layout[section] = []
    if (target.index !== undefined && target.index !== null) {
      var requested = Math.max(0, Math.floor(Number(target.index)))
      return { section: section, index: Math.min(requested, config.bar.layout[section].length) }
    }

    var anchors = { left: "omarchy.workspaces", center: "omarchy.weather", right: "omarchy.tray" }
    var anchor = findRelativeBarLocation(config, anchors[section], section)
    return {
      section: section,
      index: anchor.found ? anchor.index + 1 : config.bar.layout[section].length
    }
  }

  function moveBarEntry(config, id, placement) {
    var key = Util.canonicalWidgetId(String(id))
    var source
    if (placement.fromIndex !== undefined && placement.fromIndex !== null) {
      var fromSection = String(placement.fromSection || "")
      if (!fromSection) return "from-index requires from-section"
      var entries = config.bar.layout[fromSection]
      var fromIndex = Math.floor(Number(placement.fromIndex))
      if (!Array.isArray(entries) || fromIndex < 0 || fromIndex >= entries.length)
        return "no widget at " + fromSection + "[" + fromIndex + "]"
      if (barEntryId(entries[fromIndex]) !== key)
        return "widget at " + fromSection + "[" + fromIndex + "] is not " + key
      source = { found: true, section: fromSection, index: fromIndex }
    } else {
      source = findBarLocation(config, key, String(placement.fromSection || ""))
      if (!source.found) return "could not find widget " + key
    }

    var entry = config.bar.layout[source.section][source.index]
    config.bar.layout[source.section].splice(source.index, 1)
    var target = barTarget(config, placement, source.section)
    if (target.error) {
      config.bar.layout[source.section].splice(source.index, 0, entry)
      return target.error
    }
    config.bar.layout[target.section].splice(target.index, 0, entry)
    return ""
  }

  function moveBarWidget(id, placement) {
    var error = ""
    shellConfigMutator(function(config) {
      ensureConfigShape(config)
      error = moveBarEntry(config, id, placement || {})
    })
    if (error) return error
    registryRevision++
    pluginsChanged()
    return ""
  }

  // put is the unattended verb: where enable errors, it falls back, and it
  // leaves a widget that is already on the bar where its owner put it.
  function putBarWidget(id, placement) {
    if (inBar(id)) return ""
    var config = shellConfigProvider ? shellConfigProvider() : null
    // Enabling a source whose clone is active switches back to the built-in,
    // which is the owner's call, not an unattended caller's.
    if (findRelativeBarLocation(config, id, "").found) return ""
    // The manifest scan is a subprocess and IPC answers before it returns, so
    // an id it has not reached yet is not one that does not exist.
    if (scanning && !installedPlugins[Util.canonicalWidgetId(String(id))]) return "not ready"
    var target = Util.isPlainObject(placement) ? Util.cloneJson(placement) : {}
    var relativeId = String(target.before || target.after || "")
    if (relativeId) {
      if (!findRelativeBarLocation(config, relativeId, String(target.section || "")).found) {
        delete target.before
        delete target.after
      }
    }
    if (setEnabled(id, true, target)) return ""
    return lastEnableError || "unknown"
  }

  function setBarWidget(id, key, value, selector) {
    var error = ""
    shellConfigMutator(function(config) {
      ensureConfigShape(config)
      var location
      var requested = selector || {}
      var section = String(requested.fromSection || requested.section || "")
      var index = requested.fromIndex !== undefined && requested.fromIndex !== null
        ? requested.fromIndex : requested.index
      if (index !== undefined && index !== null) {
        if (!section) {
          error = "index requires section"
          return
        }
        var entries = config.bar.layout[section]
        var numericIndex = Math.floor(Number(index))
        if (!Array.isArray(entries) || numericIndex < 0 || numericIndex >= entries.length) {
          error = "no widget at " + section + "[" + numericIndex + "]"
          return
        }
        location = { found: true, section: section, index: numericIndex }
      } else {
        location = findBarLocation(config, id, section)
      }
      if (!location.found) {
        error = "could not find widget " + id
        return
      }
      if (barEntryId(config.bar.layout[location.section][location.index]) !== String(id)) {
        error = "widget at " + location.section + "[" + location.index + "] is not " + id
        return
      }
      var entry = config.bar.layout[location.section][location.index]
      if (!Util.isPlainObject(entry)) {
        error = "widget entry must be an object"
        return
      }
      entry[String(key)] = value
    })
    if (error) return error
    registryRevision++
    pluginsChanged()
    return ""
  }

  function ensureConfigShape(config) {
    if (!Util.isPlainObject(config.bar)) config.bar = { layout: { left: [], center: [], right: [] } }
    if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = { left: [], center: [], right: [] }
    var sections = ["left", "center", "right"]
    for (var i = 0; i < sections.length; i++) {
      if (!Array.isArray(config.bar.layout[sections[i]])) config.bar.layout[sections[i]] = []
    }
    if (!Array.isArray(config.plugins)) config.plugins = []
  }

  // Bar widgets use the default section declared in their manifest, falling
  // back to center. Panels/overlays/menus/services go into the plugins[] array.
  // Built-ins are already loaded, so shell.json only ever records the
  // deviation: an added third-party plugin in plugins[], a switched-off
  // built-in in disabledPlugins[].
  function removeDisabled(config, id) {
    if (!Array.isArray(config.disabledPlugins)) return
    config.disabledPlugins = config.disabledPlugins.filter(function(entry) { return entry !== id })
    if (config.disabledPlugins.length === 0) delete config.disabledPlugins
  }

  function addDisabled(config, id) {
    if (isDisabled(config, id)) return
    if (!Array.isArray(config.disabledPlugins)) config.disabledPlugins = []
    config.disabledPlugins.push(id)
  }

  function cloneShouldRestoreSource(config, id) {
    return Array.isArray(config.cloneSourceRestores) && config.cloneSourceRestores.indexOf(id) !== -1
  }

  function setCloneShouldRestoreSource(config, id, value) {
    var restores = Array.isArray(config.cloneSourceRestores) ? config.cloneSourceRestores : []
    restores = restores.filter(function(entry) { return entry !== id })
    if (value) restores.push(id)
    if (restores.length) config.cloneSourceRestores = restores
    else delete config.cloneSourceRestores
  }

  function activeCloneFor(config, sourceId) {
    for (var candidate in installedPlugins) {
      var candidateManifest = installedPlugins[candidate]
      var candidateMetadata = candidateManifest && Util.isPlainObject(candidateManifest.omarchy)
        ? candidateManifest.omarchy : null
      if (!candidateMetadata || String(candidateMetadata.clonedFrom || "") !== sourceId) continue
      if (Array.isArray(candidateManifest.kinds) && candidateManifest.kinds.indexOf("bar") !== -1) {
        if (Util.canonicalWidgetId(String(config.bar.id || "")) === candidate) return candidate
      } else if (findEntryLocation(config, candidate).found) {
        return candidate
      }
    }
    return ""
  }

  function restoreCloneSource(config, cloneId, sourceId) {
    var cloneManifest = installedPlugins[cloneId]
    var isBarOption = cloneManifest && Array.isArray(cloneManifest.kinds)
      && cloneManifest.kinds.indexOf("bar") !== -1
    if (isBarOption) {
      if (sourceId === "omarchy.bar") delete config.bar.id
      else config.bar.id = sourceId
    } else {
      var cloneLocation = findEntryLocation(config, cloneId)
      if (cloneLocation.kind === "bar") {
        var cloneEntry = config.bar.layout[cloneLocation.section][cloneLocation.index]
        var sections = ["left", "center", "right"]
        for (var s = 0; s < sections.length; s++) {
          for (var i = config.bar.layout[sections[s]].length - 1; i >= 0; i--) {
            if (barEntryId(config.bar.layout[sections[s]][i]) === sourceId)
              config.bar.layout[sections[s]].splice(i, 1)
          }
        }
        cloneLocation = findBarLocation(config, cloneId, "")
        if (cloneLocation.found) {
          var restoredEntry = Util.isPlainObject(cloneEntry) ? Util.cloneJson(cloneEntry) : {}
          restoredEntry.id = sourceId
          config.bar.layout[cloneLocation.section][cloneLocation.index] = restoredEntry
        }
      } else if (cloneLocation.kind === "plugin") {
        config.plugins.splice(cloneLocation.index, 1)
      }
    }

    if (cloneShouldRestoreSource(config, cloneId)) removeDisabled(config, sourceId)
    setCloneShouldRestoreSource(config, cloneId, false)
  }

  function setEnabled(id, value, placement) {
    var key = Util.canonicalWidgetId(String(id))
    lastEnableError = ""
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
    var metadata = manifest && Util.isPlainObject(manifest.omarchy) ? manifest.omarchy : null
    var clonedFrom = metadata ? Util.canonicalWidgetId(String(metadata.clonedFrom || "")) : ""
    shellConfigMutator(function(config) {
      ensureConfigShape(config)

      if (value && placement && (placement.before || placement.after)) {
        var relativeId = String(placement.before || placement.after)
        if (!findRelativeBarLocation(config, relativeId, String(placement.section || "")).found) {
          lastEnableError = "could not find target widget " + relativeId
          return
        }
      }

      if (value && manifest && manifest.__isFirstParty) {
        var activeClone = activeCloneFor(config, key)
        if (activeClone) {
          restoreCloneSource(config, activeClone, key)
          removeDisabled(config, key)
        }
      }

      if (isBarOption) {
        if (value) {
          config.bar.id = key
        } else if (Util.canonicalWidgetId(String(config.bar.id || "")) === key) {
          if (clonedFrom && clonedFrom !== "omarchy.bar") config.bar.id = clonedFrom
          else delete config.bar.id
        }
        return
      }

      var isFirstParty = manifest && manifest.__isFirstParty
      var location = findEntryLocation(config, key)

      if (value) {
        removeDisabled(config, key)
        var entry = { id: key }
        var insertedWithPlacement = false
        if (!location.found && isBarWidget) {
          var sourceLocation = clonedFrom ? findEntryLocation(config, clonedFrom) : { found: false }
          if (sourceLocation.kind === "bar") {
            var sourceEntry = config.bar.layout[sourceLocation.section][sourceLocation.index]
            var replacement = Util.isPlainObject(sourceEntry) ? Util.cloneJson(sourceEntry) : entry
            replacement.id = key
            config.bar.layout[sourceLocation.section][sourceLocation.index] = replacement
          } else {
            var section = defaultBarWidgetSection(manifest)
            var target = barTarget(config, placement || {}, section)
            config.bar.layout[target.section].splice(target.index, 0, entry)
            insertedWithPlacement = true
          }
        } else if (!location.found && !isFirstParty) {
          config.plugins.push(entry)
        }

        if (isBarWidget && !insertedWithPlacement && placement && Object.keys(placement).length)
          moveBarEntry(config, key, placement)

        if (clonedFrom && hasNonWidgetKind && !isDisabled(config, clonedFrom)) {
          addDisabled(config, clonedFrom)
          setCloneShouldRestoreSource(config, key, true)
        }
        return
      }

      if (clonedFrom) restoreCloneSource(config, key, clonedFrom)
      else if (location.kind === "bar") config.bar.layout[location.section].splice(location.index, 1)
      else if (location.kind === "plugin") config.plugins.splice(location.index, 1)

      // Dropping the layout entry is the whole story for a widget. Anything
      // else built-in loads by default, so switching it off has to be stated.
      if (isFirstParty && !isBarWidget) addDisabled(config, key)
    })
    if (lastEnableError) return false
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
    if (path.indexOf(base) !== 0) return ""

    var relative = path.slice(base.length)
    // Hidden entries are not plugins: clone staging dirs, remove backups.
    if (relative.indexOf(".") === 0) return ""
    if (relative.indexOf("/.git/") !== -1 || relative.endsWith("/.git")) return ""

    var slash = relative.indexOf("/")
    return slash === -1 ? relative : relative.slice(0, slash)
  }

  Component.onCompleted: ensureUserDir()
}
