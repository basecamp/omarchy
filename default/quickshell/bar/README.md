# Omarchy bar

This is the Quickshell implementation of the Omarchy status bar.

- `shell.qml` is Omarchy-owned bar engine code. Users should not edit it directly.
- `bar-defaults.json` is the Omarchy-owned default layout and module settings.
- User overrides live in `~/.config/omarchy/bar.json` and are merged over defaults at runtime.
- `omarchy-style-bar-position` updates only the user override file.
- Wi-Fi/LAN state is polled from the active route and NetworkManager so the QML can mirror Waybar's network icons.
- Tooltips use a small Quickshell `PopupWindow`, not Qt Quick Controls' clipped default tooltip.

Example user override:

```json
{
  "position": "right",
  "layout": {
    "left": ["omarchy", "workspaces"],
    "center": ["clock", "weather", "update"],
    "right": ["tray", "bluetooth", "network", "audio", "cpu", "battery"]
  },
  "modules": {
    "clock": {
      "format": "HH:mm",
      "formatAlt": "dd MMMM 'W'ww yyyy",
      "verticalFormat": "HH\n—\nmm"
    }
  }
}
```

`centerAnchor` defaults to `clock`. When the anchor module is present in the `center` list, it is pinned to the exact center of the bar and modules before/after it flank that anchor. If the anchor is not in the center list, the center list is centered as a group.

Available built-in modules: `omarchy`, `workspaces`, `clock`, `weather`, `update`, `voxtype`, `screenRecording`, `idle`, `notifications`, `tray`, `bluetooth`, `network`, `audio`, `cpu`, `battery`.

## Custom modules

Add a module name to a layout list, then define it under `modules` in `~/.config/omarchy/bar.json`.

For simple text/JSON output, use a command module:

```json
{
  "layout": {
    "right": ["tray", "vpn", "audio", "cpu"]
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
    "right": ["gpu", "audio", "cpu"]
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
