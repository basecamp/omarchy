# Omarchy bar

This is the Quickshell implementation of the Omarchy status bar. It is
shipped as a first-party plugin of [`omarchy-shell`](../../README.md), the
long-running shell host. The bar is mounted at startup and lives inside
the shell for its whole session.

- `manifest.json` declares the plugin (`id: omarchy.bar`, `kind: bar`, `activation: persistent`) and points at `Bar.qml` as the entry point.
- `Bar.qml` is Omarchy-owned bar engine code, loaded by the omarchy-shell host. Users should not edit it directly.
- `widgets/` holds first-party widgets — modular, interactive components shipped with Omarchy.
- `common/` holds shared QML helpers (buttons, sliders, popup cards).
- The bar receives its config from the host shell as a `barConfig` property; the host loads it from `~/.config/omarchy/shell.json` (or `shell-defaults.json` when the user has no file).
- `omarchy-style-bar-position` updates only the user shell.json file.

## Customizing

The bar config lives under the `bar:` key of [`~/.config/omarchy/shell.json`](../../README.md#shelljson-shape). Out of the box the shell uses [`shell-defaults.json`](../../shell-defaults.json). Once you customize anything via `omarchy launch bar-settings` or by editing shell.json directly, your file is canonical — there is no deep-merge.

Launch the visual editor with `omarchy launch bar-settings` (or run `omarchy-launch-bar-settings`) to reorder widgets, add/remove them, and tweak per-widget options without editing JSON by hand.

Example `shell.json` (bar subtree only shown):

```json
{
  "version": 1,
  "bar": {
    "position": "top",
    "centerAnchor": "calendar",
    "layout": {
      "left": [
        { "id": "omarchy" },
        { "id": "spacer", "size": 12 },
        { "id": "workspaces" }
      ],
      "center": [
        { "id": "media" },
        { "id": "calendar", "format": "HH:mm" }
      ],
      "right": [
        { "id": "systemStats" },
        { "id": "audioPanel" },
        { "id": "battery" },
        { "id": "controlCenter" }
      ]
    }
  }
}
```

`centerAnchor` pins one center module to the exact horizontal/vertical center and flanks others around it. Set to an empty string to disable anchoring (the center list is centered as a group).

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
| `systemStats` | Inline CPU + memory sparklines, popup with detail | left = popup · right = terminal |
| `weatherFlyout` | Weather icon + popup with forecast | left = popup · right = full notification |
| `idleInhibitor` | Coffee-cup that toggles `omarchy-toggle-idle` | left = toggle |
| `microphone` | Mic icon + scroll volume | left = mute toggle · middle = audio TUI · scroll = source volume |

### Built-in legacy modules (in `shell.qml`)

`omarchy`, `workspaces`, `clock`, `weather`, `update`, `voxtype`, `screenRecording`, `idle`, `notifications`, `tray`, `bluetooth`, `network`, `audio`, `cpu`, `battery`.

These remain available — set them in `layout` to use them instead of the richer widget versions.

## Orientation

All widgets work in `top`, `bottom`, `left`, and `right` positions. Popups anchor on the side opposite the bar edge, sliding into the workspace. Vertical bars use 28px width; widgets that show text fall back to compact icon-only forms (e.g. `media` hides its scrolling label).

## Custom user modules

The schema accepts arbitrary module ids that you provide. Set `type` to `command` for shell-driven output or `qml` for a custom QML widget. Both still go under `bar.layout.<section>` in `shell.json`.

Command module:

```json
{
  "version": 1,
  "bar": {
    "layout": {
      "right": [
        { "id": "tray" },
        { "id": "vpn", "type": "command", "exec": "~/.config/omarchy/bar/scripts/vpn-status", "interval": 5, "tooltip": "VPN", "onClick": "nm-connection-editor" },
        { "id": "audioPanel" }
      ]
    }
  }
}
```

The command may print plain text or Waybar-style JSON, for example:

```json
{"text":"󰌆","tooltip":"Work VPN","class":"active"}
```

QML module:

```json
{
  "version": 1,
  "bar": {
    "layout": {
      "right": [
        { "id": "gpu", "type": "qml" },
        { "id": "audioPanel" }
      ]
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

First-party widgets live in `widgets/<name>.qml` and are picked up by the
shell's `BarWidgetRegistry` at startup; reference one by `id` in any
layout list.

Third-party widgets ship as separate plugins under
`~/.config/omarchy/plugins/<plugin-id>/` with their own `manifest.json`
declaring `kinds: ["bar-widget"]` and a `barWidget` entry point. See
[../../README.md](../../README.md) for the manifest schema and the
Plugin Manager tab in `omarchy launch bar-settings` for enable/disable
controls.
