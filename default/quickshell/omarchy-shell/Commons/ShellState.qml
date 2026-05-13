pragma Singleton
import QtQuick

// Noctalia compat shim. Their plugins occasionally introspect global UI
// state through this singleton. Returning safe defaults lets reads succeed
// without us tracking the state ourselves.
QtObject {
  readonly property bool isLoaded: true
  property var activeScreen: null
  property bool launcherOpen: false
  property bool controlCenterOpen: false
  property bool settingsOpen: false
}
