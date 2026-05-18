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
    { "id": "community.weather-extra" }
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

## Theme tokens

Themes ship colors in `themes/<name>/colors.toml` and surface roles +
sizing in `themes/<name>/shell.toml`. Defaults are generated from
`default/themed/shell.toml.tpl`; a theme may also drop a hand-written
`shell.toml` next to its `colors.toml` to override individual keys.

The shell exposes these tokens to QML via two singletons in
`qs.Commons`:

- `Color` — palette (`foreground`, `background`, `accent`, `urgent`)
  and per-surface roles (`Color.bar.*`, `Color.popups.*`,
  `Color.notifications.*`, `Color.menu.*`, `Color.imagePicker.*`).
- `Style` — structural tokens (`cornerRadius`, focus affordances),
  the type scale (`Style.font.*`), and bar dimensions
  (`Style.bar.sizeHorizontal` / `Style.bar.sizeVertical`).

### Typography

`[font] base-size` is the rem root for the scale. Every
`Style.font.<token>` derives from it via a fixed multiplier, so
bumping `base-size` rescales the whole shell proportionally:

| Token                 | Multiplier | Default |
|-----------------------|------------|---------|
| `Style.font.caption`      | 0.833 | 10 |
| `Style.font.bodySmall`    | 0.917 | 11 |
| `Style.font.body`         | 1.0   | 12 |
| `Style.font.subtitle`     | 1.083 | 13 |
| `Style.font.title`        | 1.167 | 14 |
| `Style.font.heading`      | 1.333 | 16 |
| `Style.font.display`      | 2.0   | 24 |
| `Style.font.displayLarge` | 2.333 | 28 |
| `Style.font.iconSmall`    | bodySmall | 11 |
| `Style.font.icon`         | title     | 14 |
| `Style.font.iconLarge`    | 1.5       | 18 |

A theme can either scale everything by tweaking `base-size`:

```toml
[font]
base-size = 13   # roomier
```

…or pin individual tokens for stylistic emphasis without affecting
the rest of the scale:

```toml
[font]
base-size = 12
heading       = 20
display-large = 36
```

Recognized override keys: `base-size`, `caption`, `body-small`,
`body`, `subtitle`, `title`, `heading`, `display`, `display-large`,
`icon-small`, `icon`, `icon-large`.

`base-size` is clamped to **11..13** because row heights and the bar
cross-axis size are fixed; per-token overrides aren't clamped. The
shell font family is the fontconfig `monospace` alias — themes don't
set it, the user does via `omarchy font set <name>`.

### Bar size

`[bar] size-horizontal` / `size-vertical` set the cross-axis dimension
of top/bottom and left/right bars respectively (in px):

```toml
[bar]
size-horizontal = 26   # top/bottom bar height
size-vertical   = 28   # left/right bar width
```

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
