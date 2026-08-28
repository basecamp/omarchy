pragma Singleton
import QtQuick

// Glyph fits already measured this session, keyed by everything that shapes
// the render, so a glyph that recurs across buttons or cycles back in an
// animation settles at once instead of being rendered and measured again.
QtObject {
  property var entries: ({})

  function get(key) {
    return entries[key] || null
  }

  function set(key, value) {
    entries[key] = value
  }
}
