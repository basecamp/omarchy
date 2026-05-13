import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io

import "plugins/bar"
import "services"
import "compat/noctalia" as Compat
import qs.Services.UI as NoctaliaUI
import qs.Commons as NoctaliaCommons

ShellRoot {
  id: shell

  // Shared service instances. Plugins receive these via property injection
  // rather than re-importing them as singletons — relative-path imports do
  // not share singleton state, which silently leaves consumers with their
  // own empty copies.
  property PluginRegistry pluginRegistry: PluginRegistry { }
  property BarWidgetRegistry barWidgetRegistry: BarWidgetRegistry { }

  property string home: Quickshell.env("HOME")

  // The omarchy-shell host is the long-running entry point. Plugins live in
  // sibling directories under plugins/. Most child code (the bar, future
  // plugins) accept omarchyPath as a required property; resolve it once here
  // from the shellDir so we don't depend on OMARCHY_PATH being set in the env.
  function deriveOmarchyPath() {
    var env = Quickshell.env("OMARCHY_PATH")
    if (env) return env
    var dir = String(Quickshell.shellDir || "")
    if (dir.indexOf("/default/quickshell/omarchy-shell") !== -1)
      return dir.substring(0, dir.indexOf("/default/quickshell/omarchy-shell"))
    return home + "/.local/share/omarchy"
  }
  property string omarchyPath: deriveOmarchyPath()
  readonly property string firstPartyPluginsDir: omarchyPath + "/default/quickshell/omarchy-shell/plugins"
  readonly property string defaultsPath: omarchyPath + "/default/quickshell/omarchy-shell/shell-defaults.json"
  readonly property string userConfigPath: home + "/.config/omarchy/shell.json"

  // Bundled fallback so the shell can start even when shell-defaults.json is
  // missing or unreadable. The bar config here mirrors the on-disk defaults
  // closely enough to render a usable bar; not authoritative.
  readonly property var builtinShellConfig: ({
    version: 1,
    bar: {
      position: "top",
      fontFamily: "JetBrainsMono Nerd Font",
      centerAnchor: "calendar",
      layout: {
        left: [{ id: "omarchy" }, { id: "workspacesPro" }],
        center: [{ id: "calendar", format: "dddd HH:mm" }],
        right: [{ id: "audioPanel" }, { id: "controlCenter" }, { id: "powerMenu" }]
      }
    },
    plugins: [
      { id: "omarchy.bar-settings" },
      { id: "omarchy.image-picker" }
    ]
  })

  property var defaultsConfig: builtinShellConfig
  property var shellConfig: builtinShellConfig
  property bool suppressUserReload: false

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
  }

  function applyShellConfig() {
    // Decide which source is canonical: a valid user shell.json overrides
    // defaults entirely; otherwise fall back to defaults. We do not deep-merge.
    var defaults = isPlainObject(defaultsConfig) ? defaultsConfig : builtinShellConfig
    var user = null
    var userText = userConfigFile.text() || ""
    if (userText.trim()) {
      try {
        var parsed = JSON.parse(userText)
        if (isPlainObject(parsed) && parsed.version === 1) user = parsed
        else if (isPlainObject(parsed)) console.warn("shell.json missing version: 1, using defaults")
      } catch (e) {
        console.warn("shell.json parse failed, using defaults:", e)
      }
    }
    shellConfig = user || defaults
  }

  function loadDefaults(raw) {
    var text = String(raw || "").trim()
    if (!text) {
      defaultsConfig = builtinShellConfig
      applyShellConfig()
      return
    }
    try {
      var parsed = JSON.parse(text)
      if (isPlainObject(parsed) && parsed.version === 1) defaultsConfig = parsed
      else defaultsConfig = builtinShellConfig
    } catch (e) {
      console.warn("shell-defaults.json parse failed, using builtin:", e)
      defaultsConfig = builtinShellConfig
    }
    applyShellConfig()
  }

  function persistShellConfig(nextConfig) {
    suppressUserReload = true
    var payload = JSON.parse(JSON.stringify(nextConfig))
    payload.version = 1
    shellConfig = payload
    userConfigFile.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  readonly property var barConfig: shellConfig && isPlainObject(shellConfig.bar) ? shellConfig.bar : builtinShellConfig.bar
  readonly property var pluginsConfig: shellConfig && Array.isArray(shellConfig.plugins) ? shellConfig.plugins : []

  FileView {
    id: defaultsFile
    path: shell.defaultsPath
    watchChanges: true
    printErrors: false
    onLoaded: shell.loadDefaults(text())
    onLoadFailed: function(error) {
      console.warn("shell-defaults load failed: " + error + " path=" + shell.defaultsPath)
      shell.loadDefaults("")
    }
    onFileChanged: reload()
  }

  FileView {
    id: userConfigFile
    path: shell.userConfigPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (shell.suppressUserReload) {
        shell.suppressUserReload = false
        return
      }
      shell.applyShellConfig()
    }
    onLoadFailed: function(error) { shell.applyShellConfig() }
    onFileChanged: reload()
  }

  Component.onCompleted: {
    console.log("omarchy-shell paths",
      "omarchyPath=" + shell.omarchyPath,
      "shellDir=" + Quickshell.shellDir,
      "firstPartyPluginsDir=" + shell.firstPartyPluginsDir,
      "defaultsPath=" + shell.defaultsPath,
      "userConfigPath=" + shell.userConfigPath)
    pluginRegistry.firstPartyDir = shell.firstPartyPluginsDir
    pluginRegistry.shellConfigProvider = function() { return shell.shellConfig }
    pluginRegistry.shellConfigMutator = function(mutate) { shell.mutateShellConfig(mutate) }
    // PluginRegistry.ensureUserDir() runs in its own Component.onCompleted and
    // chains rescan() once the directory exists. We also kick a scan here in
    // case the user dir already existed at startup.
    pluginRegistry.rescan()

    // Wire Noctalia compat singletons. Plugins read state from these globals;
    // we hand them references to the host so they can route into the right
    // popup, tooltip, etc.
    NoctaliaUI.BarService.bar = bar
    NoctaliaUI.TooltipService.bar = bar
    NoctaliaUI.PanelService.bar = bar
    NoctaliaUI.PanelService.shell = shell
    NoctaliaCommons.Settings.shellConfig = shell.shellConfig
  }

  // Keep Noctalia.Settings.data in sync with whatever shell.json currently is.
  onShellConfigChanged: NoctaliaCommons.Settings.shellConfig = shell.shellConfig

  function mutateShellConfig(mutator) {
    var copy = JSON.parse(JSON.stringify(shellConfig || builtinShellConfig))
    mutator(copy)
    persistShellConfig(copy)
  }

  Bar {
    id: bar
    omarchyPath: shell.omarchyPath
    barWidgetRegistry: shell.barWidgetRegistry
    barConfig: shell.barConfig
    pluginRegistry: shell.pluginRegistry
    shell: shell
  }

  // ------------------------------------------------- Noctalia plugin API
  //
  // One pluginApi instance per plugin, cached for the life of the shell. The
  // factory is host-owned (shell, not bar) so non-bar Noctalia plugins
  // (panels, services) can call into it too. Settings lookups walk the live
  // shell.json on every read so reorders/edits never leave a stale entry
  // captured in the closure.
  Compat.PluginApiFactory { id: noctaliaApiFactory }

  property var _noctaliaApis: ({})
  property var _noctaliaServices: ({})

  function findShellEntry(pluginId) {
    var config = shellConfig
    if (!isPlainObject(config)) return null
    if (isPlainObject(config.bar) && isPlainObject(config.bar.layout)) {
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) {
        var arr = config.bar.layout[sections[s]]
        if (!Array.isArray(arr)) continue
        for (var i = 0; i < arr.length; i++) {
          if (arr[i] && arr[i].id === pluginId) return arr[i]
        }
      }
    }
    if (Array.isArray(config.plugins)) {
      for (var p = 0; p < config.plugins.length; p++) {
        if (config.plugins[p] && config.plugins[p].id === pluginId) return config.plugins[p]
      }
    }
    return null
  }

  function noctaliaPluginApiFor(pluginId) {
    var key = String(pluginId)
    if (!key) return null
    var existing = _noctaliaApis[key]
    if (existing) return existing
    var manifest = pluginRegistry && pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins[key] : null
    if (!manifest || !manifest.__noctaliaCompat) return null

    var api = noctaliaApiFactory.create(
      key,
      manifest,
      function() {
        // Compute effective settings on every read. We can't capture an entry
        // reference because mutateSection rebuilds the layout objects and the
        // captured reference would point at a snapshot.
        var defaults = (manifest.barWidget && manifest.barWidget.defaults) || manifest.defaults || {}
        var merged = {}
        for (var k in defaults) merged[k] = defaults[k]
        var entry = findShellEntry(key)
        if (entry) {
          for (var ek in entry) if (ek !== "id") merged[ek] = entry[ek]
        }
        return merged
      },
      {
        persistSettings: function(_pluginId, settings) {
          if (typeof shell.updateEntryInline === "function")
            shell.updateEntryInline(key, settings)
        },
        openPanel: function(_pluginId, _screen, _btn) {
          shell.summon(key, JSON.stringify({ source: "noctalia" }))
        },
        closePanel: function(_pluginId, _screen) { shell.hide(key) },
        currentScreen: function() {
          var screens = Quickshell.screens
          return screens && screens.length > 0 ? screens[0] : null
        }
      }
    )

    var next = ({})
    for (var existingKey in _noctaliaApis) next[existingKey] = _noctaliaApis[existingKey]
    next[key] = api
    _noctaliaApis = next
    return api
  }

  // -------------------------------------------------- noctalia service main
  //
  // Noctalia plugins with `entryPoints.main` (translated to kind="service")
  // are instantiated once per shell session when enabled. The Main.qml is
  // typically headless — a data source the plugin's bar widget reads from.
  // We rely on the shared pluginApi so the service and any bar widgets see
  // the same handle.
  function ensureNoctaliaService(pluginId) {
    var key = String(pluginId)
    if (_noctaliaServices[key]) return _noctaliaServices[key]
    var manifest = pluginRegistry && pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins[key] : null
    if (!manifest || !manifest.__noctaliaCompat) return null
    if (!manifest.entryPoints || !manifest.entryPoints.service) return null
    var url = pluginRegistry.entryPointUrl(manifest, "service")
    if (!url) return null
    var api = noctaliaPluginApiFor(key)
    if (!api) return null

    var comp = Qt.createComponent(url, Component.PreferSynchronous)
    function finalize() {
      if (comp.status !== Component.Ready) {
        console.warn("noctalia service load failed for " + key + ": " + comp.errorString())
        return
      }
      var inst = comp.createObject(shell, { pluginApi: api })
      if (!inst) {
        console.warn("noctalia service createObject returned null for", key)
        return
      }
      var snext = ({})
      for (var sk in _noctaliaServices) snext[sk] = _noctaliaServices[sk]
      snext[key] = inst
      _noctaliaServices = snext
      api.mainInstance = inst
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
      return null
    }
    finalize()
    return _noctaliaServices[key] || null
  }

  function _syncNoctaliaServices() {
    if (!pluginRegistry || !pluginRegistry.installedPlugins) return
    var plugins = pluginRegistry.installedPlugins
    for (var id in plugins) {
      var m = plugins[id]
      if (!m || !m.__noctaliaCompat) continue
      if (!m.entryPoints || !m.entryPoints.service) continue
      if (!pluginRegistry.isEnabled(id)) continue
      if (_noctaliaServices[id]) continue
      ensureNoctaliaService(id)
    }
    // Drop services for plugins that have been disabled or removed.
    for (var existingId in _noctaliaServices) {
      var stillThere = plugins[existingId]
      var stillEnabled = stillThere && pluginRegistry.isEnabled(existingId)
      if (stillThere && stillEnabled) continue
      var inst = _noctaliaServices[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
      var next = ({})
      for (var k in _noctaliaServices) if (k !== existingId) next[k] = _noctaliaServices[k]
      _noctaliaServices = next
      var apis = ({})
      for (var ak in _noctaliaApis) apis[ak] = _noctaliaApis[ak]
      if (apis[existingId]) apis[existingId].mainInstance = null
      _noctaliaApis = apis
    }
  }

  Connections {
    target: shell.pluginRegistry
    function onPluginsChanged() { shell._syncNoctaliaServices() }
  }

  // Used by Noctalia compat: pluginApi.saveSettings() ends up writing inline
  // settings to the plugin's entry in shell.json. moduleName is the entry id
  // (the bare manifest id, e.g. "noctalia.air-quality"); settings is the
  // merged plugin state. Returns true if anything actually changed.
  // Compute the proposed new shellConfig in a local clone, and only persist
  // if anything actually changed. Lets Noctalia plugins call saveSettings()
  // repeatedly with identical values (common for reactive QML bindings)
  // without dirtying shell.json or thrashing the file watcher.
  function updateEntryInline(moduleName, settings) {
    var stripped = String(moduleName)
    var copy = JSON.parse(JSON.stringify(shellConfig || builtinShellConfig))
    if (!isPlainObject(copy.bar)) copy.bar = { layout: { left: [], center: [], right: [] } }
    if (!isPlainObject(copy.bar.layout)) copy.bar.layout = { left: [], center: [], right: [] }
    if (!Array.isArray(copy.plugins)) copy.plugins = []

    var sections = ["left", "center", "right"]
    var foundInLayout = false
    var dirty = false
    for (var s = 0; s < sections.length; s++) {
      var arr = copy.bar.layout[sections[s]] || []
      for (var i = 0; i < arr.length; i++) {
        if (arr[i] && arr[i].id === stripped) {
          var next = { id: stripped }
          for (var k in settings) if (k !== "id") next[k] = settings[k]
          if (JSON.stringify(arr[i]) !== JSON.stringify(next)) {
            arr[i] = next
            dirty = true
          }
          foundInLayout = true
        }
      }
    }
    if (!foundInLayout) {
      for (var j = 0; j < copy.plugins.length; j++) {
        if (copy.plugins[j] && copy.plugins[j].id === stripped) {
          var pnext = { id: stripped }
          for (var pk in settings) if (pk !== "id") pnext[pk] = settings[pk]
          if (JSON.stringify(copy.plugins[j]) !== JSON.stringify(pnext)) {
            copy.plugins[j] = pnext
            dirty = true
          }
        }
      }
    }
    if (!dirty) return false
    persistShellConfig(copy)
    return true
  }

  // ---------------------------------------------------------- on-demand panels

  // openPanelIds is a plain object treated as a set. A plugin id maps to
  // `true` while the panel is summoned; deleting the key (well, building a new
  // object without it) hides it. Reassigning the whole object is required for
  // QML to notice the change.
  property var openPanelIds: ({})

  function isPanelOpen(id) { return openPanelIds[id] === true }

  // Pending payloads to deliver to a plugin's open() once its loader resolves.
  // Keyed by plugin id; the value is an array so two summon() calls before
  // the Loader resolves both reach the plugin in arrival order rather than
  // the second clobbering the first.
  property var pendingPayloads: ({})

  function summon(pluginId, payloadJson) {
    var id = String(pluginId || "")
    if (!id) return false
    var plugins = shell.pluginRegistry.installedPlugins
    if (!plugins[id]) {
      console.warn("summon: unknown plugin", id)
      return false
    }
    var next = ({})
    for (var k in openPanelIds) next[k] = openPanelIds[k]
    next[id] = true
    openPanelIds = next

    // Stash payload so the Loader.onLoaded handler can hand it to open().
    var pending = ({})
    for (var p in pendingPayloads) pending[p] = pendingPayloads[p].slice()
    var queue = pending[id] || []
    queue.push(payloadJson || "")
    pending[id] = queue
    pendingPayloads = pending

    // If the plugin is keepLoaded and already mounted, deliver immediately.
    deliverIfLoaded(id)
    return true
  }

  function hide(pluginId) {
    var id = String(pluginId || "")
    if (!id) return false
    invokeIfLoaded(id, "close", null)
    if (!openPanelIds[id]) return true
    var next = ({})
    for (var k in openPanelIds) if (k !== id) next[k] = openPanelIds[k]
    openPanelIds = next
    return true
  }

  function toggle(pluginId, payloadJson) {
    var id = String(pluginId || "")
    return openPanelIds[id] ? hide(id) : summon(id, payloadJson)
  }

  // Map of pluginId -> Loader, populated by the Instantiator delegate below.
  property var panelLoaders: ({})

  function registerPanelLoader(pluginId, loader) {
    var next = ({})
    for (var k in panelLoaders) next[k] = panelLoaders[k]
    next[pluginId] = loader
    panelLoaders = next
    deliverIfLoaded(pluginId)
  }

  function unregisterPanelLoader(pluginId) {
    if (!panelLoaders[pluginId]) return
    var next = ({})
    for (var k in panelLoaders) if (k !== pluginId) next[k] = panelLoaders[k]
    panelLoaders = next
  }

  function deliverIfLoaded(pluginId) {
    var loader = panelLoaders[pluginId]
    if (!loader || !loader.item) return
    var queue = pendingPayloads[pluginId]
    if (!Array.isArray(queue) || queue.length === 0) return
    if (typeof loader.item.open === "function") {
      for (var i = 0; i < queue.length; i++) {
        try { loader.item.open(queue[i]) } catch (e) {
          console.warn("plugin " + pluginId + " open() threw:", e)
        }
      }
    }
    var next = ({})
    for (var k in pendingPayloads) if (k !== pluginId) next[k] = pendingPayloads[k].slice()
    pendingPayloads = next
  }

  function invokeIfLoaded(pluginId, method, arg) {
    var loader = panelLoaders[pluginId]
    if (!loader || !loader.item) return
    if (typeof loader.item[method] !== "function") return
    try { loader.item[method](arg) } catch (e) {
      console.warn("plugin " + pluginId + " " + method + "() threw:", e)
    }
  }

  // One Loader per discoverable panel/overlay/menu plugin. Active when the
  // host marks it open. The Loader holds onto the instance while active so the
  // plugin's FloatingWindow + state survive between summons within a session.
  property var panelEntries: []

  function computePanelEntries() {
    var out = []
    var plugins = shell.pluginRegistry.installedPlugins
    var panelKinds = ["panel", "overlay", "menu"]
    for (var id in plugins) {
      var m = plugins[id]
      if (!m || !Array.isArray(m.kinds)) continue
      var matched = false
      for (var i = 0; i < panelKinds.length; i++)
        if (m.kinds.indexOf(panelKinds[i]) !== -1) { matched = true; break }
      if (!matched) continue
      if (!shell.pluginRegistry.isEnabled(id)) continue
      var kind = m.kinds.indexOf("panel") !== -1 ? "panel"
        : (m.kinds.indexOf("overlay") !== -1 ? "overlay" : "menu")
      out.push({ id: id, manifest: m, kind: kind, keepLoaded: m.keepLoaded === true })
    }
    return out
  }

  Connections {
    target: shell.pluginRegistry
    function onPluginsChanged() { shell.panelEntries = shell.computePanelEntries() }
  }

  Instantiator {
    model: shell.panelEntries
    active: true

    delegate: QtObject {
      id: panelEntry
      required property var modelData
      readonly property string pluginId: modelData.id
      readonly property var manifest: modelData.manifest
      readonly property string entryKind: modelData.kind
      readonly property bool keepLoaded: modelData.keepLoaded === true
      readonly property string sourceUrl: shell.pluginRegistry.entryPointUrl(manifest, entryKind)

      property Loader panelLoader: Loader {
        source: panelEntry.sourceUrl
        active: panelEntry.sourceUrl !== "" && (panelEntry.keepLoaded || shell.openPanelIds[panelEntry.pluginId] === true)
        asynchronous: true
        onLoaded: {
          if (!item) return
          if ("omarchyPath" in item) item.omarchyPath = shell.omarchyPath
          if ("shell" in item) item.shell = shell
          if ("manifest" in item) item.manifest = panelEntry.manifest
          if ("barWidgetRegistry" in item) item.barWidgetRegistry = shell.barWidgetRegistry
          if ("pluginRegistry" in item) item.pluginRegistry = shell.pluginRegistry
          // Noctalia panel/overlay/menu plugins expect a pluginApi just like
          // their bar widgets do. First-party Omarchy plugins don't declare
          // the property so the `in target` check skips them.
          if (panelEntry.manifest && panelEntry.manifest.__noctaliaCompat && "pluginApi" in item)
            item.pluginApi = shell.noctaliaPluginApiFor(panelEntry.pluginId)
          shell.registerPanelLoader(panelEntry.pluginId, this)
        }
        onStatusChanged: {
          if (status === Loader.Error) {
            console.warn("panel plugin " + panelEntry.pluginId + " failed:",
              sourceComponent ? sourceComponent.errorString() : "")
            shell.hide(panelEntry.pluginId)
          }
        }
        Component.onDestruction: shell.unregisterPanelLoader(panelEntry.pluginId)
      }
    }
  }

  // ---------------------------------------------------------- plugin loader

  // Mirror plugin registry state into BarWidgetRegistry whenever it changes.
  // Each enabled plugin with kind "bar-widget" gets a Component created from
  // its manifest entry point and registered under its plain manifest id.
  // First-party widget ids (calendar, weather, etc.) are short and don't
  // collide with namespaced plugin ids like noctalia.air-quality, so we don't
  // need a separate "plugin:" namespace anymore.
  Connections {
    target: shell.pluginRegistry
    function onPluginsChanged() { shell.syncPluginWidgets() }
  }

  property var pluginWidgetComponents: ({})

  function syncPluginWidgets() {
    var plugins = shell.pluginRegistry.installedPlugins
    var seen = ({})

    for (var pluginId in plugins) {
      var manifest = plugins[pluginId]
      if (!manifest || !manifest.kinds || manifest.kinds.indexOf("bar-widget") === -1) continue
      if (!shell.pluginRegistry.isEnabled(pluginId)) continue

      var registryKey = String(manifest.id)
      seen[registryKey] = true

      // Already loaded with matching source — leave it alone.
      var existing = pluginWidgetComponents[registryKey]
      var url = shell.pluginRegistry.entryPointUrl(manifest, "barWidget")
      if (!url) {
        console.warn("Plugin " + manifest.id + " has no barWidget entry point")
        continue
      }
      if (existing && existing.url === url && shell.barWidgetRegistry.has(registryKey)) continue

      var meta = manifest.barWidget || {}
      meta = {
        displayName: meta.displayName || manifest.name,
        description: meta.description || manifest.description,
        category: meta.category || "Plugin",
        allowMultiple: meta.allowMultiple === true,
        defaults: meta.defaults || {},
        schema: meta.schema || [],
        pluginId: manifest.id,
        source: "plugin"
      }

      loadPluginWidget(registryKey, url, meta)
    }

    // Drop registrations for plugins that are no longer present or enabled.
    var allIds = shell.barWidgetRegistry.availableIds()
    for (var i = 0; i < allIds.length; i++) {
      var id = allIds[i]
      if (!pluginWidgetComponents[id]) continue
      if (!seen[id]) {
        shell.barWidgetRegistry.unregister(id)
        var next = ({})
        for (var k in pluginWidgetComponents) if (k !== id) next[k] = pluginWidgetComponents[k]
        pluginWidgetComponents = next
      }
    }
  }

  function loadPluginWidget(registryKey, url, meta) {
    var comp = Qt.createComponent(url, Component.Asynchronous)
    function finalize() {
      if (comp.status === Component.Ready) {
        shell.barWidgetRegistry.register(registryKey, comp, meta)
        var next = ({})
        for (var k in pluginWidgetComponents) next[k] = pluginWidgetComponents[k]
        next[registryKey] = { url: url, component: comp }
        pluginWidgetComponents = next
      } else if (comp.status === Component.Error) {
        console.warn("Plugin widget " + registryKey + " failed: " + comp.errorString())
        shell.pluginRegistry.pluginLoadFailed(registryKey, comp.errorString())
      }
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
    } else {
      finalize()
    }
  }

  // ---------------------------------------------------------- shell IPC

  IpcHandler {
    target: "shell"

    function ping(): string {
      return "ok"
    }

    function rescanPlugins(): void {
      shell.pluginRegistry.rescan()
    }

    function setPluginEnabled(id: string, enabled: string): void {
      shell.pluginRegistry.setEnabled(id, enabled === "true")
    }

    function listPlugins(): string {
      var out = []
      var plugins = shell.pluginRegistry.installedPlugins
      for (var id in plugins) {
        out.push({
          id: id,
          name: plugins[id].name,
          kinds: plugins[id].kinds,
          enabled: shell.pluginRegistry.isEnabled(id),
          firstParty: !!plugins[id].__isFirstParty
        })
      }
      return JSON.stringify(out)
    }

    // Returns the effective shell.json content as JSON. Useful for debugging
    // and for CLI tools that want to inspect the merged state without
    // re-implementing the load logic.
    function listShellConfig(): string {
      return JSON.stringify(shell.shellConfig || {})
    }

    function summon(id: string, payloadJson: string): string {
      return shell.summon(id, payloadJson) ? "ok" : "unknown"
    }

    function hide(id: string): void {
      shell.hide(id)
    }

    function toggle(id: string, payloadJson: string): void {
      shell.toggle(id, payloadJson)
    }
  }
}
