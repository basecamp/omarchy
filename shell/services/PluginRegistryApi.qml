import QtQuick

// Read-only, self-scoped registry view for an installed third-party plugin.
// The host updates manifest/enabled when it rescans; no host registry object is
// retained here, so `parent` and property traversal cannot reach ShellRoot.
QtObject {
  id: api

  required property string pluginId
  property var manifest: null
  property bool enabled: false
  property var _entryPointUrl: null

  readonly property var installedPlugins: {
    var out = ({})
    if (manifest) out[pluginId] = manifest
    return out
  }

  function isEnabled(id) {
    return String(id || "") === pluginId && enabled
  }

  function resolveEnabledId(id) {
    return String(id || "") === pluginId ? pluginId : ""
  }

  function entryPointUrl(candidate, kind) {
    if (!candidate || String(candidate.id || "") !== pluginId) return ""
    return _entryPointUrl ? _entryPointUrl(String(kind || "")) : ""
  }
}
