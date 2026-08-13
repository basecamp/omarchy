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
  property AppLibrary appLibrary: AppLibrary { }

  property string home: Quickshell.env("HOME")

  // The omarchy-shell host is the long-running entry point. Plugins live in
  // sibling directories under plugins/. OMARCHY_PATH is provided by the uwsm
  // session environment and is the single source of truth for this checkout.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string shellPath: omarchyPath + "/shell"
  readonly property string firstPartyPluginsDir: shellPath + "/plugins"
  readonly property string defaultsPath: omarchyPath + "/config/omarchy/shell.json"
  readonly property string userConfigPath: home + "/.config/omarchy/shell.json"

  // Bundled fallback so the shell can start even when the default shell.json is
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
      centerAnchor: "omarchy.clock",
      layout: {
        left: [{ id: "omarchy.menu" }, { id: "omarchy.workspaces" }],
        center: [{ id: "omarchy.clock", format: "dddd HH:mm" }],
        right: [{ id: "omarchy.audio" }]
      }
    },
    plugins: []
  })

  property var defaultsConfig: builtinShellConfig
  property var shellConfig: builtinShellConfig
  property bool fullPluginReloading: false
  property bool fullPluginReloadPending: false
  property var activePluginReloads: ({})
  property var pendingLocalPluginReloads: ({})
  property bool pendingLocalPluginFullReload: false
  property var pluginSourceRevisions: ({})
  property var preparedPluginSourceRevisions: ({})
  property int pluginSourceRevisionCounter: 0
  readonly property string pluginReloadSession: String(Date.now()) + "-"
    + String(Math.floor(Math.random() * 1000000))
  readonly property string pluginReloadSourceRoot: Quickshell.env("XDG_RUNTIME_DIR")
    + "/omarchy-shell/plugin-reloads/" + pluginReloadSession
  readonly property bool pluginReloading: fullPluginReloading || Object.keys(activePluginReloads).length > 0

  Timer {
    id: localPluginReloadTimer
    interval: 150
    onTriggered: shell.reloadLocalPlugins()
  }

  Process {
    id: pluginSourceRevisionProcess
    onExited: function(exitCode) { shell.finishPluginSourceRevisionPreparation(exitCode) }
  }

  onShellConfigChanged: {
    if (failedBarId !== "") failedBarId = ""
    pluginRegistry.registryRevision++
    pluginRegistry.pluginsChanged()
  }

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
      console.warn("default shell.json parse failed, using builtin:", e)
      defaultsConfig = builtinShellConfig
    }
    applyShellConfig()
  }

  function persistShellConfig(nextConfig) {
    var payload = JSON.parse(JSON.stringify(nextConfig))
    payload.version = 1
    shellConfig = payload
    userConfigFile.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  readonly property var barConfig: shellConfig && Util.isPlainObject(shellConfig.bar) ? shellConfig.bar : builtinShellConfig.bar
  onBarConfigChanged: if (bar && "barConfig" in bar) bar.barConfig = shell.barConfig
  FileView {
    id: defaultsFile
    path: shell.defaultsPath
    watchChanges: true
    printErrors: false
    onLoaded: shell.loadDefaults(text())
    onLoadFailed: function(error) {
      console.warn("default shell.json load failed: " + error + " path=" + shell.defaultsPath)
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
    onLoaded: shell.applyShellConfig()
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
  // can read barSize/barHidden/position to anchor relative to the active bar.
  readonly property string defaultBarId: "omarchy.bar"
  readonly property string selectedBarId: {
    var config = shell.barConfig
    if (Util.isPlainObject(config)) {
      var configured = Util.canonicalWidgetId(String(config.id || ""))
      if (configured) return configured
    }
    return shell.defaultBarId
  }
  property string failedBarId: ""
  readonly property bool selectedBarAvailable: {
    var revision = shell.pluginRegistry.registryRevision
    return shell.barOptionAvailable(shell.selectedBarId)
  }
  readonly property string activeBarId: selectedBarId !== failedBarId && selectedBarAvailable ? selectedBarId : defaultBarId
  readonly property var activeBarManifest: {
    var revision = shell.pluginRegistry.registryRevision
    return shell.barManifestFor(shell.activeBarId)
  }
  readonly property string activeBarSourceUrl: activeBarId === defaultBarId ? "" : shell.pluginEntryPointUrl(activeBarManifest, "bar")
  property var bar: null

  onSelectedBarIdChanged: if (failedBarId !== "") failedBarId = ""

  function barManifestFor(pluginId) {
    var plugins = shell.pluginRegistry ? shell.pluginRegistry.installedPlugins : null
    return plugins ? plugins[String(pluginId || "")] || null : null
  }

  function pluginEntryPointUrl(manifest, kind) {
    if (!manifest) return ""
    var sourceDir = String(manifest.__sourceDir || "")
    var revision = shell.pluginSourceRevisions[String(manifest.id || "")] || 0
    if (revision > 0) {
      // A revisioned base URL also changes cache keys for relative QML and JS.
      var pluginsDir = shell.pluginRegistry.pluginsDir.replace(/\/$/, "")
      var expectedPrefix = pluginsDir + "/"
      if (sourceDir.indexOf(expectedPrefix) === 0) {
        sourceDir = shell.pluginReloadSourceRoot + "/" + revision + "/plugins/"
          + sourceDir.slice(expectedPrefix.length)
      }
    }
    return shell.pluginRegistry.entryPointUrl(manifest, kind, sourceDir)
  }

  function isBarOptionManifest(manifest) {
    return manifest
      && Array.isArray(manifest.kinds)
      && manifest.kinds.indexOf("bar") !== -1
      && manifest.entryPoints
      && manifest.entryPoints.bar
  }

  function barOptionAvailable(pluginId) {
    var id = String(pluginId || "")
    if (id === "" || id === shell.defaultBarId) return true
    var manifest = shell.barManifestFor(id)
    return shell.isBarOptionManifest(manifest) && shell.pluginRegistry.entryPointUrl(manifest, "bar") !== ""
  }

  function isActiveBarOption(pluginId) {
    return String(pluginId || "") === shell.activeBarId
  }

  function configureBar(target, manifest) {
    if (!target) return
    if ("omarchyPath" in target) target.omarchyPath = shell.omarchyPath
    if ("shell" in target) target.shell = shell
    if ("manifest" in target) target.manifest = manifest
    if ("barWidgetRegistry" in target) target.barWidgetRegistry = shell.barWidgetRegistry
    if ("pluginRegistry" in target) target.pluginRegistry = shell.pluginRegistry
    if ("barConfig" in target) target.barConfig = shell.barConfig
    shell.bar = target
  }

  Component {
    id: defaultBarComponent

    Bar {
      omarchyPath: shell.omarchyPath
      barWidgetRegistry: shell.barWidgetRegistry
      barConfig: shell.barConfig
      shell: shell
      manifest: shell.barManifestFor(shell.defaultBarId)
    }
  }

  Loader {
    id: defaultBarLoader

    active: shell.activeBarId === shell.defaultBarId
    sourceComponent: defaultBarComponent
    onLoaded: shell.configureBar(item, shell.barManifestFor(shell.defaultBarId))
    onActiveChanged: if (!active && shell.activeBarId !== shell.defaultBarId) shell.bar = null
  }

  Loader {
    id: pluginBarLoader

    active: !shell.pluginReloadAffects(shell.activeBarId)
      && shell.activeBarId !== shell.defaultBarId
      && shell.activeBarSourceUrl !== ""
    source: shell.activeBarId !== shell.defaultBarId ? shell.activeBarSourceUrl : ""
    asynchronous: true
    onLoaded: shell.configureBar(item, shell.activeBarManifest)
    onActiveChanged: if (!active) shell.bar = null
    onStatusChanged: {
      if (status === Loader.Error) {
        var detail = errorString && errorString() ? errorString() : ""
        console.warn("bar option " + shell.activeBarId + " failed to load, falling back to " + shell.defaultBarId + ":", detail)
        shell.failedBarId = shell.activeBarId
      }
    }
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
  property int pluginServiceLoadRevision: 0
  property var pluginServiceLoadRevisions: ({})

  function serviceFor(pluginId) {
    return _services[String(pluginId)] || null
  }

  function firstPartyServiceFor(pluginId) {
    return serviceFor(pluginId)
  }

  function advancePluginServiceLoad(pluginId) {
    var key = String(pluginId || "")
    if (!key) return 0
    pluginServiceLoadRevision++
    var next = ({})
    for (var id in pluginServiceLoadRevisions) next[id] = pluginServiceLoadRevisions[id]
    next[key] = pluginServiceLoadRevision
    pluginServiceLoadRevisions = next
    return pluginServiceLoadRevision
  }

  function ensureService(pluginId) {
    var key = String(pluginId)
    if (_services[key]) return _services[key]
    var manifest = pluginRegistry && pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins[key] : null
    if (!manifest) return null
    if (!Array.isArray(manifest.kinds) || manifest.kinds.indexOf("service") === -1) return null
    if (!manifest.entryPoints || !manifest.entryPoints.service) return null
    var url = shell.pluginEntryPointUrl(manifest, "service")
    if (!url) return null

    var loadRevision = shell.advancePluginServiceLoad(key)
    var comp = Qt.createComponent(url, Component.PreferSynchronous)
    function finalize() {
      if (shell.pluginServiceLoadRevisions[key] !== loadRevision) return
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

  function unloadPluginService(pluginId) {
    var key = String(pluginId || "")
    shell.advancePluginServiceLoad(key)
    var inst = _services[key]
    if (!inst) return
    if (typeof inst.destroy === "function") inst.destroy()
    var next = ({})
    for (var existingId in _services) if (existingId !== key) next[existingId] = _services[existingId]
    _services = next
  }

  function unloadPluginServices() {
    pluginServiceLoadRevisions = ({})
    for (var existingId in _services) {
      var inst = _services[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
    }
    _services = ({})
  }

  Connections {
    target: shell.pluginRegistry
    function onPluginsChanged() { if (!shell.pluginReloading) shell._syncServices() }
  }

  // Writes inline settings to a bar layout entry or top-level plugin entry in
  // shell.json. moduleName is the entry id; settings is the merged plugin
  // state. Returns true if anything actually changed. Compute the proposed
  // new shellConfig in a local clone, and only persist if anything actually
  // changed so reactive bindings do not dirty shell.json unnecessarily.
  function updateEntryInline(moduleName, settings) {
    var stripped = Util.canonicalWidgetId(moduleName)
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
        if (arr[i] && Util.canonicalWidgetId(arr[i].id) === stripped) {
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

  // Bar-widget panels (audio, bluetooth, network, power, monitor, etc.)
  // are mounted inside the bar, not via the panel loader below. Route
  // summon/hide/toggle to the live bar instance so panel hotkeys survive
  // plugin/bar reloads: the bar re-creates the widget, while a fixed IPC
  // target only ever routes to one of the per-monitor instances.
  function isBarWidgetPanelPlugin(pluginId) {
    var plugins = shell.pluginRegistry.installedPlugins
    var m = plugins[String(pluginId || "")]
    if (!m || !Array.isArray(m.kinds)) return false
    if (m.kinds.indexOf("bar-widget") === -1) return false
    // Plugins that are also panel/overlay/menu kinds are owned by the
    // panel loader (e.g. omarchy.menu); let that path handle them.
    var loaderKinds = ["panel", "overlay", "menu"]
    for (var i = 0; i < loaderKinds.length; i++) {
      if (m.kinds.indexOf(loaderKinds[i]) !== -1) return false
    }
    return true
  }

  function summon(pluginId, payloadJson) {
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
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
    // Bar widgets take no payload; payloadJson is dropped on this path.
    if (shell.isBarWidgetPanelPlugin(id)) {
      var summoned = shell.bar && typeof shell.bar.summonBarWidget === "function"
        && shell.bar.summonBarWidget(id)
      if (!summoned) console.warn("summon: no live bar widget for:", id)
      return summoned === true
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
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
    if (!id) return false
    if (shell.isBarWidgetPanelPlugin(id)) {
      var hidden = shell.bar && typeof shell.bar.hideBarWidget === "function"
        && shell.bar.hideBarWidget(id)
      if (!hidden) console.warn("hide: no live bar widget for:", id)
      return hidden === true
    }
    invokeIfLoaded(id, "close", null)
    if (!openPanelIds[id]) return true
    var next = ({})
    for (var k in openPanelIds) if (k !== id) next[k] = openPanelIds[k]
    openPanelIds = next
    return true
  }

  function isPluginOpen(pluginId) {
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
    if (shell.isBarWidgetPanelPlugin(id)) {
      return shell.bar && typeof shell.bar.isBarWidgetOpen === "function"
        ? shell.bar.isBarWidgetOpen(id)
        : false
    }
    var loader = panelLoaders[id]
    if (loader && loader.item && loader.item.opened !== undefined)
      return loader.item.opened === true
    return openPanelIds[id] === true
  }

  function toggle(pluginId, payloadJson) {
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
    return isPluginOpen(id) ? hide(id) : summon(id, payloadJson)
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

  function preparePanelReload(pluginId) {
    var key = String(pluginId || "")
    if (!key || shell.isBarWidgetPanelPlugin(key) || !shell.isPluginOpen(key)) return
    shell.invokeIfLoaded(key, "close", null)

    var next = ({})
    for (var id in pendingPayloads) next[id] = pendingPayloads[id].slice()
    var queue = next[key] || []
    if (queue.length === 0) queue.push("")
    next[key] = queue
    pendingPayloads = next
  }

  function unloadPanels() {
    for (var id in panelLoaders) hide(id)
    panelEntries = []
    panelLoaders = ({})
    pendingPayloads = ({})
    openPanelIds = ({})
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

  function callIfLoaded(pluginId, method, arg) {
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
    var loader = panelLoaders[id]
    if (!loader || !loader.item) return "unknown"
    if (typeof loader.item[method] !== "function") return "unknown"
    try {
      var result = loader.item[method](arg)
      return result === undefined || result === null ? "ok" : String(result)
    } catch (e) {
      console.warn("plugin " + id + " " + method + "() threw:", e)
      return "error"
    }
  }

  // One Loader per discoverable panel/overlay/menu plugin. Active when the
  // host marks it open. The Loader holds onto the instance while active so the
  // plugin's FloatingWindow + state survive between summons within a session.
  property var panelEntries: []

  function panelKindForManifest(manifest) {
    if (!manifest || !Array.isArray(manifest.kinds)) return ""
    if (manifest.kinds.indexOf("panel") !== -1) return "panel"
    if (manifest.kinds.indexOf("overlay") !== -1) return "overlay"
    if (manifest.kinds.indexOf("menu") !== -1) return "menu"
    return ""
  }

  function panelEntryFor(pluginId) {
    var id = String(pluginId || "")
    var manifest = shell.pluginRegistry.installedPlugins[id]
    if (!shell.panelKindForManifest(manifest) || !shell.pluginRegistry.isEnabled(id)) return null
    return { id: id }
  }

  function computePanelEntries() {
    var out = []
    var plugins = shell.pluginRegistry.installedPlugins
    for (var id in plugins) {
      var entry = shell.panelEntryFor(id)
      if (entry) out.push(entry)
    }
    return out
  }

  function syncReloadedPanelEntries(reloadIds) {
    var next = panelEntries.slice()
    var changed = false
    for (var id in reloadIds) {
      var index = -1
      for (var i = 0; i < next.length; i++) {
        if (next[i].id === id) {
          index = i
          break
        }
      }

      var entry = shell.panelEntryFor(id)
      if (index === -1 && entry) {
        next.push(entry)
        changed = true
      } else if (index !== -1 && !entry) {
        next.splice(index, 1)
        changed = true
      }
    }
    if (changed) panelEntries = next
  }

  Connections {
    target: shell.pluginRegistry
    function onPluginsChanged() { if (!shell.pluginReloading) shell.panelEntries = shell.computePanelEntries() }
  }

  Instantiator {
    model: shell.panelEntries
    active: true

    delegate: QtObject {
      id: panelEntry
      required property var modelData
      readonly property string pluginId: modelData.id
      readonly property var manifest: shell.pluginRegistry.installedPlugins[pluginId] || null
      readonly property string entryKind: shell.panelKindForManifest(manifest)
      readonly property bool keepLoaded: manifest ? manifest.keepLoaded === true : false
      readonly property string sourceUrl: shell.pluginEntryPointUrl(manifest, entryKind)

      property Loader panelLoader: Loader {
        source: panelEntry.sourceUrl
        active: !shell.pluginReloadAffects(panelEntry.pluginId)
          && panelEntry.sourceUrl !== ""
          && (panelEntry.keepLoaded || shell.openPanelIds[panelEntry.pluginId] === true)
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
  // its manifest entry point and registered under its manifest id. Built-in
  // widgets use the same first-party manifest contract as third-party widgets.
  Connections {
    target: shell.pluginRegistry
    function onPluginsChanged() { if (!shell.pluginReloading) shell.syncPluginWidgets() }
  }

  property var pluginWidgetComponents: ({})
  property int pluginWidgetLoadRevision: 0

  function syncPluginWidgets(reloadIds) {
    var plugins = shell.pluginRegistry.installedPlugins
    var seen = ({})
    var targeted = reloadIds && Object.keys(reloadIds).length > 0

    for (var pluginId in plugins) {
      var manifest = plugins[pluginId]
      if (!manifest || !manifest.kinds || manifest.kinds.indexOf("bar-widget") === -1) continue
      if (!shell.pluginRegistry.isEnabled(pluginId)) continue

      var registryKey = String(manifest.id)
      seen[registryKey] = true
      if (targeted && reloadIds[registryKey] !== true) continue

      // Already loaded with matching source — leave it alone.
      var existing = pluginWidgetComponents[registryKey]
      var url = shell.pluginEntryPointUrl(manifest, "barWidget")
      if (!url) {
        console.warn("Plugin " + manifest.id + " has no barWidget entry point")
        continue
      }
      var meta = manifest.barWidget || {}
      meta = {
        displayName: meta.displayName || manifest.name,
        description: meta.description || manifest.description,
        category: meta.category || "Plugin",
        allowMultiple: meta.allowMultiple === true,
        defaults: meta.defaults || {},
        settingsForm: meta.settingsForm || "",
        schema: meta.schema || [],
        pluginId: manifest.id,
        sourceDir: manifest.__sourceDir || "",
        source: "plugin"
      }

      // A load already in flight for this URL registers itself when it
      // finishes. Starting a second one produces a second Component for the
      // same widget, and swapping a slot's component rebuilds its item —
      // briefly running two of the widget, each registering its IPC handler.
      if (existing && existing.url === url && !existing.component) continue

      // If the component URL is unchanged, just refresh the metadata in
      // place. We can't skip this even when the URL matches: manifests can
      // change schema, defaults, or sourceDir between rescans, and the
      // settings panel reads metadata from the registry.
      if (existing && existing.url === url && shell.barWidgetRegistry.has(registryKey)) {
        shell.barWidgetRegistry.register(registryKey, existing.component, meta)
        continue
      }

      loadPluginWidget(registryKey, url, meta)
    }

    // Drop registrations for plugins that are no longer present or enabled.
    var allIds = shell.barWidgetRegistry.availableIds()
    for (var i = 0; i < allIds.length; i++) {
      var id = allIds[i]
      if (targeted && reloadIds[id] !== true) continue
      if (!pluginWidgetComponents[id]) continue
      if (!seen[id]) {
        shell.barWidgetRegistry.unregister(id)
        var next = ({})
        for (var k in pluginWidgetComponents) if (k !== id) next[k] = pluginWidgetComponents[k]
        pluginWidgetComponents = next
      }
    }
  }

  function unloadPluginWidget(pluginId) {
    var key = String(pluginId || "")
    shell.barWidgetRegistry.unregister(key)
    shell.setPluginWidgetComponent(key, null)
  }

  function unloadPluginWidgets() {
    for (var id in pluginWidgetComponents) shell.barWidgetRegistry.unregister(id)
    pluginWidgetComponents = ({})
  }

  function hasPluginReloads(reloads) {
    return reloads && Object.keys(reloads).length > 0
  }

  function mergePluginReloads(current, additions) {
    var next = ({})
    for (var id in current) next[id] = true
    for (var addedId in additions) next[addedId] = true
    return next
  }

  function preparePluginSourceRevision(reloads) {
    pluginSourceRevisionCounter++
    var next = ({})
    for (var id in pluginSourceRevisions) next[id] = pluginSourceRevisions[id]
    for (var reloadId in reloads) next[reloadId] = pluginSourceRevisionCounter
    preparedPluginSourceRevisions = next

    var script = "mkdir -p -- \"$0/$2\" && ln -s -- \"$1\" \"$0/$2/plugins\""
    pluginSourceRevisionProcess.command = [
      "bash", "-c", script,
      pluginReloadSourceRoot,
      pluginRegistry.pluginsDir,
      String(pluginSourceRevisionCounter)
    ]
    pluginSourceRevisionProcess.running = true
  }

  function finishPluginSourceRevisionPreparation(exitCode) {
    if (exitCode === 0) {
      pluginSourceRevisions = preparedPluginSourceRevisions
      preparedPluginSourceRevisions = ({})
      Qt.callLater(shell.finishPluginReload)
      return
    }

    console.warn("Could not prepare versioned plugin sources; falling back to a full plugin reload")
    preparedPluginSourceRevisions = ({})
    activePluginReloads = ({})
    fullPluginReloading = true
    shell.unloadPanels()
    shell.unloadPluginServices()
    shell.unloadPluginWidgets()
    Qt.callLater(shell.finishPluginReload)
  }

  function pluginReloadAffects(pluginId) {
    return shell.fullPluginReloading || shell.activePluginReloads[String(pluginId || "")] === true
  }

  function queueLocalPluginReload(sourceDir) {
    var pluginId = shell.pluginRegistry.pluginIdForSourceDir(sourceDir)
    if (!pluginId) {
      // A directory the registry does not know yet — a new plugin still being
      // written, or a stray file at the plugins root — needs a full reload to
      // discover it. Still route it through the debounce timer: a burst of
      // file events (git clone, an editor saving many files) must coalesce
      // into one reload instead of tearing the shell down once per event.
      pendingLocalPluginFullReload = true
    } else {
      var reload = ({})
      reload[pluginId] = true
      pendingLocalPluginReloads = shell.mergePluginReloads(pendingLocalPluginReloads, reload)
    }
    localPluginReloadTimer.restart()
  }

  function reloadLocalPlugins() {
    if (shell.pendingLocalPluginFullReload) {
      shell.pendingLocalPluginFullReload = false
      shell.reloadPlugins()
      return
    }
    if (!shell.hasPluginReloads(shell.pendingLocalPluginReloads)) return
    if (shell.pluginReloading || shell.pluginRegistry.scanning) return

    var reloads = shell.pendingLocalPluginReloads
    pendingLocalPluginReloads = ({})
    for (var id in reloads) shell.preparePanelReload(id)

    // Keep every unrelated service, panel, bar, and widget mounted while the
    // registry rescans.
    activePluginReloads = reloads
    for (var pluginId in reloads) {
      shell.unloadPluginService(pluginId)
      shell.unloadPluginWidget(pluginId)
    }
    shell.preparePluginSourceRevision(reloads)
  }

  function reloadPlugins() {
    if (shell.pluginReloading || shell.pluginRegistry.scanning) {
      shell.fullPluginReloadPending = true
      return
    }
    pendingLocalPluginReloads = ({})
    pendingLocalPluginFullReload = false
    activePluginReloads = ({})
    fullPluginReloading = true
    shell.unloadPanels()
    shell.unloadPluginServices()
    shell.unloadPluginWidgets()
    Qt.callLater(shell.finishPluginReload)
  }

  function finishPluginReload() {
    if (!shell.pluginReloading) return
    if (shell.pluginRegistry.scanning) {
      if (shell.fullPluginReloading) {
        shell.fullPluginReloadPending = true
      } else {
        shell.pendingLocalPluginReloads = shell.mergePluginReloads(
          shell.pendingLocalPluginReloads, shell.activePluginReloads)
      }
      shell.fullPluginReloading = false
      shell.activePluginReloads = ({})
      return
    }
    if (shell.fullPluginReloading && typeof Qt.clearComponentCache === "function")
      Qt.clearComponentCache()
    shell.pluginRegistry.rescan()
  }

  Connections {
    target: shell.pluginRegistry
    function onLocalPluginChanged(sourceDir) {
      console.log("Local plugin changed, reloading:", sourceDir)
      shell.queueLocalPluginReload(sourceDir)
    }
    function onScanFinished() {
      if (shell.fullPluginReloadPending) {
        shell.fullPluginReloadPending = false
        shell.fullPluginReloading = false
        shell.activePluginReloads = ({})
        shell.pendingLocalPluginReloads = ({})
        shell.pendingLocalPluginFullReload = false
        Qt.callLater(shell.reloadPlugins)
        return
      }

      var fullReload = shell.fullPluginReloading
      var reloads = shell.activePluginReloads
      shell._syncServices()
      if (fullReload || !shell.hasPluginReloads(reloads)) {
        shell.panelEntries = shell.computePanelEntries()
        shell.syncPluginWidgets()
      } else {
        shell.syncReloadedPanelEntries(reloads)
        shell.syncPluginWidgets(reloads)
      }
      shell.fullPluginReloading = false
      shell.activePluginReloads = ({})
      if (shell.hasPluginReloads(shell.pendingLocalPluginReloads) || shell.pendingLocalPluginFullReload)
        Qt.callLater(shell.reloadLocalPlugins)
    }
  }

  function setPluginWidgetComponent(registryKey, entry) {
    var next = ({})
    for (var k in pluginWidgetComponents) if (k !== registryKey) next[k] = pluginWidgetComponents[k]
    if (entry) next[registryKey] = entry
    pluginWidgetComponents = next
  }

  function loadPluginWidget(registryKey, url, meta) {
    // Claim the key before the component exists. The revision also prevents a
    // canceled asynchronous load from registering after a targeted reload.
    pluginWidgetLoadRevision++
    var loadRevision = pluginWidgetLoadRevision
    setPluginWidgetComponent(registryKey, {
      url: url,
      component: null,
      loadRevision: loadRevision
    })

    var comp = Qt.createComponent(url, Component.Asynchronous)
    function finalize() {
      var pending = shell.pluginWidgetComponents[registryKey]
      if (!pending || pending.loadRevision !== loadRevision) return
      if (comp.status === Component.Ready) {
        shell.barWidgetRegistry.register(registryKey, comp, meta)
        shell.setPluginWidgetComponent(registryKey, {
          url: url,
          component: comp,
          loadRevision: loadRevision
        })
      } else if (comp.status === Component.Error) {
        console.warn("Plugin widget " + registryKey + " failed: " + comp.errorString())
        // Drop the claim so a later rescan can retry.
        shell.setPluginWidgetComponent(registryKey, null)
        shell.pluginRegistry.pluginLoadFailed(registryKey, comp.errorString())
      }
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
    } else {
      finalize()
    }
  }

  // --------------------------------------------------- image selector IPC

  function imagePickerItem() {
    var loader = panelLoaders["omarchy.image-picker"]
    return loader && loader.item ? loader.item : null
  }

  IpcHandler {
    target: "image-selector"

    function open(imageDirs: string,
                  imageRowsB64: string,
                  selectedImage: string,
                  selectionFile: string,
                  doneFile: string,
                  showLabels: string,
                  filterable: string): string {
      var payload = JSON.stringify({
        imageDirs: imageDirs,
        imageRows: Util.decodeBase64(imageRowsB64),
        selectedImage: selectedImage,
        selectionFile: selectionFile,
        doneFile: doneFile,
        showLabels: showLabels,
        filterable: filterable
      })
      return shell.summon("omarchy.image-picker", payload) ? "ok" : "unknown"
    }

    function preload(imageRowsB64: string,
                     selectedImage: string,
                     showLabels: string,
                     filterable: string): string {
      var picker = shell.imagePickerItem()
      if (picker && typeof picker.preloadRows === "function") {
        picker.preloadRows(Util.decodeBase64(imageRowsB64), selectedImage,
                           showLabels, filterable)
      }
      return "ok"
    }

    function cancel(doneFile: string): string {
      var picker = shell.imagePickerItem()
      if (picker && typeof picker.closeSelector === "function") {
        picker.closeSelector(doneFile || "")
      } else {
        shell.hide("omarchy.image-picker")
      }
      return "ok"
    }

    function ping(): string {
      return "ok"
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
      shell.reloadPlugins()
    }

    function reloadConfig(): string {
      userConfigFile.reload()
      return "ok"
    }

    function toggleBarTransparency(): string {
      if (shell.bar && typeof shell.bar.toggleTransparency === "function") {
        shell.bar.toggleTransparency()
        return "ok"
      }
      return "no-bar"
    }

    function setPluginEnabled(id: string, enabled: string): string {
      return shell.pluginRegistry.setEnabled(id, enabled === "true") ? "ok" : "unknown"
    }

    function enablePlugin(id: string, placementJson: string): string {
      try {
        var placement = JSON.parse(placementJson || "{}")
        if (shell.pluginRegistry.setEnabled(id, true, placement)) return "ok"
        return shell.pluginRegistry.lastEnableError || "unknown"
      } catch (e) {
        return "invalid placement: " + e
      }
    }

    // Enable, but only where the widget is not on the bar already, so a caller
    // that cannot know whether it ran before leaves a placed widget alone.
    function putBarWidget(id: string, placementJson: string): string {
      try {
        var error = shell.pluginRegistry.putBarWidget(id, JSON.parse(placementJson || "{}"))
        return error ? error : "ok"
      } catch (e) {
        return "invalid placement: " + e
      }
    }

    function moveBarWidget(id: string, placementJson: string): string {
      try {
        var error = shell.pluginRegistry.moveBarWidget(id, JSON.parse(placementJson || "{}"))
        return error ? error : "ok"
      } catch (e) {
        return "invalid placement: " + e
      }
    }

    function setBarWidget(id: string, key: string, valueJson: string, selectorJson: string): string {
      try {
        var value = JSON.parse(valueJson)
        var selector = JSON.parse(selectorJson || "{}")
        var error = shell.pluginRegistry.setBarWidget(id, key, value, selector)
        return error ? error : "ok"
      } catch (e) {
        return "invalid widget setting: " + e
      }
    }

    function listPlugins(): string {
      var out = []
      var plugins = shell.pluginRegistry.installedPlugins
      for (var id in plugins) {
        var kinds = plugins[id].kinds || []
        var isBarOption = Array.isArray(kinds) && kinds.indexOf("bar") !== -1
        var isBarWidget = Array.isArray(kinds) && kinds.indexOf("bar-widget") !== -1
        var active = isBarOption && shell.isActiveBarOption(id)
        var metadata = plugins[id].omarchy
        var clonedFrom = Util.isPlainObject(metadata) ? String(metadata.clonedFrom || "") : ""
        out.push({
          id: id,
          name: plugins[id].name,
          kinds: kinds,
          // What `omarchy plugin enable/disable` toggles: for a widget that is
          // its place in the bar, not whether its component is loadable.
          enabled: isBarOption ? active
            : (isBarWidget ? shell.pluginRegistry.inBar(id) : shell.pluginRegistry.isEnabled(id)),
          active: active,
          // A bar has no off, only a successor: you leave one by enabling
          // another, so there is nothing for disable to do to it. Said here so
          // that a caller offering the verbs does not have to read kinds and
          // work it out again.
          canDisable: !isBarOption,
          firstParty: !!plugins[id].__isFirstParty,
          clonedFrom: clonedFrom
        })
      }
      // Consumers should not each invent their own presentation order.
      out.sort(function(left, right) {
        var leftName = String(left.name || left.id)
        var rightName = String(right.name || right.id)
        if (leftName < rightName) return -1
        if (leftName > rightName) return 1
        return String(left.id).localeCompare(String(right.id))
      })
      return JSON.stringify(out)
    }

    // Returns the effective shell.json content as JSON. Useful for debugging
    // and for CLI tools that want to inspect the merged state without
    // re-implementing the load logic.
    function listShellConfig(): string {
      return JSON.stringify(shell.shellConfig || {})
    }

    function debugBarGeometry(): string {
      return JSON.stringify(shell.bar && shell.bar.debugBarGeometry ? shell.bar.debugBarGeometry() : [])
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

    // A bar section's panels answer to their position as well as their id, so a
    // hotkey can mean "the third panel in the right section" and keep meaning
    // it after the bar is rearranged. Returns the id it acted on, or "unknown"
    // when the section holds no panel at that position.
    function togglePanelAt(section: string, index: string): string {
      var id = shell.bar && typeof shell.bar.panelWidgetIdAt === "function"
        ? shell.bar.panelWidgetIdAt(section, index)
        : ""
      if (!id) return "unknown"
      shell.toggle(id, "{}")
      return id
    }

    function call(id: string, method: string, arg: string): string {
      return shell.callIfLoaded(id, method, arg)
    }
  }
}
