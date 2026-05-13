pragma Singleton
import QtQuick

// Noctalia compat shim. Their plugins resolve app icons through XDG icon
// themes; we don't ship that machinery, so iconForAppId returns empty and
// callers fall back to their default glyph.
QtObject {
  function iconFromName(name) { return "" }
  function iconForAppId(appId) { return "" }
}
