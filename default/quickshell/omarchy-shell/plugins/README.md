# First-party plugins

These plugins ship with Omarchy and are loaded by the shell at startup.
They use the same `manifest.json` contract as third-party plugins; the
only difference is that the shell flags them with `__isFirstParty: true`
so they cannot be disabled.

User-installed plugins live alongside these conceptually but on disk under
`~/.config/omarchy/plugins/<plugin-id>/` rather than in this directory.

| Plugin                | id                            | kinds        | activation  | entry point                |
|-----------------------|-------------------------------|--------------|-------------|----------------------------|
| Bar                   | `omarchy.bar`                 | `bar`        | persistent  | `bar/Bar.qml`              |
| Bar settings          | `omarchy.bar-settings`        | `panel`      | on-demand   | `bar-settings/BarSettingsPanel.qml` |
| Background switcher   | `omarchy.background-switcher` | `overlay`    | on-demand   | `background-switcher/BackgroundSwitcher.qml` |

## Bar

The status bar. Mounted at startup, lives forever. Layout is configured
through `~/.config/omarchy/bar.json` (deep-merged over
[`bar/bar-defaults.json`](bar/bar-defaults.json)). Owns the `bar` IPC
target for refresh hooks fired by indicator scripts. See
[`bar/README.md`](bar/README.md) for the widget catalogue and customization
schema.

## Bar settings

Visual editor for the bar layout. Summoned by
`omarchy-shell-ipc shell summon omarchy.bar-settings "{}"` (which is what
`omarchy launch bar-settings` ultimately calls). Provides:

- per-section add/move/remove/edit of widget entries
- a Plugin Manager tab for enabling/disabling third-party plugins
- a dynamic settings form driven by each widget's manifest schema

## Background switcher

Fullscreen wallpaper / image picker overlay. Summoned for ad-hoc wallpaper
selection. Keeps its legacy unix socket protocol at
`/run/user/<uid>/omarchy-image-selector.sock` so existing callers like
`omarchy-menu-images` keep working without any wire-format change. The
plugin has `keepLoaded: true` so the socket survives between summons.

## Coming soon

- `omarchy.menu` — folds the existing `omarchy-menu` (currently on another
  branch) into the shell as a `menu` plugin. Not present on this branch.
- `omarchy.theme-switcher` — folds theme switching into the shell.
