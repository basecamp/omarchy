# Omarchy theming

Omarchy themes live under `themes/<name>/` in the source tree (installed at
`/usr/share/omarchy/themes/<name>/`), with optional user themes under
`~/.config/omarchy/themes/<name>/`. A theme normally starts with a
`colors.toml`; Omarchy generates the active theme files from
`default/themed/*.tpl` when `omarchy-theme-set <name>` runs.

## Theme activation flow

`omarchy-theme-set <name>` builds a clean staging directory at
`~/.local/state/omarchy/current/next-theme`:

1. Copy the first-party theme from `themes/<name>/`.
2. Overlay any user theme files from `~/.config/omarchy/themes/<name>/`.
3. If needed, generate `colors.toml` from `alacritty.toml`.
4. Run `omarchy-theme-set-templates` to render templates into the staging
   theme.
5. Move the staging theme into `~/.local/state/omarchy/current/theme`, write
   `~/.local/state/omarchy/current/theme.name`, and notify the running shell.

Template rendering only happens when the staged theme has `colors.toml`.
Existing files are never overwritten by a template, so a hand-written
`themes/<name>/shell.toml` or `hyprland.lua` wins over
`default/themed/shell.toml.tpl` or `hyprland.lua.tpl`.

User templates in `~/.config/omarchy/themed/*.tpl` are processed before the
built-in templates. If a user template has the same output filename as a
built-in template, the built-in output is skipped.

## `colors.toml`

`colors.toml` provides the palette keys used by templates. Common keys are:

```toml
foreground = "#a9b1d6"
background = "#1a1b26"
accent     = "#7aa2f7"
color1     = "#f7768e"
color4     = "#7aa2f7"
```

Any key can be referenced from a template with `{{ key }}`. The shell also
uses a few semantic palette keys directly:

- `foreground`
- `background`
- `accent` — preferred when present; otherwise some places fall back to
  `color4`
- `urgent` / `color1`

## Template placeholders

Templates are plain files ending in `.tpl`. `omarchy-theme-set-templates`
replaces placeholders with values from `colors.toml`.

### Color placeholders

For a color key such as `accent = "#7aa2f7"`:

| Placeholder | Output |
|-------------|--------|
| `{{ accent }}` | `#7aa2f7` |
| `{{ accent_strip }}` | `7aa2f7` |
| `{{ accent_rgb }}` | `122,162,247` |

### Color mixing

`mix`, `mix_strip`, and `mix_rgb` blend two hex colors by a fraction or
percentage:

```text
{{ mix background foreground 15% }}
{{ mix_strip background accent 0.35 }}
{{ mix_rgb color0 color7 50 }}
```

### Gradient helpers

Some theme keys can be either a solid color or a Hyprland-style gradient:

```toml
hyprland_active_border = "rgba(33ccffee) rgba(00ff99ee) 45deg"
```

Gradient helper placeholders understand those values:

| Helper | Use | Example output |
|--------|-----|----------------|
| `{{ hypr_gradient hyprland_active_border accent }}` | Hyprland Lua config | `{ colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }` |
| `{{ shell_gradient hyprland_active_border accent }}` | shell border tokens | `rgba(33ccffee) rgba(00ff99ee) 45deg` |
| `{{ gradient_start hyprland_active_border accent }}` | flat-color-only consumers | `#33ccff` |

The second argument is a fallback. For example,
`{{ shell_gradient hyprland_active_border accent }}` means: use
`hyprland_active_border` if the theme defines it; otherwise use `accent`.
The helper does not choose the first color unless you use `gradient_start`.

## `shell.toml`

`shell.toml` contains shell surface roles, control states, spacing, typography,
and bar sizing. The default generated file comes from
`default/themed/shell.toml.tpl`.

Themes can override the entire generated file by shipping `shell.toml`, or just
one section by shipping `shell.<section>.toml`. For example,
`shell.lock.toml` replaces only the `[lock]` section after the default
`shell.toml` has been generated:

```toml
text        = "#ffffff"
placeholder = "#ffffff"
border      = "#ffffff"
```

The filename decides the target section, so the `[lock]` header is optional.

The running shell reads `shell.toml` into two QML singletons:

- `Color` for palette and surface roles like `Color.menu.border`.
- `Style` for controls, spacing, font scale, corner radius, and bar sizing.

### Borders

Shell border tokens accept either a solid color or a gradient in the same key:

```toml
[notifications]
border = "#7aa2f7"
```

or:

```toml
[notifications]
border = "rgba(33ccffee) rgba(00ff99ee) 45deg"
```

Do not add a separate `border-gradient` key for new themes. The parser still
accepts `border-gradient` and `*-border-gradient` for compatibility with older
configs, but the canonical form is the border key itself.

Border alphas apply to solid borders and to every gradient stop:

```toml
[notifications]
border       = "rgba(33ccffee) rgba(00ff99ee) 45deg"
border-alpha = 0.8
```

If a color stop already includes alpha, the stop alpha and `border-alpha` are
combined.

### Border widths

Border widths accept CSS-style lists:

```toml
border-width = 2          # all sides
border-width = "2 4"      # top/bottom, right/left
border-width = "2 4 6"    # top, right/left, bottom
border-width = "2 4 6 8"  # top, right, bottom, left
```

Per-side keys override the list:

```toml
[notifications]
border-width = 2
border-width-left = 6
```

That gives notifications a 2px border on the top, right, and bottom, and a 6px
left edge.

State-specific borders follow the same pattern. A selected menu row can use a
different width from the card border:

```toml
[menu]
selected-border = "accent"
selected-border-width = "1 1 1 4"
```

For state-specific surfaces such as lock and polkit, the token name prefixes
the width key:

```toml
[lock]
border-active = "rgba(33ccffee) rgba(00ff99ee) 45deg"
border-active-width-left = 6
```

### Control borders

`[controls]` governs shared controls such as buttons, dropdowns, text fields,
toggles, and cursor rows. Each state has a fill color, optional border value,
border width, and border alpha:

```toml
[controls]
normal-color        = "#a9b1d6"
normal-border       = "#a9b1d6"
normal-border-width = 1
normal-border-alpha = 0.4

hover-cursor-color        = "#a9b1d6"
hover-cursor-border       = "#a9b1d6"
hover-cursor-border-width = 1
hover-cursor-border-alpha = 0.25
```

The `*-border` keys can also be gradients:

```toml
[controls]
focus-border = "rgba(33ccffee) rgba(00ff99ee) 45deg"
focus-border-width = "2 2 2 4"
```

Set a border width to `0` to keep the fill but remove that state border.

### Surface sections

Common shell sections include:

- `[bar]`
- `[controls]`
- `[popups]`
- `[tooltip]`
- `[notifications]`
- `[launcher]`
- `[menu]`
- `[polkit]`
- `[lock]`
- `[image-picker]`
- `[spacing]`
- `[font]`

Clipboard and emojis inherit menu tokens. Popups are used by bar flyouts,
dropdowns, OSD, and popup cards.

## QML border API

Plugin and shell QML should use `BorderSurface` for theme-aware borders:

```qml
import qs.Commons
import qs.Ui

BorderSurface {
  color: Color.popups.background
  borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 2)
  padding: Style.spacing.popupPadding

  Item {
    anchors.fill: parent
    anchors.topMargin: parent.contentTopInset
    anchors.rightMargin: parent.contentRightInset
    anchors.bottomMargin: parent.contentBottomInset
    anchors.leftMargin: parent.contentLeftInset
  }
}
```

Use `Border.surfaceSpec(section, token, fallbackColor, fallbackWidth)` for
shell theme tokens, `Border.controlSpec(state, foreground, accent)` for shared
controls, and `Border.flat(color, width)` for a deliberate local border that
should not be overridden by the active theme. `Color.<section>.border` is the
flat first-stop color for consumers that cannot render full border specs.

## Hyprland templates

Hyprland theme output is generated from `default/themed/hyprland.lua.tpl`.
Use `hypr_gradient` for border values because Hyprland's Lua config wants a
Lua string for solid colors and a Lua table for gradients:

```lua
local active_border_color = {{ hypr_gradient hyprland_active_border accent }}
```

For a solid fallback this renders:

```lua
local active_border_color = "#7aa2f7"
```

For a gradient it renders:

```lua
local active_border_color = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }
```

## Adding or overriding theme files

- Add palette values to `themes/<name>/colors.toml`.
- Prefer generated files when the theme can be expressed with templates.
- Add a hand-written file in `themes/<name>/` only when that theme needs to
  override the generated output entirely.
- Add a new built-in template under `default/themed/<file>.tpl` when every
  theme should generate that file.
- Add a user-wide template under `~/.config/omarchy/themed/<file>.tpl` when a
  local customization should apply across themes.

When changing templates or theme helpers, run focused tests such as:

```bash
./test/cli
./test/shell
```
