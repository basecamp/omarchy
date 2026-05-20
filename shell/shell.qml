import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io

import qs.Commons

import "plugins/bar"
import "services"

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
  // sibling directories under plugins/. OMARCHY_PATH is provided by the uwsm
  // session environment and is the single source of truth for this checkout.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string shellPath: omarchyPath + "/shell"
  readonly property string firstPartyPluginsDir: shellPath + "/plugins"
  readonly property string defaultsPath: shellPath + "/shell-defaults.json"
  readonly property string userConfigPath: home + "/.config/omarchy/shell.json"

  // Bundled fallback so the shell can start even when shell-defaults.json is
  // missing or unreadable. The bar config here mirrors the on-disk defaults
  // closely enough to render a usable bar; not authoritative.
  readonly property var builtinShellConfig: ({
    version: 1,
    idle: {
      screensaver: 150,
      lock: 300
    },
    bar: {
      position: "top",
      transparent: false,
      centerAnchor: "calendar",
      layout: {
        left: [{ id: "omarchy" }, { id: "workspaces" }],
        center: [{ id: "calendar", format: "dddd HH:mm" }],
        right: [{ id: "audioPanel" }]
      }
    },
    plugins: []
  })

  property var defaultsConfig: builtinShellConfig
  property var shellConfig: builtinShellConfig
  property bool suppressUserReload: false

  function applyShellConfig() {
    // Decide which source is canonical: a valid user shell.json overrides
    // defaults entirely; otherwise fall back to defaults. We do not deep-merge.
    var defaults = Util.isPlainObject(defaultsConfig) ? defaultsConfig : builtinShellConfig
    var user = null
    var userText = userConfigFile.text() || ""
    if (userText.trim()) {
      try {
        var parsed = JSON.parse(userText)
        if (Util.isPlainObject(parsed) && parsed.version === 1) user = parsed
        else if (Util.isPlainObject(parsed)) console.warn("shell.json missing version: 1, using defaults")
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
      if (Util.isPlainObject(parsed) && parsed.version === 1) defaultsConfig = parsed
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

  readonly property var barConfig: shellConfig && Util.isPlainObject(shellConfig.bar) ? shellConfig.bar : builtinShellConfig.bar
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
    shell._syncServices()
  }

  function mutateShellConfig(mutator) {
    var copy = JSON.parse(JSON.stringify(shellConfig || builtinShellConfig))
    mutator(copy)
    persistShellConfig(copy)
  }

  // Exposed as a property so child plugins (notifications, future panels)
  // can read barSize/barHidden/position to anchor relative to the bar.
  property alias bar: bar

  Bar {
    id: bar
    omarchyPath: shell.omarchyPath
    barWidgetRegistry: shell.barWidgetRegistry
    barConfig: shell.barConfig
    shell: shell
  }

  // ------------------------------------------------------------- services
  //
  // Generic loader for any enabled plugin that declares kind "service".
  // First-party infrastructure services are implicitly enabled by the registry;
  // third-party services are enabled by adding the plugin id to shell.json.
  Item {
    id: serviceHost
    visible: false
  }

  property var _services: ({})

  function serviceFor(pluginId) {
    return _services[String(pluginId)] || null
  }

  function firstPartyServiceFor(pluginId) {
    return serviceFor(pluginId)
  }

  function ensureService(pluginId) {
    var key = String(pluginId)
    if (_services[key]) return _services[key]
    var manifest = pluginRegistry && pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins[key] : null
    if (!manifest) return null
    if (!Array.isArray(manifest.kinds) || manifest.kinds.indexOf("service") === -1) return null
    if (!manifest.entryPoints || !manifest.entryPoints.service) return null
    var url = pluginRegistry.entryPointUrl(manifest, "service")
    if (!url) return null

    var comp = Qt.createComponent(url, Component.PreferSynchronous)
    function finalize() {
      if (comp.status !== Component.Ready) {
        console.warn("service plugin load failed for " + key + ": " + comp.errorString())
        return
      }
      var inst = comp.createObject(serviceHost)
      if (!inst) {
        console.warn("service plugin createObject returned null for", key)
        return
      }
      if ("omarchyPath" in inst) inst.omarchyPath = shell.omarchyPath
      if ("shell" in inst) inst.shell = shell
      if ("manifest" in inst) inst.manifest = manifest
      if ("barWidgetRegistry" in inst) inst.barWidgetRegistry = shell.barWidgetRegistry
      if ("pluginRegistry" in inst) inst.pluginRegistry = shell.pluginRegistry
      var snext = ({})
      for (var sk in _services) snext[sk] = _services[sk]
      snext[key] = inst
      _services = snext
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
      return null
    }
    finalize()
    return _services[key] || null
  }

  function _syncServices() {
    if (!pluginRegistry || !pluginRegistry.installedPlugins) return
    var plugins = pluginRegistry.installedPlugins
    for (var id in plugins) {
      var m = plugins[id]
      if (!m) continue
      if (!Array.isArray(m.kinds) || m.kinds.indexOf("service") === -1) continue
      if (!m.entryPoints || !m.entryPoints.service) continue
      if (!pluginRegistry.isEnabled(id)) continue
      if (_services[id]) continue
      ensureService(id)
    }
    // Drop services for plugins that have been disabled or removed.
    for (var existingId in _services) {
      var stillThere = plugins[existingId]
      var stillEnabled = stillThere && pluginRegistry.isEnabled(existingId)
      if (stillThere && stillEnabled) continue
      var inst = _services[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
      var next = ({})
      for (var k in _services) if (k !== existingId) next[k] = _services[k]
      _services = next
    }
  }

  Connections {
    target: shell.pluginRegistry
    function onPluginsChanged() { shell._syncServices() }
  }

  // Writes inline settings to a bar layout entry or top-level plugin entry in
  // shell.json. moduleName is the entry id; settings is the merged plugin
  // state. Returns true if anything actually changed. Compute the proposed
  // new shellConfig in a local clone, and only persist if anything actually
  // changed so reactive bindings do not dirty shell.json unnecessarily.
  function updateEntryInline(moduleName, settings) {
    var stripped = String(moduleName)
    var copy = JSON.parse(JSON.stringify(shellConfig || builtinShellConfig))
    if (!Util.isPlainObject(copy.bar)) copy.bar = { layout: { left: [], center: [], right: [] } }
    if (!Util.isPlainObject(copy.bar.layout)) copy.bar.layout = { left: [], center: [], right: [] }
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
    // A disabled plugin has no Loader, so setting openPanelIds would only
    // produce an invisible "open" state that toggle() then has to unwind.
    // Tell the caller plainly instead of silently no-op'ing.
    if (!shell.pluginRegistry.isEnabled(id)) {
      console.warn("summon: plugin not enabled, not summoning:", id)
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
          // Plugins that pair a panel UI with a service entry read shared
          // state off `service`. Hand them the matching singleton if one was
          // loaded.
          if ("service" in item) item.service = shell.serviceFor(panelEntry.pluginId)
          shell.registerPanelLoader(panelEntry.pluginId, this)
        }
        onStatusChanged: {
          if (status === Loader.Error) {
            // Loader.errorString() reflects the source-load failure even when
            // sourceComponent is null. Surface both so the user sees something
            // actionable instead of a panel that silently refuses to open.
            var detail = errorString && errorString() ? errorString() : ""
            if (!detail && sourceComponent) detail = sourceComponent.errorString()
            console.warn("panel plugin " + panelEntry.pluginId + " failed to load:", detail)
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
  // collide with namespaced plugin ids, so we don't need a separate
  // "plugin:" namespace anymore.
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

    function applyTheme(colorsB64: string, shellB64: string): string {
      var colorsRaw = ""
      var shellRaw = ""
      try { colorsRaw = Qt.atob(String(colorsB64 || "")) } catch (e) { colorsRaw = "" }
      try { shellRaw = Qt.atob(String(shellB64 || "")) } catch (e2) { shellRaw = "" }
      Color.loadColors(colorsRaw)
      Color.loadShell(shellRaw)
      Style.scheduleRefresh()
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
