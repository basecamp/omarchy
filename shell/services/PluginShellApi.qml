import QtQuick

// Capability-scoped shell surface for installed third-party plugins.
//
// The callbacks are closed over one plugin id by shell.qml. A plugin can call
// them directly, but it cannot widen their scope: ordinary plugins are limited
// to their own id, and full-bar callbacks independently enforce their explicit
// non-authentication UI scope. This object avoids directly injecting the host
// shell, but it is not a QML sandbox: visual plugins share the host object tree.
QtObject {
  id: api

  required property string pluginId

  property var appLibrary: null
  property var bar: null
  property var barConfig: ({})

  property var _serviceLookup: null
  property var _firstPartyServiceLookup: null
  property var _barEntryShellLookup: null
  property var _summon: null
  property var _hide: null
  property var _toggle: null
  property var _isOpen: null
  property var _updateSettings: null
  property var _mutateBarConfig: null

  function serviceFor(id) {
    return _serviceLookup ? _serviceLookup(String(id || "")) : null
  }

  // Only full-bar facades receive narrow proxies for the specific
  // non-authentication services used by the built-in bar widgets.
  function firstPartyServiceFor(id) {
    return _firstPartyServiceLookup
      ? _firstPartyServiceLookup(String(id || "")) : null
  }

  function pluginShellForBarEntry(ownerId, moduleName) {
    return _barEntryShellLookup
      ? _barEntryShellLookup(String(ownerId || ""), String(moduleName || "")) : null
  }

  function summon(id, payloadJson) {
    return _summon ? _summon(String(id || ""), String(payloadJson || "")) : false
  }

  function hide(id) {
    return _hide ? _hide(String(id || "")) : false
  }

  function toggle(id, payloadJson) {
    return _toggle ? _toggle(String(id || ""), String(payloadJson || "")) : false
  }

  function isPluginOpen(id) {
    return _isOpen ? _isOpen(String(id || "")) : false
  }

  function updateEntryInline(id, settings) {
    return _updateSettings ? _updateSettings(String(id || ""), settings) : false
  }

  function mutateShellConfig(mutator) {
    return _mutateBarConfig && typeof mutator === "function"
      ? _mutateBarConfig(mutator) : false
  }
}
