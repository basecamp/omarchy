# Omarchy bar

This is the Quickshell implementation of the Omarchy status bar.

- `shell.qml` is Omarchy-owned bar engine code. Users should not edit it directly.
- `bar-defaults.json` is the Omarchy-owned default layout and module settings.
- `widgets/` holds first-party widgets — modular, interactive components shipped with Omarchy.
- `common/` holds shared QML helpers (buttons, sliders, popup cards).
- User overrides live in `~/.config/omarchy/bar.json` and are merged over defaults at runtime.
- `omarchy-style-bar-position` updates only the user override file.

Example user override:

```json
{
  "position": "top",
  "layout": {
    "left": ["omarchy", "workspacesPro"],
    "center": ["media", "calendar", "weatherFlyout"],
    "right": ["systemStats", "notificationCenter", "bluetoothPanel", "networkPanel", "audioPanel", "brightness", "powerProfile", "battery", "powerMenu"]
  },
  "centerAnchor": "calendar"
}
```

`centerAnchor` pins one center module to the exact horizontal/vertical center and flanks others around it.

## Module catalogue

### First-party interactive widgets (in `widgets/`)

| Name | What it does | Interactions |
|---|---|---|
| `media` | MPRIS now-playing — scrolling track + artist, cover-art popup | left = play/pause · middle = next · scroll = prev/next · right = popup |
| `audioPanel` | Volume icon + popup with master slider, output-device picker, per-app mixer | left = popup · right = mute · middle = audio TUI · scroll = volume |
| `networkPanel` | Wi-Fi/Ethernet icon + popup with Wi-Fi scan, signal, connect | left = popup · right = nmtui |
| `bluetoothPanel` | Bluetooth icon + popup with device list, connect/disconnect, battery | left = popup · right = toggle radio · middle = bluetoothctl TUI |
| `calendar` | Clock + popup with month-grid calendar | left = popup · right = tz selector |
| `notificationCenter` | Bell with badge + popup with recent notifications, DND toggle | left = popup · right = toggle DND |
| `brightness` | Brightness slider + scroll | scroll = adjust · left = popup · middle = reset to 80% |
| `powerProfile` | Current power profile + popup picker | left = popup |
| `systemStats` | Inline CPU + memory sparklines, popup with detail | left = popup · right = terminal |
| `weatherFlyout` | Weather icon + popup with forecast | left = popup · right = full notification |
| `workspacesPro` | Animated focus indicator that slides between workspaces | left = focus · right = move window · scroll = cycle |
| `powerMenu` | Power icon → popup with lock/suspend/log out/reboot/shutdown | left = popup |
| `idleInhibitor` | Coffee-cup that toggles `omarchy-toggle-idle` | left = toggle |
| `microphone` | Mic icon + scroll volume | left = mute toggle · middle = audio TUI · scroll = source volume |

### Built-in legacy modules (in `shell.qml`)

`omarchy`, `workspaces`, `clock`, `weather`, `update`, `voxtype`, `screenRecording`, `idle`, `notifications`, `tray`, `bluetooth`, `network`, `audio`, `cpu`, `battery`.

These remain available — set them in `layout` to use them instead of the richer widget versions.

## Orientation

All widgets work in `top`, `bottom`, `left`, and `right` positions. Popups anchor on the side opposite the bar edge, sliding into the workspace. Vertical bars use 28px width; widgets that show text fall back to compact icon-only forms (e.g. `media` hides its scrolling label).

## Custom user modules

Add a module name to a layout list, then define it under `modules` in `~/.config/omarchy/bar.json`.

For simple text/JSON output, use a command module:

```json
{
  "layout": {
    "right": ["tray", "vpn", "audioPanel", "cpu"]
  },
  "modules": {
    "vpn": {
      "type": "command",
      "exec": "~/.config/omarchy/bar/scripts/vpn-status",
      "interval": 5,
      "tooltip": "VPN",
      "onClick": "nm-connection-editor"
    }
  }
}
```

The command may print plain text or Waybar-style JSON, for example:

```json
{"text":"󰌆","tooltip":"Work VPN","class":"active"}
```

For advanced custom UI, use QML:

```json
{
  "layout": {
    "right": ["gpu", "audioPanel", "cpu"]
  },
  "modules": {
    "gpu": {
      "type": "qml"
    }
  }
}
```

Then create `~/.config/omarchy/bar/modules/gpu.qml`. If you want to store it elsewhere, add a `source` path.

Custom QML modules should be an `Item` with `implicitWidth` and `implicitHeight`. They may optionally define these properties, which the bar fills after loading:

```qml
import QtQuick

Item {
  property var bar
  property string moduleName
  property var settings

  implicitWidth: 28
  implicitHeight: bar ? bar.barSize : 26

  Text {
    anchors.centerIn: parent
    text: "GPU"
    color: bar ? bar.foreground : "white"
    font.family: bar ? bar.fontFamily : "monospace"
    font.pixelSize: 12
  }

  MouseArea {
    anchors.fill: parent
    onClicked: if (bar) bar.run("omarchy-launch-or-focus-tui btop")
  }
}
```

## Bar properties available to widgets

Widgets receive `bar` (the shell root), `moduleName` (string), and `settings` (object) injected at load time. The bar exposes:

- `bar.foreground`, `bar.background`, `bar.urgent` — theme colors (live-updated)
- `bar.fontFamily` — current monospace family
- `bar.position` — `"top" | "bottom" | "left" | "right"`
- `bar.vertical` — boolean shortcut
- `bar.barSize` — 26 horizontal / 28 vertical
- `bar.run(command)` — fire-and-forget bash exec
- `bar.shellQuote(value)` — safe shell-quote a string
- `bar.showTooltip(target, text)` / `bar.hideTooltip(target)` — shared tooltip popup
- `bar.requestPopout(owner)` / `bar.releasePopout(owner)` — one-popup-at-a-time coordinator

Drop new widgets into `widgets/<name>.qml`, add the name to the `firstPartyWidgets` registry in `shell.qml`, and reference it by name in any layout list.
