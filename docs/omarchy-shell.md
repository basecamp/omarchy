# omarchy-shell

A single long-running [Quickshell](https://quickshell.org/) instance
that hosts the Omarchy desktop. The bar, panels, overlays, menus, and
services all run inside as plugins. IPC is the canonical way for CLIs
to talk to a running shell — `omarchy-shell-ipc` auto-starts it on
first call.

## Plugin manifest

```json
{
  "schemaVersion": 1,
  "id": "my.org.cool-clock",
  "name": "Cool clock",
  "version": "1.0.0",
  "author": "You",
  "description": "A clock that does cool things",
  "kinds": ["bar-widget"],
  "activation": "on-demand",
  "entryPoints": { "barWidget": "Widget.qml" }
}
```

`kinds` (a manifest may declare more than one):

| Kind         | What it is                                  |
|--------------|---------------------------------------------|
| `bar-widget` | Component the bar drops into a section      |
| `panel`      | Floating window (e.g. bar settings)         |
| `overlay`    | Fullscreen overlay (e.g. background picker) |
| `menu`       | Summoned menu surface                       |
| `service`    | Headless singleton, no UI                   |

`activation` is `persistent` (loaded at startup) or `on-demand`
(loaded by `shell summon`, unloaded by `shell hide`). On-demand
plugins can set `keepLoaded: true` to survive between summons.

Full schema: [`shell/services/PluginRegistry.qml`](../shell/services/PluginRegistry.qml).

## Installing a third-party plugin

1. Drop into `~/.config/omarchy/plugins/<id>/` with a `manifest.json`
   plus the QML referenced from `entryPoints`.
2. `omarchy-shell-ipc shell rescanPlugins`
3. `omarchy-shell-ipc shell setPluginEnabled <id> true`
4. Bar widgets also need adding to a section via bar settings.

## IPC

The shell exposes a `shell` target plus extra targets registered by
individual plugins (`bar`, `image-selector`, …).

| Method                                | Effect                          |
|---------------------------------------|---------------------------------|
| `ping`                                | health check                    |
| `summon <id> <payloadJson>`           | load + open a plugin            |
| `hide <id>`                           | close a previously-summoned     |
| `toggle <id> <payloadJson>`           | summon if closed, hide if open  |
| `rescanPlugins`                       | re-walk plugin dirs             |
| `setPluginEnabled <id> <"true"\|…>`   | flip enabled bit                |
| `listPlugins`                         | JSON of every discovered plugin |

`setPluginEnabled` takes a string; only literal `"true"` enables.

## shell.json

```json
{
  "version": 1,
  "bar": {
    "position": "top",
    "transparent": false,
    "centerAnchor": "calendar",
    "fontFamily": "JetBrainsMono Nerd Font",
    "layout": {
      "left":   [ { "id": "omarchy" } ],
      "center": [ { "id": "calendar", "format": "HH:mm" } ],
      "right":  [ { "id": "audioPanel" } ]
    }
  },
  "plugins": [
    { "id": "omarchy.settings" }
  ]
}
```

Rules:

1. Every plugin instance is one entry — `bar.layout.<section>` for
   bar widgets, `plugins[]` for everything else.
2. Settings are inline on the entry. No `config:` sub-object, no
   merge layers.
3. Enabled ⇔ present.
4. `allowMultiple: true` in the manifest permits multiple instances.
5. `version: 1` is required.

`shell-defaults.json` describes the fresh-install state. When no
user `shell.json` exists, defaults are used verbatim. Once the user
customizes, `shell.json` is canonical — there is no deep-merge.

## Custom bar modules

If a full plugin is overkill, declare a one-off module inline in
`bar.layout.<section>`:

```json
{ "id": "vpn", "type": "command", "exec": "~/.config/omarchy/bar/scripts/vpn-status",
  "interval": 5, "tooltip": "VPN", "onClick": "nm-connection-editor" }
```

Output is plain text or Waybar-style JSON (`{ "text": ..., "tooltip": ..., "class": ... }`).

For a custom QML widget:

```json
{ "id": "gpu", "type": "qml" }
```

Then `~/.config/omarchy/bar/modules/gpu.qml` (or set `source` to point
elsewhere). The module is an `Item` and receives `bar`, `moduleName`,
`settings` properties. `bar` exposes `foreground` / `background` /
`urgent` / `fontFamily` / `position` / `vertical` / `barSize`, plus
`run(cmd)`, `shellQuote(v)`, `showTooltip(t, s)` / `hideTooltip(t)`,
`requestPopout(o)` / `releasePopout(o)`.
