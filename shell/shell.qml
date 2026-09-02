import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io

import qs.Commons

import "plugins/bar"
import "services"
import "services/AuthServiceStore.js" as AuthServiceStore

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
  property bool pluginReloading: false
  property bool pluginReloadPending: false

  Timer {
    id: localPluginReloadTimer
    interval: 150
    onTriggered: shell.reloadPlugins()
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
  onBarConfigChanged: {
    if (bar && "barConfig" in bar)
      bar.barConfig = shell.barConfigFor(shell.activeBarManifest)
  }
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
  readonly property string activeBarSourceUrl: activeBarId === defaultBarId ? "" : shell.pluginRegistry.entryPointUrl(activeBarManifest, "bar")
  property var bar: null

  onSelectedBarIdChanged: if (failedBarId !== "") failedBarId = ""

  function barManifestFor(pluginId) {
    var plugins = shell.pluginRegistry ? shell.pluginRegistry.installedPlugins : null
    return plugins ? plugins[String(pluginId || "")] || null : null
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
    if ("shell" in target) target.shell = shell.pluginShellFor(manifest)
    if ("manifest" in target) target.manifest = shell.publicPluginManifest(manifest)
    if ("barWidgetRegistry" in target) target.barWidgetRegistry = shell.pluginBarWidgetRegistryFor(manifest)
    if ("pluginRegistry" in target) target.pluginRegistry = shell.pluginRegistryFor(manifest)
    if ("barConfig" in target) target.barConfig = shell.barConfigFor(manifest)
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

    active: !shell.pluginReloading && shell.activeBarId !== shell.defaultBarId && shell.activeBarSourceUrl !== ""
    source: shell.activeBarId !== shell.defaultBarId ? shell.activeBarSourceUrl : ""
    asynchronous: true
    onLoaded: shell.configureBar(item, shell.activeBarManifest)
    onActiveChanged: if (!active) shell.bar = null
    onStatusChanged: {
      if (status === Loader.Error) {
        console.warn("bar option " + shell.activeBarId + " failed to load, falling back to " + shell.defaultBarId)
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
  property var _pluginShellApis: ({})
  property var _pluginShellApiDescriptors: ({})
  property var _pluginBarEntryShellApis: ({})
  property var _pluginRegistryApis: ({})
  property var _pluginBarWidgetRegistryApis: ({})
  property var _pluginAppLibraryApis: ({})
  property var _pluginBarStateApis: ({})
  property var _pluginFirstPartyServiceApis: ({})

  Component {
    id: pluginShellApiComponent
    PluginShellApi { }
  }

  Component {
    id: pluginRegistryApiComponent
    PluginRegistryApi { }
  }

  Component {
    id: pluginBarWidgetRegistryApiComponent
    PluginBarWidgetRegistryApi { }
  }

  Component {
    id: pluginAppLibraryApiComponent
    PluginAppLibraryApi { }
  }

  Component {
    id: pluginBarStateApiComponent
    PluginBarStateApi { }
  }

  Component {
    id: pluginFirstPartyServiceApiComponent
    PluginFirstPartyServiceApi { }
  }

  function publicPluginManifest(manifest) {
    if (!manifest) return null
    if (manifest.__isFirstParty) return manifest
    var copy = JSON.parse(JSON.stringify(manifest))
    delete copy.__sourceDir
    delete copy.__isFirstParty
    delete copy.__hostCapabilities
    return copy
  }

  function publicBarConfig() {
    return JSON.parse(JSON.stringify(shell.barConfig || {}))
  }

  function barConfigFor(manifest) {
    return !manifest || manifest.__isFirstParty
      ? shell.barConfig : shell.publicBarConfig()
  }

  function publicBarWidgetSnapshot() {
    var source = shell.barWidgetRegistry.widgets || {}
    var snapshot = {}
    for (var id in source) {
      var entry = source[id]
      if (!entry) continue
      snapshot[id] = {
        component: entry.component,
        metadata: JSON.parse(JSON.stringify(entry.metadata || {}))
      }
    }
    return snapshot
  }

  function manifestHasKind(manifest, kind) {
    return !!manifest && Array.isArray(manifest.kinds)
      && manifest.kinds.indexOf(kind) !== -1
  }

  function pluginHasBarCapabilities(manifest) {
    return shell.manifestHasKind(manifest, "bar")
  }

  function pluginOwnsTarget(pluginId, requestedId) {
    var caller = String(pluginId || "")
    if (!caller) return false
    return shell.pluginRegistry.resolveEnabledId(String(requestedId || "")) === caller
  }

  function pluginServiceFor(pluginId, requestedId) {
    if (!shell.pluginOwnsTarget(pluginId, requestedId)) return null
    return shell.serviceFor(shell.pluginRegistry.resolveEnabledId(requestedId))
  }

  function barEntryConfigured(pluginId) {
    var location = shell.pluginRegistry.findEntryLocation(shell.shellConfig, pluginId)
    return location && location.kind === "bar"
  }

  function barPluginMayControl(manifest, requestedId) {
    if (!shell.pluginHasBarCapabilities(manifest)) return false
    var id = shell.pluginRegistry.resolveEnabledId(String(requestedId || ""))
    var target = shell.pluginRegistry.installedPlugins[id]
    if (!target || shell.isAuthenticationService(target)) return false
    if (shell.barEntryConfigured(id)) return true
    var uiKinds = ["bar-widget", "panel", "overlay", "menu"]
    for (var i = 0; i < uiKinds.length; i++)
      if (shell.manifestHasKind(target, uiKinds[i])) return true
    return false
  }

  function mutatePluginBarConfig(mutator) {
    if (typeof mutator !== "function") return false
    shell.mutateShellConfig(function(config) {
      var scoped = { bar: JSON.parse(JSON.stringify(config.bar || {})) }
      mutator(scoped)
      if (Util.isPlainObject(scoped.bar)) config.bar = JSON.parse(JSON.stringify(scoped.bar))
    })
    return true
  }

  function pluginAppLibraryFor(cacheKey, pluginId) {
    if (_pluginAppLibraryApis[cacheKey]) return _pluginAppLibraryApis[cacheKey]
    var api = pluginAppLibraryApiComponent.createObject(null, {
      ownerPluginId: pluginId,
      _entryName: function(entry) { return shell.appLibrary.entryName(entry) },
      _entrySubtext: function(entry) { return shell.appLibrary.entrySubtext(entry) },
      _sortedEntries: function(query) { return shell.appLibrary.sortedEntries(query) },
      _iconSource: function(icon) { return shell.appLibrary.iconSource(icon) },
      _refreshIcons: function() { shell.appLibrary.refreshIcons() },
      _launch: function(desktopId, name) { shell.appLibrary.launch(desktopId, name) },
      _remove: function(desktopId, name) { shell.appLibrary.remove(desktopId, name) }
    })
    if (!api) return null
    var next = ({})
    for (var id in _pluginAppLibraryApis) next[id] = _pluginAppLibraryApis[id]
    next[cacheKey] = api
    _pluginAppLibraryApis = next
    return api
  }

  function pluginBarStateFor(cacheKey, pluginId) {
    if (_pluginBarStateApis[cacheKey]) return _pluginBarStateApis[cacheKey]
    var api = pluginBarStateApiComponent.createObject(null, { ownerPluginId: pluginId })
    if (!api) return null
    api.barHidden = Qt.binding(function() { return shell.bar ? shell.bar.barHidden === true : false })
    api.barSize = Qt.binding(function() { return shell.bar ? Math.max(0, shell.bar.barSize || 0) : 0 })
    api.fontFamily = Qt.binding(function() { return shell.bar ? String(shell.bar.fontFamily || "") : "" })
    api.position = Qt.binding(function() { return shell.bar ? String(shell.bar.position || "top") : "top" })
    var next = ({})
    for (var id in _pluginBarStateApis) next[id] = _pluginBarStateApis[id]
    next[cacheKey] = api
    _pluginBarStateApis = next
    return api
  }

  function pluginFirstPartyServiceFor(cacheKey, pluginId, requestedId) {
    var id = String(requestedId || "")
    var allowed = ["omarchy.idle", "omarchy.media", "omarchy.nightlight", "omarchy.notifications"]
    if (allowed.indexOf(id) === -1) return null
    var proxyKey = cacheKey + "::" + id
    if (_pluginFirstPartyServiceApis[proxyKey]) return _pluginFirstPartyServiceApis[proxyKey]

    function service() {
      return shell.serviceFor(shell.pluginRegistry.resolveEnabledId(id))
    }
    var api = pluginFirstPartyServiceApiComponent.createObject(null, {
      ownerPluginId: pluginId,
      serviceId: id,
      _setIdleEnabled: function(value) {
        var target = service()
        if (target && typeof target.setIdleEnabled === "function") target.setIdleEnabled(value)
      },
      _setNightlight: function(value) {
        var target = service()
        if (target && typeof target.setNightlight === "function") target.setNightlight(value)
      },
      _setDoNotDisturb: function(value) {
        var target = service()
        if (target && typeof target.setDoNotDisturb === "function") target.setDoNotDisturb(value)
      },
      _runAction: function(action, showFeedback, targetKey) {
        var target = service()
        if (target && typeof target.runAction === "function") target.runAction(action, showFeedback, targetKey)
      },
      _playerKey: function(player) {
        var target = service()
        return target && typeof target.playerKey === "function" ? target.playerKey(player) : ""
      },
      _selectPlayer: function(playerKey) {
        var target = service()
        if (target && typeof target.selectPlayer === "function") target.selectPlayer(playerKey)
      }
    })
    if (!api) return null
    api.stayAwake = Qt.binding(function() {
      var target = service()
      return target ? target.stayAwake === true : false
    })
    api.enabled = Qt.binding(function() {
      var target = service()
      return target ? target.enabled === true : false
    })
    api.doNotDisturb = Qt.binding(function() {
      var target = service()
      return target ? target.doNotDisturb === true : false
    })
    api.activePlayer = Qt.binding(function() {
      var target = service()
      return target ? target.activePlayer : null
    })
    api.sourcePlayers = Qt.binding(function() {
      var target = service()
      return target && Array.isArray(target.sourcePlayers) ? target.sourcePlayers : []
    })
    var next = ({})
    for (var existing in _pluginFirstPartyServiceApis) next[existing] = _pluginFirstPartyServiceApis[existing]
    next[proxyKey] = api
    _pluginFirstPartyServiceApis = next
    return api
  }

  function pluginShellCapabilityProfile(manifest, allowOwnService, barCapabilities) {
    return [
      allowOwnService ? "own-service" : "no-own-service",
      barCapabilities ? "bar" : "no-bar",
      shell.manifestHasKind(manifest, "menu") ? "menu" : "no-menu"
    ].join("|")
  }

  function cacheWithoutKey(cache, key, destroyValue) {
    var next = ({})
    for (var existing in cache) {
      if (existing === key) {
        var value = cache[existing]
        if (destroyValue && value && typeof value.destroy === "function") value.destroy()
      } else {
        next[existing] = cache[existing]
      }
    }
    return next
  }

  function cacheWithoutPrefix(cache, prefix) {
    var next = ({})
    for (var existing in cache) {
      if (existing.indexOf(prefix) === 0) {
        var value = cache[existing]
        if (value && typeof value.destroy === "function") value.destroy()
      } else {
        next[existing] = cache[existing]
      }
    }
    return next
  }

  function revokePluginShellApi(cacheKey) {
    var key = String(cacheKey || "")
    if (!key) return
    _pluginAppLibraryApis = shell.cacheWithoutKey(_pluginAppLibraryApis, key, true)
    _pluginFirstPartyServiceApis = shell.cacheWithoutPrefix(_pluginFirstPartyServiceApis, key + "::")
    _pluginBarEntryShellApis = shell.cacheWithoutPrefix(_pluginBarEntryShellApis, key + ":")
    _pluginShellApis = shell.cacheWithoutKey(_pluginShellApis, key, true)
    _pluginShellApiDescriptors = shell.cacheWithoutKey(_pluginShellApiDescriptors, key, false)
  }

  function createScopedPluginShell(manifest, cacheKey, allowOwnService, barCapabilities) {
    var key = String(manifest && manifest.id || "")
    if (!key) return null
    var profile = shell.pluginShellCapabilityProfile(manifest, allowOwnService, barCapabilities)
    var cached = _pluginShellApis[cacheKey]
    var descriptor = _pluginShellApiDescriptors[cacheKey]
    if (cached && descriptor && descriptor.pluginId === key
        && descriptor.profile === profile) return cached
    if (cached || descriptor) shell.revokePluginShellApi(cacheKey)

    function currentManifest() {
      return shell.pluginRegistry.installedPlugins[key] || null
    }

    function hasCurrentBarCapabilities() {
      return barCapabilities && shell.pluginHasBarCapabilities(currentManifest())
    }

    // Construct the narrow service proxies before any plugin binding can call
    // firstPartyServiceFor(). Creating a QObject while evaluating that binding
    // makes QML re-enter the binding and report a loop on the caller's service
    // property, even though the resulting proxy is otherwise acyclic.
    var firstPartyServices = ({})
    if (barCapabilities) {
      var serviceIds = ["omarchy.idle", "omarchy.media", "omarchy.nightlight", "omarchy.notifications"]
      for (var i = 0; i < serviceIds.length; i++) {
        var serviceId = serviceIds[i]
        firstPartyServices[serviceId] = shell.pluginFirstPartyServiceFor(cacheKey, key, serviceId)
      }
    }

    var api = pluginShellApiComponent.createObject(null, {
      pluginId: key,
      appLibrary: shell.manifestHasKind(manifest, "menu")
        ? shell.pluginAppLibraryFor(cacheKey, key) : null,
      bar: shell.pluginBarStateFor(cacheKey, key),
      barConfig: shell.publicBarConfig(),
      _serviceLookup: function(requestedId) {
        return allowOwnService ? shell.pluginServiceFor(key, requestedId) : null
      },
      _firstPartyServiceLookup: function(requestedId) {
        if (allowOwnService && shell.pluginOwnsTarget(key, requestedId))
          return shell.pluginServiceFor(key, requestedId)
        return hasCurrentBarCapabilities() ? (firstPartyServices[requestedId] || null) : null
      },
      _barEntryShellLookup: function(ownerId, moduleName) {
        return hasCurrentBarCapabilities()
          ? shell.pluginShellForBarEntry(cacheKey + ":" + ownerId, moduleName) : null
      },
      _summon: function(requestedId, payloadJson) {
        if (!shell.pluginOwnsTarget(key, requestedId)
            && !shell.barPluginMayControl(currentManifest(), requestedId)) return false
        return shell.summon(shell.pluginRegistry.resolveEnabledId(requestedId), payloadJson)
      },
      _hide: function(requestedId) {
        if (!shell.pluginOwnsTarget(key, requestedId)
            && !shell.barPluginMayControl(currentManifest(), requestedId)) return false
        return shell.hide(shell.pluginRegistry.resolveEnabledId(requestedId))
      },
      _toggle: function(requestedId, payloadJson) {
        if (!shell.pluginOwnsTarget(key, requestedId)
            && !shell.barPluginMayControl(currentManifest(), requestedId)) return false
        return shell.toggle(shell.pluginRegistry.resolveEnabledId(requestedId), payloadJson)
      },
      _isOpen: function(requestedId) {
        if (!shell.pluginOwnsTarget(key, requestedId)
            && !shell.barPluginMayControl(currentManifest(), requestedId)) return false
        return shell.isPluginOpen(shell.pluginRegistry.resolveEnabledId(requestedId))
      },
      _updateSettings: function(requestedId, settings) {
        if (shell.pluginOwnsTarget(key, requestedId)) return shell.updateEntryInline(key, settings)
        if (hasCurrentBarCapabilities() && shell.barEntryConfigured(requestedId))
          return shell.updateEntryInline(requestedId, settings)
        return false
      },
      _mutateBarConfig: function(mutator) {
        return hasCurrentBarCapabilities() ? shell.mutatePluginBarConfig(mutator) : false
      }
    })
    if (!api) return null

    var next = ({})
    for (var id in _pluginShellApis) next[id] = _pluginShellApis[id]
    next[cacheKey] = api
    _pluginShellApis = next
    var descriptorNext = ({})
    for (var descriptorKey in _pluginShellApiDescriptors)
      descriptorNext[descriptorKey] = _pluginShellApiDescriptors[descriptorKey]
    descriptorNext[cacheKey] = {
      pluginId: key,
      allowOwnService: allowOwnService === true,
      profile: profile
    }
    _pluginShellApiDescriptors = descriptorNext
    return api
  }

  function scopedPluginShellForId(pluginId) {
    var key = String(pluginId || "")
    var manifest = shell.pluginRegistry.installedPlugins[key]
    if (!manifest) return null
    if (!manifest.__isFirstParty) return shell.pluginShellFor(manifest)
    return shell.createScopedPluginShell(manifest, "hosted:" + key, false, false)
  }

  function pluginShellForId(pluginId) {
    return shell.scopedPluginShellForId(pluginId)
  }

  function pluginShellForBarEntry(ownerId, moduleName) {
    var owner = String(ownerId || "")
    var target = String(moduleName || "")
    if (!owner || !target) return null
    if (!shell.barEntryConfigured(target)) return null
    var cacheKey = owner + "::" + target
    if (_pluginBarEntryShellApis[cacheKey]) return _pluginBarEntryShellApis[cacheKey]

    function owns(requestedId) {
      return shell.pluginRegistry.resolveEnabledId(String(requestedId || ""))
        === shell.pluginRegistry.resolveEnabledId(target)
    }

    var api = pluginShellApiComponent.createObject(null, {
      pluginId: target,
      barConfig: shell.publicBarConfig(),
      _summon: function(requestedId, payloadJson) {
        return owns(requestedId)
          ? shell.summon(shell.pluginRegistry.resolveEnabledId(target), payloadJson) : false
      },
      _hide: function(requestedId) {
        return owns(requestedId)
          ? shell.hide(shell.pluginRegistry.resolveEnabledId(target)) : false
      },
      _toggle: function(requestedId, payloadJson) {
        return owns(requestedId)
          ? shell.toggle(shell.pluginRegistry.resolveEnabledId(target), payloadJson) : false
      },
      _isOpen: function(requestedId) {
        return owns(requestedId)
          ? shell.isPluginOpen(shell.pluginRegistry.resolveEnabledId(target)) : false
      },
      _updateSettings: function(requestedId, settings) {
        return String(requestedId || "") === target
          ? shell.updateEntryInline(target, settings) : false
      }
    })
    if (!api) return null
    var next = ({})
    for (var id in _pluginBarEntryShellApis) next[id] = _pluginBarEntryShellApis[id]
    next[cacheKey] = api
    _pluginBarEntryShellApis = next
    return api
  }

  function pluginShellFor(manifest) {
    if (!manifest || manifest.__isFirstParty) return shell
    var key = String(manifest.id || "")
    if (!key) return null
    return shell.createScopedPluginShell(manifest, key, true, shell.pluginHasBarCapabilities(manifest))
  }

  function pluginRegistryFor(manifest) {
    if (!manifest || manifest.__isFirstParty) return shell.pluginRegistry
    var key = String(manifest.id || "")
    if (!key) return null
    if (_pluginRegistryApis[key]) return _pluginRegistryApis[key]

    var api = pluginRegistryApiComponent.createObject(null, {
      pluginId: key,
      manifest: shell.publicPluginManifest(manifest),
      enabled: shell.pluginRegistry.isEnabled(key),
      _entryPointUrl: function(kind) {
        var current = shell.pluginRegistry.installedPlugins[key]
        return current ? shell.pluginRegistry.entryPointUrl(current, kind) : ""
      }
    })
    if (!api) return null

    var next = ({})
    for (var id in _pluginRegistryApis) next[id] = _pluginRegistryApis[id]
    next[key] = api
    _pluginRegistryApis = next
    return api
  }

  function pluginBarWidgetRegistryFor(manifest) {
    if (!manifest || manifest.__isFirstParty) return shell.barWidgetRegistry
    var key = String(manifest.id || "")
    if (!key) return null
    if (_pluginBarWidgetRegistryApis[key]) return _pluginBarWidgetRegistryApis[key]

    var api = pluginBarWidgetRegistryApiComponent.createObject(null, {
      widgets: shell.publicBarWidgetSnapshot(),
      revision: shell.barWidgetRegistry.revision
    })
    if (!api) return null

    var next = ({})
    for (var id in _pluginBarWidgetRegistryApis) next[id] = _pluginBarWidgetRegistryApis[id]
    next[key] = api
    _pluginBarWidgetRegistryApis = next
    return api
  }

  function pluginApiActive(api, plugins) {
    var id = api ? String(api.pluginId || api.ownerPluginId || "") : ""
    var manifest = id ? plugins[id] : null
    return !!manifest && shell.pluginRegistry.isEnabled(id)
  }

  function prunePluginApis() {
    var plugins = shell.pluginRegistry.installedPlugins
    var shellKeys = Object.keys(_pluginShellApis)
    for (var si = 0; si < shellKeys.length; si++) {
      var shellKey = shellKeys[si]
      var shellApi = _pluginShellApis[shellKey]
      var descriptor = _pluginShellApiDescriptors[shellKey]
      var manifest = descriptor ? plugins[descriptor.pluginId] : null
      var barCapabilities = descriptor && descriptor.allowOwnService
        && shell.pluginHasBarCapabilities(manifest)
      var expectedProfile = descriptor
        ? shell.pluginShellCapabilityProfile(manifest, descriptor.allowOwnService, barCapabilities) : ""
      var active = descriptor && manifest && shell.pluginRegistry.isEnabled(descriptor.pluginId)
      if (!active || descriptor.profile !== expectedProfile)
        shell.revokePluginShellApi(shellKey)
    }

    var registryNext = ({})
    for (var registryKey in _pluginRegistryApis) {
      var registryApi = _pluginRegistryApis[registryKey]
      if (shell.pluginApiActive(registryApi, plugins)) registryNext[registryKey] = registryApi
      else if (registryApi && typeof registryApi.destroy === "function") registryApi.destroy()
    }
    _pluginRegistryApis = registryNext

    var widgetNext = ({})
    for (var widgetKey in _pluginBarWidgetRegistryApis) {
      var widgetApi = _pluginBarWidgetRegistryApis[widgetKey]
      if (plugins[widgetKey] && shell.pluginRegistry.isEnabled(widgetKey)) widgetNext[widgetKey] = widgetApi
      else if (widgetApi && typeof widgetApi.destroy === "function") widgetApi.destroy()
    }
    _pluginBarWidgetRegistryApis = widgetNext

    var appNext = ({})
    for (var appKey in _pluginAppLibraryApis) {
      var appApi = _pluginAppLibraryApis[appKey]
      if (shell.pluginApiActive(appApi, plugins)) appNext[appKey] = appApi
      else if (appApi && typeof appApi.destroy === "function") appApi.destroy()
    }
    _pluginAppLibraryApis = appNext

    var barStateNext = ({})
    for (var barStateKey in _pluginBarStateApis) {
      var barStateApi = _pluginBarStateApis[barStateKey]
      if (shell.pluginApiActive(barStateApi, plugins)) barStateNext[barStateKey] = barStateApi
      else if (barStateApi && typeof barStateApi.destroy === "function") barStateApi.destroy()
    }
    _pluginBarStateApis = barStateNext

    var serviceNext = ({})
    for (var serviceKey in _pluginFirstPartyServiceApis) {
      var serviceApi = _pluginFirstPartyServiceApis[serviceKey]
      if (shell.pluginApiActive(serviceApi, plugins)) serviceNext[serviceKey] = serviceApi
      else if (serviceApi && typeof serviceApi.destroy === "function") serviceApi.destroy()
    }
    _pluginFirstPartyServiceApis = serviceNext

    var entryNext = ({})
    for (var entryKey in _pluginBarEntryShellApis) {
      var entryApi = _pluginBarEntryShellApis[entryKey]
      if (entryApi && shell.barEntryConfigured(entryApi.pluginId)) entryNext[entryKey] = entryApi
      else if (entryApi && typeof entryApi.destroy === "function") entryApi.destroy()
    }
    _pluginBarEntryShellApis = entryNext
  }

  function syncPluginApis() {
    shell.prunePluginApis()
    var plugins = shell.pluginRegistry.installedPlugins
    for (var id in _pluginRegistryApis) {
      var registryApi = _pluginRegistryApis[id]
      var manifest = plugins[id]
      registryApi.manifest = shell.publicPluginManifest(manifest)
      registryApi.enabled = !!manifest && shell.pluginRegistry.isEnabled(id)
    }
    for (var widgetId in _pluginBarWidgetRegistryApis) {
      var widgetApi = _pluginBarWidgetRegistryApis[widgetId]
      widgetApi.widgets = shell.publicBarWidgetSnapshot()
      widgetApi.revision = shell.barWidgetRegistry.revision
    }
    for (var shellKey in _pluginShellApis)
      _pluginShellApis[shellKey].barConfig = shell.publicBarConfig()
    for (var entryKey in _pluginBarEntryShellApis)
      _pluginBarEntryShellApis[entryKey].barConfig = shell.publicBarConfig()
  }

  function serviceFor(pluginId) {
    return _services[String(pluginId)] || null
  }

  function firstPartyServiceFor(pluginId) {
    return serviceFor(shell.pluginRegistry.resolveEnabledId(pluginId))
  }

  function isAuthenticationService(manifest) {
    return !!manifest && Array.isArray(manifest.__hostCapabilities)
      && manifest.__hostCapabilities.indexOf("authentication") !== -1
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
    var authenticationService = shell.isAuthenticationService(manifest)
    if (authenticationService && AuthServiceStore.has(key)) return null

    var comp = Qt.createComponent(url, Component.PreferSynchronous)
    function finalize() {
      if (comp.status !== Component.Ready) {
        console.warn("service plugin load failed for " + key + ": " + comp.errorString())
        return
      }
      // Authentication services and third-party services have no visual
      // parent. Parenting either to serviceHost would let a plugin's object
      // traversal walk between the host and credential-bearing QML.
      var inst = comp.createObject(manifest.__isFirstParty && !authenticationService ? serviceHost : null)
      if (!inst) {
        console.warn("service plugin createObject returned null for", key)
        return
      }
      if ("omarchyPath" in inst) inst.omarchyPath = shell.omarchyPath
      if ("shell" in inst) inst.shell = shell.pluginShellFor(manifest)
      if ("manifest" in inst) inst.manifest = shell.publicPluginManifest(manifest)
      if ("barWidgetRegistry" in inst) inst.barWidgetRegistry = shell.pluginBarWidgetRegistryFor(manifest)
      if ("pluginRegistry" in inst) inst.pluginRegistry = shell.pluginRegistryFor(manifest)
      if (authenticationService) {
        // Never publish lock/polkit through ShellRoot._services. The private JS
        // import retains their lifetime without adding a traversable property
        // or QObject parent back to the host shell.
        AuthServiceStore.put(key, inst)
      } else {
        var snext = ({})
        for (var sk in _services) snext[sk] = _services[sk]
        snext[key] = inst
        _services = snext
      }
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
      return null
    }
    finalize()
    return authenticationService ? null : (_services[key] || null)
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
      var authenticationService = shell.isAuthenticationService(m)
      if (_services[id]) {
        if (authenticationService) {
          // A service that gains a trusted authentication capability must move
          // out of the host's public service map before it is recreated.
          var published = _services[id]
          if (published && typeof published.destroy === "function") published.destroy()
          var withoutPublished = ({})
          for (var publishedId in _services)
            if (publishedId !== id) withoutPublished[publishedId] = _services[publishedId]
          _services = withoutPublished
        } else {
          // A kept instance outlives the rescan; hand it the fresh manifest.
          var kept = _services[id]
          if (kept && "shell" in kept) kept.shell = shell.pluginShellFor(m)
          if (kept && "manifest" in kept) kept.manifest = shell.publicPluginManifest(m)
          continue
        }
      }
      if (AuthServiceStore.has(id)) {
        if (authenticationService) {
          AuthServiceStore.updateManifest(id, shell.publicPluginManifest(m))
          continue
        }
        // A service that loses its trusted authentication capability can move
        // back to the ordinary service map only after the isolated copy dies.
        AuthServiceStore.destroy(id)
      }
      ensureService(id)
    }
    // Drop services for plugins that have been disabled or removed, or that
    // no longer declare a service entry point.
    for (var existingId in _services) {
      var stillThere = plugins[existingId]
      var stillService = stillThere && Array.isArray(stillThere.kinds)
        && stillThere.kinds.indexOf("service") !== -1
        && stillThere.entryPoints && stillThere.entryPoints.service
      var stillEnabled = stillThere && pluginRegistry.isEnabled(existingId)
      if (stillService && stillEnabled) continue
      var inst = _services[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
      var next = ({})
      for (var k in _services) if (k !== existingId) next[k] = _services[k]
      _services = next
    }
    // Authentication services are retained outside the root object graph, so
    // reconcile their disable/remove lifecycle separately from _services.
    var authenticationIds = AuthServiceStore.ids()
    for (var ai = 0; ai < authenticationIds.length; ai++) {
      var authenticationId = authenticationIds[ai]
      var authenticationManifest = plugins[authenticationId]
      var stillAuthenticationService = authenticationManifest
        && Array.isArray(authenticationManifest.kinds)
        && authenticationManifest.kinds.indexOf("service") !== -1
        && authenticationManifest.entryPoints
        && authenticationManifest.entryPoints.service
      if (stillAuthenticationService && pluginRegistry.isEnabled(authenticationId)
          && shell.isAuthenticationService(authenticationManifest)) continue
      AuthServiceStore.destroy(authenticationId)
    }
  }

  function serviceKeepLoaded(pluginId) {
    var plugins = pluginRegistry && pluginRegistry.installedPlugins
    var manifest = plugins ? plugins[pluginId] : null
    return !!(manifest && manifest.keepLoaded === true)
  }

  // keepLoaded services (lock, idle, polkit) must survive plugin hot-reload.
  // Destroying omarchy.lock drops the ext-session-lock client while Hyprland
  // still holds the lock, which surfaces the crashed-lockscreen fallback.
  function unloadPluginServices() {
    var next = ({})
    for (var existingId in _services) {
      if (serviceKeepLoaded(existingId)) {
        next[existingId] = _services[existingId]
        continue
      }
      var inst = _services[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
    }
    _services = next
    var authenticationIds = AuthServiceStore.ids()
    for (var ai = 0; ai < authenticationIds.length; ai++) {
      var authenticationId = authenticationIds[ai]
      if (!serviceKeepLoaded(authenticationId))
        AuthServiceStore.destroy(authenticationId)
    }
  }

  Connections {
    target: shell.pluginRegistry
    function onPluginsChanged() {
      shell.syncPluginApis()
      if (!shell.pluginReloading) shell._syncServices()
    }
  }

  Connections {
    target: shell.barWidgetRegistry
    function onChanged() { shell.syncPluginApis() }
  }

  Connections {
    target: shell.appLibrary
    function onAppsChanged() {
      for (var id in shell._pluginAppLibraryApis)
        shell._pluginAppLibraryApis[id].appsChanged()
    }
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
    function onPluginsChanged() { if (!shell.pluginReloading) shell.panelEntries = shell.computePanelEntries() }
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
          if ("shell" in item) item.shell = shell.pluginShellFor(panelEntry.manifest)
          if ("manifest" in item) item.manifest = shell.publicPluginManifest(panelEntry.manifest)
          if ("barWidgetRegistry" in item) item.barWidgetRegistry = shell.pluginBarWidgetRegistryFor(panelEntry.manifest)
          if ("pluginRegistry" in item) item.pluginRegistry = shell.pluginRegistryFor(panelEntry.manifest)
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
        source: "plugin",
        firstParty: !!manifest.__isFirstParty
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
      if (!pluginWidgetComponents[id]) continue
      if (!seen[id]) {
        shell.barWidgetRegistry.unregister(id)
        var next = ({})
        for (var k in pluginWidgetComponents) if (k !== id) next[k] = pluginWidgetComponents[k]
        pluginWidgetComponents = next
      }
    }
  }

  function unloadPluginWidgets() {
    for (var id in pluginWidgetComponents) shell.barWidgetRegistry.unregister(id)
    pluginWidgetComponents = ({})
  }

  function reloadPlugins() {
    if (shell.pluginReloading || shell.pluginRegistry.scanning) {
      shell.pluginReloadPending = true
      return
    }
    shell.pluginReloading = true
    shell.unloadPanels()
    shell.unloadPluginServices()
    shell.unloadPluginWidgets()
    Qt.callLater(shell.finishPluginReload)
  }

  function finishPluginReload() {
    if (!shell.pluginReloading) return
    if (shell.pluginRegistry.scanning) {
      shell.pluginReloadPending = true
      return
    }
    if (typeof Qt.clearComponentCache === "function") Qt.clearComponentCache()
    shell.pluginRegistry.rescan()
  }

  Connections {
    target: shell.pluginRegistry
    function onLocalPluginChanged(pluginId) {
      console.log("Local plugin changed, reloading:", pluginId)
      localPluginReloadTimer.restart()
    }
    function onScanFinished() {
      if (shell.pluginReloadPending) {
        shell.pluginReloadPending = false
        shell.pluginReloading = false
        Qt.callLater(shell.reloadPlugins)
        return
      }
      shell.pluginReloading = false
      shell._syncServices()
      shell.panelEntries = shell.computePanelEntries()
      shell.syncPluginWidgets()
    }
  }

  function setPluginWidgetComponent(registryKey, entry) {
    var next = ({})
    for (var k in pluginWidgetComponents) if (k !== registryKey) next[k] = pluginWidgetComponents[k]
    if (entry) next[registryKey] = entry
    pluginWidgetComponents = next
  }

  function loadPluginWidget(registryKey, url, meta) {
    // Claim the key before the component exists. Qt.createComponent is
    // asynchronous and syncPluginWidgets runs several times while the shell
    // starts, so without a marker the later passes cannot tell a load in
    // flight from one that never happened.
    setPluginWidgetComponent(registryKey, { url: url, component: null })

    var comp = Qt.createComponent(url, Component.Asynchronous)
    function finalize() {
      if (comp.status === Component.Ready) {
        shell.barWidgetRegistry.register(registryKey, comp, meta)
        shell.setPluginWidgetComponent(registryKey, { url: url, component: comp })
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
