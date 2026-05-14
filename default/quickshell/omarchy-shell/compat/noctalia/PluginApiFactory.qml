import QtQuick
import Quickshell

// Builds the `pluginApi` QtObject that Noctalia plugins expect. The host
// (omarchy-shell or the bar) calls create() once per plugin and caches the
// returned object so the same handle is reused across the plugin's bar
// widget, panel, settings form, etc.
Item {
  // create(pluginId, manifest, settingsProvider, hostBridge) -> QtObject
  //
  // settingsProvider: function() that returns the plugin's current settings
  //   merged with defaults. Called fresh on every read so the plugin always
  //   sees the live shell.json entry, not a stale snapshot from when create()
  //   was first called.
  // hostBridge: object with these methods (all optional):
  //   - persistSettings(pluginId, settings): write back to shell.json via
  //     the shell's updateEntryInline helper.
  //   - openPanel(pluginId, screen, buttonItem): summon the plugin's panel
  //     entry point through the shell's plugin host.
  //   - closePanel(pluginId, screen): hide a previously-summoned panel.
  //   - currentScreen(): return the screen the plugin should anchor to.
  // togglePanel is provided by the factory itself and routes through the
  // open/closePanel bridge methods. Main.qml service instances are wired
  // separately by the shell and set on api.mainInstance once instantiated.
  function create(pluginId, manifest, settingsProvider, hostBridge) {
    var api = pluginApiFactory.createObject(null, {
      pluginId: pluginId,
      pluginDir: manifest && manifest.__sourceDir ? manifest.__sourceDir : "",
      manifest: manifest || ({}),
      _settingsProvider: settingsProvider || (function() { return {} }),
      _hostBridge: hostBridge || ({})
    })
    return api
  }

  Component {
    id: pluginApiFactory

    QtObject {
      id: api

      property string pluginId: ""
      property string pluginDir: ""
      property var manifest: ({})
      property var _settingsProvider
      property var _hostBridge: ({})
      property var mainInstance: null

      // Writable because Noctalia Settings.qml components commonly stage edits
      // with `pluginApi.pluginSettings = ...; pluginApi.saveSettings()`.
      // The initial binding resolves shell.json + defaults; assignment during
      // save intentionally replaces it with the staged value to persist.
      property var pluginSettings: _settingsProvider ? _settingsProvider() : ({})

      property var panelOpenScreen: null
      property var panelAnchorItem: null
      property var ipcHandlers: ({})

      // Noctalia i18n surface — v1 returns the key as-is.
      readonly property string currentLanguage: "en"
      readonly property var pluginTranslations: ({})
      readonly property var pluginFallbackTranslations: ({})
      readonly property int translationVersion: 0

      function tr(key, interp) { return String(key === undefined ? "" : key) }
      function trp(key, count, interp) { return String(key === undefined ? "" : key) }
      function hasTranslation(key) { return false }

      function saveSettings(settings) {
        if (settings !== undefined) pluginSettings = settings
        if (_hostBridge && typeof _hostBridge.persistSettings === "function")
          _hostBridge.persistSettings(pluginId, pluginSettings)
        // Re-read after persisting so mainInstance/bar widgets see the
        // canonical merged settings (defaults + saved overrides) immediately.
        if (_settingsProvider) pluginSettings = _settingsProvider()
        if (mainInstance && typeof mainInstance.refresh === "function") mainInstance.refresh()
      }

      function openPanel(screen, buttonItem) {
        panelOpenScreen = screen || true
        panelAnchorItem = buttonItem || null
        if (_hostBridge && _hostBridge.tooltipService && typeof _hostBridge.tooltipService.hide === "function")
          _hostBridge.tooltipService.hide(buttonItem)
        if (_hostBridge && typeof _hostBridge.openPanel === "function")
          _hostBridge.openPanel(pluginId, screen, buttonItem)
      }

      function closePanel(screen) {
        panelOpenScreen = null
        panelAnchorItem = null
        if (_hostBridge && typeof _hostBridge.closePanel === "function")
          _hostBridge.closePanel(pluginId, screen)
      }

      function togglePanel(screen, buttonItem) {
        if (panelOpenScreen) closePanel(screen)
        else openPanel(screen, buttonItem)
      }

      function withCurrentScreen(cb) {
        if (typeof cb !== "function") return
        var s = (_hostBridge && typeof _hostBridge.currentScreen === "function")
          ? _hostBridge.currentScreen() : null
        cb(s)
      }

      function openLauncher(screen) {
        console.warn("pluginApi.openLauncher is not supported in the Omarchy compat layer (plugin=" + pluginId + ")")
      }
      function closeLauncher(screen) { /* no-op */ }
      function toggleLauncher(screen) { openLauncher(screen) }
    }
  }
}
