# Noctalia plugin compatibility (omarchy-shell)

The omarchy-shell can load most bar widget plugins from the
[noctalia-dev/noctalia-plugins](https://github.com/noctalia-dev/noctalia-plugins)
ecosystem without any modification to the plugin code.

## Install a Noctalia plugin

```sh
git clone https://github.com/noctalia-dev/noctalia-plugins /tmp/noctalia-plugins
ln -s /tmp/noctalia-plugins/asus-um5606-fan-state \
      ~/.config/omarchy/plugins/asus-um5606-fan-state
omarchy-shell-ipc shell rescanPlugins
```

The plugin id you see inside Omarchy is prefixed: `noctalia.asus-um5606-fan-state`.
Add it via the bar customizer or by editing `~/.config/omarchy/shell.json` directly.

## What's supported in v1

| Noctalia concept | Omarchy support |
|---|---|
| `entryPoints.barWidget` | yes — registered through `BarWidgetRegistry` |
| `entryPoints.panel` | yes — opened via `pluginApi.openPanel()` |
| `entryPoints.settings` | yes — embedded in the bar-settings dialog |
| `entryPoints.main` | yes — instantiated as a hidden service, exposed via `pluginApi.mainInstance` |
| `entryPoints.desktopWidget` | **no** — skipped with a console warning |
| `entryPoints.launcherProvider` | **no** — skipped with a console warning |
| `entryPoints.controlCenterWidget` | **no** — skipped with a console warning |
| Plugin i18n (`i18n/<lang>.json`) | **no** — `tr()` returns the raw key |
| Plugin install from git URL | **no** — manual drop into `~/.config/omarchy/plugins/` |
| Hot reload on plugin change | **no** — call `omarchy-shell-ipc shell rescanPlugins` |

## Shim surface

We ship just enough of Noctalia's QML namespace to render typical bar widgets.

| Module | Symbols |
|---|---|
| `qs.Commons` | `Color`, `Style`, `Logger`, `Settings` (read-only), `I18n` (stub), `Time`, `Icons` (~50 entries), `ThemeIcons` (stub), `ShellState` (stub) |
| `qs.Widgets` | `NText`, `NIcon`, `NIconButton`, `NBox`, `NButton`, `NPopupContextMenu`, `NScrollText`, `NToggle`, `NSpinBox`, `NSlider`, `NTextInput`, `NComboBox`, `NCheckbox`, `NDivider` |
| `qs.Services.UI` | `BarService`, `TooltipService`, `PanelService` |
| `qs.Services.System` | `HostService` (reads `/etc/os-release`) |
| `qs.Services.Power` | `PowerProfileService` (returns `noctaliaPerformanceMode: false`) |

Anything outside this surface logs a `console.warn` instead of crashing the
shell, but the plugin may not render correctly.

## `pluginApi` surface

A Noctalia plugin's `pluginApi` is built per-plugin and injected onto the bar
widget / panel / settings entry points. The implementation lives at
`compat/noctalia/PluginApiFactory.qml`.

| Property / method | Behaviour |
|---|---|
| `pluginId`, `pluginDir`, `manifest` | Provided as expected. |
| `pluginSettings` | Live read of the plugin's entry in `~/.config/omarchy/shell.json`, merged with the manifest's `metadata.defaultSettings`. |
| `mainInstance` | Live instance of `Main.qml` when the plugin declares one. |
| `saveSettings()` | Persists the merged settings into the plugin's entry in `shell.json`. |
| `openPanel(screen, btn)` / `closePanel(screen)` / `togglePanel(screen, btn)` | Routes through `omarchy-shell-ipc shell summon/hide` against the plugin's panel entry point. |
| `withCurrentScreen(cb)` | Calls `cb` with the bar's currently-rendering screen. |
| `tr/trp/hasTranslation` | Returns the key as-is; no i18n in v1. |
| `openLauncher(...)` family | Stub — logs a warning. |

## Known limitations

- Plugin labels show raw translation keys for non-English locales.
- Icon names not present in our compact `Icons` map render as `?`.
- Plugins that declare only `desktopWidget` or `launcherProvider` and no
  bar/panel/main do not appear in the Omarchy catalog.
- Some plugins call `Color.mPrimary` for accent colors that don't perfectly
  match Omarchy's theme palette; results are close but not pixel-identical.
