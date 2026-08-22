import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Resolves Desktop Mode vs Power User Mode. UI checks feature flags, not
// mode strings (docs/mode-profiles.md). User choice lives in
// ~/.local/state/omarchy/ultimate/mode; shipped defaults live in
// $OMARCHY_PATH/default/ultimate/profiles/.
QtObject {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string home: Quickshell.env("HOME")
  property int revision: 0

  property string mode: "desktop"
  property string description: "Consumer default profile: floating windows, taskbar, Start, desktop icons, visible-before-memorable affordances. Windows muscle memory is the API."
  // Match desktop.json so the first frame is Desktop Mode before FileView lands.
  property var features: ({
    desktopIcons: true,
    taskbar: true,
    startMenu: true,
    systemTray: true,
    quickSettings: true,
    notificationCenter: true,
    floatingWindows: true,
    tilingDefault: false,
    snapLayouts: true,
    taskView: true,
    omarchyBindings: false,
    powerUserMenu: false,
    topBar: false,
    configEditingExposed: false
  })
  property var desktopProfile: ({})
  property var powerUserProfile: ({})

  readonly property string modeFilePath: home + "/.local/state/omarchy/ultimate/mode"
  readonly property string desktopProfilePath: omarchyPath + "/default/ultimate/profiles/desktop.json"
  readonly property string powerUserProfilePath: omarchyPath + "/default/ultimate/profiles/power-user.json"

  function feature(name) {
    return !!(root.features && root.features[String(name)] === true)
  }

  function _parseProfile(raw) {
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      if (Util.isPlainObject(parsed)) return parsed
    } catch (e) {
    }
    return ({})
  }

  function _apply() {
    var chosen = root.mode === "power-user" ? root.powerUserProfile : root.desktopProfile
    if (!Util.isPlainObject(chosen) || Object.keys(chosen).length === 0) {
      chosen = root.desktopProfile
    }
    root.description = String(chosen.description || "")
    root.features = Util.isPlainObject(chosen.features) ? chosen.features : ({})
    root.revision++
  }

  function _setModeFromText(raw) {
    var value = String(raw || "").replace(/\s+/g, "")
    if (value === "power-user") root.mode = "power-user"
    else root.mode = "desktop"
    root._apply()
  }

  function setMode(next) {
    var value = String(next || "")
    if (value !== "desktop" && value !== "power-user") return false
    root.mode = value
    root._apply()
    writeMode.command = [
      "bash", "-c",
      "mkdir -p \"$0\" && printf '%s\\n' \"$1\" > \"$0/mode\"; hyprctl reload >/dev/null 2>&1 || true",
      root.home + "/.local/state/omarchy/ultimate",
      value
    ]
    writeMode.running = true
    return true
  }

  FileView {
    id: desktopProfileFile
    path: root.desktopProfilePath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.desktopProfile = root._parseProfile(text())
      root._apply()
    }
    onLoadFailed: root.desktopProfile = ({})
    onFileChanged: reload()
  }

  FileView {
    id: powerUserProfileFile
    path: root.powerUserProfilePath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.powerUserProfile = root._parseProfile(text())
      root._apply()
    }
    onLoadFailed: root.powerUserProfile = ({})
    onFileChanged: reload()
  }

  FileView {
    id: modeFile
    path: root.modeFilePath
    watchChanges: true
    printErrors: false
    onLoaded: root._setModeFromText(text())
    onLoadFailed: root._setModeFromText("")
    onFileChanged: reload()
  }

  Process {
    id: writeMode
  }
}
