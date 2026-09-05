import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "AppSearch.js" as AppSearch

// Shared desktop-application library: the sorted entry list with hidden-entry
// filtering, the icon fallback index, launch feedback, and entry removal.
// Injected as shell.appLibrary; the menu's Apps submenu is the consumer.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property var configuredHiddenEntryIds: ({})
  property var desktopHiddenEntryIds: ({})

  // Maps an icon name to a file on disk (e.g. "omacut" -> ".../apps/omacut.svg").
  // Built by walking the icon theme's inheritance chain and limited to
  // app/device icons, so a name resolves without the ambiguity an
  // unconstrained themed lookup carries, and so icons installed after this
  // process started are found at all (Qt's icon cache never re-scans).
  // Refreshed whenever the app list changes, so newly installed apps get their
  // icon live.
  property var iconIndex: ({})
  property var pendingIconIndex: ({})

  property int launchSerial: 0
  property int launchToplevelCount: 0
  property var launchActiveToplevel: null
  // True while the launch OSD is on screen. It outlives the launch that opened
  // it: the OSD shows with duration 0, so only closeLaunchFeedback() takes it
  // down.
  property bool launchOsdOpen: false
  property string launchOsdMessage: ""

  // Emitted whenever the visible application set may have changed: desktop
  // entries appeared or vanished, or the hidden-entry filters reloaded.
  signal appsChanged()

  function entryName(entry) {
    return AppSearch.entryName(entry)
  }

  function entrySubtext(entry) {
    return AppSearch.entrySubtext(entry)
  }

  function isHiddenEntry(entry) {
    var id = String((entry && entry.id) || "")
    return root.configuredHiddenEntryIds[id] === true || root.desktopHiddenEntryIds[id] === true
  }

  function sortedEntries(query) {
    var values = DesktopEntries.applications.values || []
    return AppSearch.sortedEntries(values, query, function(entry) { return root.isHiddenEntry(entry) })
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    // Prefer the context-limited app/device index. An unconstrained themed
    // lookup can resolve an app name such as "zoom" to an action icon instead.
    var found = root.iconIndex[value]
    if (found) return Util.fileUrl(found)
    var themed = Quickshell.iconPath(value, true)
    if (themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  // The shell may start before first-install packages have finished placing
  // their icons; consumers call this when they open so icons appear live.
  function refreshIcons() {
    if (!iconIndexScan.running) iconIndexScan.running = true
  }

  function launch(desktopId, name) {
    var id = String(desktopId || "")
    if (!id) return
    root.beginLaunchFeedback(name)
    // Start gtk-launch inside a scope under app-graphical.slice so apps do not
    // inherit wayland-wm@.service. Keeping gtk-launch as the desktop-entry
    // resolver supports IDs with spaces and entries that UWSM rejects.
    // Keep the .desktop suffix or ids like org.telegram.desktop won't resolve.
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
  }

  function remove(desktopId, name) {
    var id = String(desktopId || "")
    if (!id) return
    Util.execDetached(Util.shellQuote(root.omarchyPath + "/bin/omarchy-remove-launcher-entry") + " " + Util.shellQuote(id) + " " + Util.shellQuote(String(name || id)))
  }

  function normalizeDesktopId(id) {
    var value = String(id || "").trim()
    if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
    return value
  }

  function loadConfiguredHides(rawText) {
    var next = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = root.normalizeDesktopId(lines[i])
      if (id.length > 0) next[id] = true
    }
    root.configuredHiddenEntryIds = next
    root.appsChanged()
  }

  function loadDesktopHiddenEntries(rawText) {
    var next = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = root.normalizeDesktopId(lines[i])
      if (id.length > 0) next[id] = true
    }
    root.desktopHiddenEntryIds = next
    root.appsChanged()
  }

  function iconIndexScanCommand() {
    // List app/device icons as "<path>" lines, in icon-theme search order: the
    // active theme, each theme it inherits depth-first in declared order, then
    // hicolor, then /usr/share/pixmaps. Some desktop entries, such as Print
    // Settings, use device icons like "printer" instead of app icons.
    //
    // The parser keeps the first hit per name, so this order is what picks the
    // icon; walking every theme on disk instead let whichever one `find`
    // reached first decide it. Depth-first is what the icon theme spec defines:
    // a parent's own inheritance is searched before the next declared parent.
    // A theme's icons may be spread across base directories, but only the first
    // index.theme found defines it, so the walk takes that one and stops.
    // hicolor is appended rather than followed through Inherits because it is
    // the fallback of last resort and themes do list it early
    // (Tela-circle-dark: "Inherits=hicolor,Adwaita,breeze").
    //
    // A theme is exhausted before the next is consulted, SVGs first and then
    // PNGs within it, so a scalable icon further down the search order cannot
    // outrank the configured theme's raster one. Each pass is reverse-sorted so
    // "scalable" beats the numeric size directories; symbolic icons are dropped
    // because that order would otherwise prefer a monochrome glyph.
    return [
      'theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "\'");',
      ': "${theme:=hicolor}";',
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'declare -A seen; order=();',
      'visit() {',
      '  local base parent;',
      '  if [[ -z $1 || $1 == "hicolor" || -n ${seen[$1]+set} ]]; then return; fi;',
      '  seen[$1]=1; order+=("$1");',
      '  for base in $dirs; do',
      '    [[ -f $base/$1/index.theme ]] || continue;',
      '    while IFS= read -r parent; do visit "$parent"; done < <(sed -n "s/^Inherits=//p" "$base/$1/index.theme" | head -1 | tr "," "\\n");',
      '    break;',
      '  done;',
      '};',
      'visit "$theme"; order+=(hicolor);',
      'for name in "${order[@]}"; do',
      '  for base in $dirs; do',
      '    [[ -d $base/$name ]] || continue;',
      '    for ext in svg png; do',
      '      find "$base/$name" \\( -path "*/apps/*" -o -path "*/devices/*" \\) ! -path "*/symbolic/*" -name "*.$ext" 2>/dev/null | sort -r;',
      '    done;',
      '  done;',
      'done;',
      'for ext in svg png; do find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null | sort -r; done'
    ].join(' ')
  }

  function indexIconLine(path) {
    var value = String(path || "").trim()
    if (value.length === 0) return
    var slash = value.lastIndexOf("/")
    var file = slash >= 0 ? value.slice(slash + 1) : value
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file
    if (name.length > 0 && root.pendingIconIndex[name] === undefined)
      root.pendingIconIndex[name] = value
  }

  function hiddenEntryScanCommand() {
    var desktop = [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")].filter(function(v) { return String(v || "").length > 0 }).join(":")
    var script = root.omarchyPath + "/shell/services/hidden-entries.sh"
    return Util.shellQuote(script) + " " + Util.shellQuote(desktop)
  }

  function toplevelCount() {
    try { return ToplevelManager.toplevels.values.length } catch (e) { return 0 }
  }

  function beginLaunchFeedback(name) {
    root.launchSerial++
    root.launchToplevelCount = root.toplevelCount()
    root.launchActiveToplevel = ToplevelManager.activeToplevel
    root.launchOsdMessage = "Launching " + String(name || "application") + "…"
    launchDelay.restart()
    launchTimeout.restart()
  }

  function closeLaunchFeedback(serial) {
    if (serial !== root.launchSerial) return
    launchDelay.stop()
    launchTimeout.stop()
    if (root.launchOsdOpen) {
      Quickshell.execDetached(["omarchy-shell", "osd", "close"])
      root.launchOsdOpen = false
    }
  }

  function maybeFinishLaunchFeedback() {
    if (!launchDelay.running && !launchTimeout.running && !root.launchOsdOpen) return
    if (root.toplevelCount() <= root.launchToplevelCount && ToplevelManager.activeToplevel === root.launchActiveToplevel) return
    root.closeLaunchFeedback(root.launchSerial)
  }

  QtObject {
    id: hiddenEntryOutput
    property string text: ""
  }

  // Both scans must run in non-login shells. A login shell sources the user's
  // profile, and tools like mise touch ~/.local/share on activation — a
  // directory the desktop-entry watcher monitors — so every scan would
  // trigger the next one, pinning a core at idle.
  Process {
    id: hiddenEntryScan
    command: ["bash", "-c", root.hiddenEntryScanCommand()]
    stdout: SplitParser { onRead: function(line) { hiddenEntryOutput.text += line + "\n" } }
    onStarted: hiddenEntryOutput.text = ""
    onExited: root.loadDesktopHiddenEntries(hiddenEntryOutput.text)
  }

  Process {
    id: iconIndexScan
    command: ["bash", "-c", root.iconIndexScanCommand()]
    stdout: SplitParser { onRead: function(line) { root.indexIconLine(line) } }
    onStarted: root.pendingIconIndex = ({})
    // Swapping the property re-evaluates every iconSource() binding, so
    // newly found icons appear without rebuilding the list.
    onExited: root.iconIndex = root.pendingIconIndex
  }

  // Coalesces bursts of app-list changes (a package install touches many
  // entries) into a single rescan.
  Timer {
    id: iconIndexDebounce
    interval: 750
    onTriggered: if (!iconIndexScan.running) iconIndexScan.running = true
  }

  FileView {
    path: root.omarchyPath + "/default/omarchy/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfiguredHides(text())
    onFileChanged: root.loadConfiguredHides(text())
    onLoadFailed: root.loadConfiguredHides("")
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.maybeFinishLaunchFeedback() }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.maybeFinishLaunchFeedback() }
  }

  Timer {
    id: launchDelay
    interval: 2000
    onTriggered: {
      if (root.toplevelCount() > root.launchToplevelCount || ToplevelManager.activeToplevel !== root.launchActiveToplevel) return
      root.launchOsdOpen = true
      Quickshell.execDetached(["omarchy-shell", "osd", "show", JSON.stringify({ icon: "󱓞", message: root.launchOsdMessage, duration: 0 })])
    }
  }

  Timer {
    id: launchTimeout
    interval: 15000
    onTriggered: root.closeLaunchFeedback(root.launchSerial)
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      hiddenEntryScan.running = true
      iconIndexDebounce.restart()
      root.appsChanged()
    }
  }

  Component.onCompleted: {
    hiddenEntryScan.running = true
    iconIndexScan.running = true
  }
}
