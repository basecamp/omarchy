import QtQuick
import Quickshell
import Quickshell.Io

import "plugins/bar"
import "services" as Services

ShellRoot {
  id: shell

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

  Component.onCompleted: {
    console.log("omarchy-shell paths",
      "omarchyPath=" + shell.omarchyPath,
      "shellDir=" + Quickshell.shellDir,
      "firstPartyPluginsDir=" + shell.firstPartyPluginsDir)
    Services.PluginRegistry.firstPartyDir = shell.firstPartyPluginsDir
    // PluginRegistry.ensureUserDir() runs in its own Component.onCompleted and
    // chains rescan() once the directory exists. We also kick a scan here in
    // case the user dir already existed at startup.
    Services.PluginRegistry.rescan()
  }

  Bar {
    id: bar
    omarchyPath: shell.omarchyPath
  }

  // ---------------------------------------------------------- plugin loader

  // Mirror plugin registry state into BarWidgetRegistry whenever it changes.
  // Each enabled plugin with kind "bar-widget" gets a Component created from
  // its manifest entry point and registered under the id "plugin:<id>".
  Connections {
    target: Services.PluginRegistry
    function onPluginsChanged() { shell.syncPluginWidgets() }
  }

  property var pluginWidgetComponents: ({})

  function syncPluginWidgets() {
    var plugins = Services.PluginRegistry.installedPlugins
    var seen = ({})

    for (var pluginId in plugins) {
      var manifest = plugins[pluginId]
      if (!manifest || !manifest.kinds || manifest.kinds.indexOf("bar-widget") === -1) continue
      if (!Services.PluginRegistry.isEnabled(pluginId)) continue

      var registryKey = "plugin:" + manifest.id
      seen[registryKey] = true

      // Already loaded with matching source — leave it alone.
      var existing = pluginWidgetComponents[registryKey]
      var url = Services.PluginRegistry.entryPointUrl(manifest, "barWidget")
      if (!url) {
        console.warn("Plugin " + manifest.id + " has no barWidget entry point")
        continue
      }
      if (existing && existing.url === url && Services.BarWidgetRegistry.has(registryKey)) continue

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
    var allIds = Services.BarWidgetRegistry.availableIds()
    for (var i = 0; i < allIds.length; i++) {
      var id = allIds[i]
      if (id.indexOf("plugin:") !== 0) continue
      if (!seen[id]) {
        Services.BarWidgetRegistry.unregister(id)
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
        Services.BarWidgetRegistry.register(registryKey, comp, meta)
        var next = ({})
        for (var k in pluginWidgetComponents) next[k] = pluginWidgetComponents[k]
        next[registryKey] = { url: url, component: comp }
        pluginWidgetComponents = next
      } else if (comp.status === Component.Error) {
        console.warn("Plugin widget " + registryKey + " failed: " + comp.errorString())
        Services.PluginRegistry.pluginLoadFailed(registryKey, comp.errorString())
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
      Services.PluginRegistry.rescan()
    }

    function setPluginEnabled(id: string, enabled: string): void {
      Services.PluginRegistry.setEnabled(id, enabled === "true")
    }

    function listPlugins(): string {
      var out = []
      var plugins = Services.PluginRegistry.installedPlugins
      for (var id in plugins) {
        out.push({
          id: id,
          name: plugins[id].name,
          kinds: plugins[id].kinds,
          enabled: Services.PluginRegistry.isEnabled(id),
          firstParty: !!plugins[id].__isFirstParty
        })
      }
      return JSON.stringify(out)
    }
  }
}
