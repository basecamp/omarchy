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
  "entryPoints": { "barWidget": "Widget.qml" }
}
```

`kinds` (a manifest may declare more than one):

| Kind         | What it is                                  |
|--------------|---------------------------------------------|
| `bar-widget` | Component the active bar drops into a section |
| `bar`        | Full bar option that can replace `omarchy.bar` |
| `panel`      | Floating window (e.g. OSD)                     |
| `overlay`    | Fullscreen overlay (e.g. background picker)    |
| `menu`       | Summoned menu surface                          |
| `service`    | Headless singleton, no UI                      |

Only one full bar option is active at a time. The built-in `omarchy.bar` is
used when `bar.id` is omitted or when a selected third-party bar cannot load.
Panels, overlays, and menus are loaded when summoned. Plugins can set
`keepLoaded: true` to survive between summons. First-party services are
loaded at startup.

Full schema: [`shell/services/PluginRegistry.qml`](../shell/services/PluginRegistry.qml).

## Installing a third-party plugin

A plugin is a **git repo** with a `manifest.json` at its root. Adding one
clones it straight into `~/.config/omarchy/plugins/<id>/`; updating is a
fast-forward pull:

```bash
omarchy plugin add https://github.com/acme/omarchy-weather.git
omarchy plugin update --all          # fetches, shows a diff, fast-forwards
omarchy plugin remove acme.weather
```

Plugins run as **unsandboxed code** inside `omarchy-shell`. Adding warns you
before cloning, plugins land disabled so you can review the code before
`omarchy plugin enable`, and updates show a diff before touching anything.
Commands prompt when run bare in a terminal and run unattended when given
arguments — add `--yes` to skip every prompt (the path for scripts and agents).

You can still install by hand: drop a plugin into
`~/.config/omarchy/plugins/<id>/`, run `omarchy plugin rescan`, then
`omarchy plugin enable <id>` (bar widgets also need `omarchy bar add <id>`;
full bar replacements are selected with `omarchy bar use <id>`).
The lower-level IPC methods remain available through `omarchy-shell shell ...`.

## IPC

The shell exposes a `shell` target plus extra targets registered by
individual plugins (`bar`, `image-selector`, …).

| Method                                | Effect                          |
|---------------------------------------|---------------------------------|
| `ping`                                | health check                    |
| `summon <id> <payloadJson>`           | load + open a plugin            |
| `hide <id>`                           | close a previously-summoned     |
| `toggle <id> <payloadJson>`           | summon if closed, hide if open  |
| `call <id> <method> <arg>`            | call an already-loaded plugin   |
| `rescanPlugins`                       | re-walk plugin dirs and hot-reload plugin code |
| `reloadConfig`                        | reload shell.json               |
| `setPluginEnabled <id> <"true"\|…>`   | flip enabled bit (`ok` / `unknown`) |
| `listPlugins`                         | JSON of every discovered plugin |

`setPluginEnabled` takes a string; only literal `"true"` enables.

## shell.json

```json
{
  "version": 1,
  "idle": {
    "screensaver": 150,
    "lock": 300
  },
  "bar": {
    "id": "omarchy.bar",
    "position": "top",
    "transparent": false,
    "centerAnchor": "calendar",
    "fontFamily": "JetBrainsMono Nerd Font",
    "layout": {
      "left":   [ { "id": "omarchy.menu" } ],
      "center": [ { "id": "omarchy.clock", "format": "HH:mm" } ],
      "right":  [ { "id": "omarchy.audio" } ]
    }
  },
  "plugins": [
    { "id": "community.weather-extra" }
  ]
}
```

Rules:

1. The active bar option is `bar.id`. Omit it or set it to `omarchy.bar` for
   the built-in bar; set it to a plugin whose manifest declares `kind: "bar"`
   to replace the full bar.
2. Every plugin instance is one entry — `bar.layout.<section>` for
   bar widgets, `plugins[]` for everything else.
3. Settings are inline on the entry. No `config:` sub-object, no
   merge layers.
4. Built-in bar widget ids are namespaced (`omarchy.clock`, `omarchy.audio`, …).
   The migration rewrites older ids such as `Clock` and `AudioPanel` forward.
5. Third-party enabled ⇔ present; for full bar options that means `bar.id`.
   First-party non-bar plugins are always enabled.
6. `allowMultiple: true` in the manifest permits multiple instances.
7. `idle.screensaver` and `idle.lock` are seconds since user idle began.
8. `version: 1` is required.

`config/omarchy/shell.json` describes the fresh-install state. When no
user `shell.json` exists, defaults are used verbatim. Once the user
customizes, `shell.json` is canonical — there is no deep-merge.

## Theme tokens

See [`theming.md`](theming.md) for the full theme/template workflow,
including generated `*.tpl` files, gradient helpers, and shell border syntax.

Themes ship colors in `themes/<name>/colors.toml` and surface roles +
sizing in `themes/<name>/shell.toml`. Defaults are generated from
`default/themed/shell.toml.tpl`; a theme may also drop a hand-written
`shell.toml` next to its `colors.toml` to replace the generated file.

`colors.toml` uses `fg` and `bg` for the foundational text/background
palette. The shell exposes those to QML as `Color.foreground` and
`Color.background`, so shell roles still use the readable role names.

The shell exposes these tokens to QML via two singletons in
`qs.Commons`:

- `Color` — palette (`foreground`, `background`, `accent`, `urgent`)
  and per-surface roles (`Color.bar.*`, `Color.popups.*`,
  `Color.tooltip.*`, `Color.notifications.*`, `Color.menu.*`,
  `Color.launcher.*`, `Color.imagePicker.*`, `Color.polkit.*`,
  `Color.lock.*`). Clipboard and emojis share `Color.menu.*`.
- `Style` — structural tokens (`cornerRadius`), shared interactive
  state tokens/helpers, spacing (`Style.spacing.*` / `Style.space(px)`),
  the type scale (`Style.font.*`), and bar dimensions
  (`Style.bar.sizeHorizontal` / `Style.bar.sizeVertical`).
- `Border` — border-spec helpers for QML surfaces. Use with
  `BorderSurface` from `qs.Ui` when a border should honor shell theme
  gradients or per-side widths. `Color.<section>.border` is only the
  flat-color fallback for code that cannot render a real border.

### Interactive states

`[controls]` standardizes reusable control chrome (buttons, dropdowns,
tab strips, etc.) around four states: `normal`, `hover-cursor`, `focus`,
and `selected`. State colors and border tokens accept palette roles
(`foreground`, `accent`, `urgent`, `background`) or hex strings; border
values may also be gradients. Fill alpha applies to the state color;
border alpha applies to the state's border token.

Surfaces like `[menu]`, `[launcher]`, and `[image-picker]` define
their own `selected-*` tokens and do **not** inherit from `[controls]`.
`[controls]` only governs the shared button/dropdown chrome.

| State | Color token | Fill alpha | Border token | Border width | Border alpha |
|-------|-------------|------------|--------------|--------------|--------------|
| Normal idle chrome | `normal-color` | `normal-fill-alpha` | `normal-border` | `normal-border-width` | `normal-border-alpha` |
| Hover / keyboard cursor | `hover-cursor-color` | `hover-cursor-fill-alpha` | `hover-cursor-border` | `hover-cursor-border-width` | `hover-cursor-border-alpha` |
| Qt activeFocus | `focus-color` | `focus-fill-alpha` | `focus-border` | `focus-border-width` | `focus-border-alpha` |
| Persistent selected/current | `selected-color` | `selected-fill-alpha` | `selected-border` | `selected-border-width` | `selected-border-alpha` |

The template ships `focus-*` adjacent to `hover-cursor-*` with the same
values so mouse hover, keyboard cursor, and tab focus read identically.
Themes that want focus to stand out override the `focus-*` keys.

Border widths are the theme-level on/off switches for state borders; set
a width to `0` to keep the fill while removing that state border. The
default keeps selected borders off globally (`selected-border-width =
0`); explicitly bordered controls keep their normal border when selected.

```toml
[controls]
# Accent-tinted cursor/focus, foreground-tinted selected state.
hover-cursor-color = "accent"
focus-color        = "accent"
selected-color     = "foreground"
focus-border       = "rgba(33ccffee) rgba(00ff99ee) 45deg"

# Keep selected fills but remove selected-state borders.
selected-border-width = 0
```

Momentary fills use `pressed-fill-alpha` for button press feedback and
`selection-fill-alpha` for text selection. Themes may also provide
`pressed-color` or `selection-color`; they fall back to hover-cursor and
foreground respectively.

The section was previously named `[style]`. Hand-written theme
`shell.toml` files using the old name still apply — the parser accepts
both `[controls]` and `[style]`.

### Spacing

`[spacing] scale` multiplies the shell's shared margins, gaps, padding,
control sizes, and panel dimensions. The default is `1.0`; values above
`1.0` create more breathing room while values below `1.0` make controls
dense. By default `scale-with-font = true`, so increasing `[font]
base-size` also scales buttons, popup widths, row heights, and panel
padding proportionally.

```toml
[spacing]
scale = 1.15
scale-with-font = true  # grow controls and panels with [font] base-size
```

QML components should prefer semantic tokens where possible:

| Token | Default use |
|-------|-------------|
| `Style.spacing.controlPaddingX` / `controlPaddingY` | Button and tooltip padding |
| `Style.spacing.inputPaddingY` | Text-field vertical padding |
| `Style.spacing.controlHeight` / `popupRowHeight` | Dropdown and number-field row heights |
| `Style.spacing.dropdownWidth` / `searchableDropdownWidth` / `numberFieldWidth` | Default field widths |
| `Style.spacing.searchablePopupMinHeight` | Minimum searchable dropdown popup height |
| `Style.spacing.controlGap` | Gap between icon and label inside controls |
| `Style.spacing.labelGap` | Label-to-control and compact list gaps |
| `Style.spacing.rowGap` / `rowPaddingX` | Form rows and list row content |
| `Style.spacing.panelGap` / `panelPadding` | Panel section spacing and interior padding |
| `Style.spacing.popupPadding` | Popout interior padding |

Popout placement deliberately follows Hyprland's `general:gaps_out`
(`Style.gapsOut`) so panels align with tiled windows. Use a theme's
`hyprland.lua` to change that outer alignment; `[spacing]` controls the
interior breathing room.

For one-off proportional constants, use `Style.space(px)` to preserve the
old default at scale `1.0` and `base-size = 12` while still responding to
the theme scale and font scale. Use `Style.spaceReal(px)` only for
fractional geometry that should not be rounded, such as bar widget text
margins. Themes can override any semantic token directly in `[spacing]`,
e.g.:

```toml
[spacing]
scale = 1.0
panel-padding = 22
row-gap = 10
```

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

`base-size` has no upper clamp; the shell only floors it at **1px** to
avoid nonsensical zero/negative sizes. Per-token overrides aren't clamped
either. The shell font family is the fontconfig `monospace` alias —
themes don't set it, the user does via `omarchy font set <name>`.

### Bar size

`[bar] size-horizontal` / `size-vertical` set the cross-axis dimension
of top/bottom and left/right bars respectively, measured at the default
12px font base. By default `scale-with-font = true`, so increasing
`[font] base-size` also increases the bar's cross-axis size:

```toml
[bar]
scale-with-font = true
size-horizontal = 26   # top/bottom bar height at base-size 12
size-vertical   = 28   # left/right bar width at base-size 12
```

Set `scale-with-font = false` to keep those bar sizes as fixed pixels.

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
