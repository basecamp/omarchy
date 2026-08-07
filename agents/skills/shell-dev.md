# Omarchy Shell Development

Read this before editing the Quickshell desktop under `shell/`.

The Quickshell desktop runs as a single long-running process out of
`shell/`. Hyprland autostart launches it directly with `quickshell -n -p`;
do not start additional standalone Quickshell instances for individual
components.

Run `omarchy-restart-shell` after making changes to QML files.

## Plugin contract

- First-party plugins live directly under `shell/plugins/` or one category
  level deeper, such as `shell/plugins/panels/weather/`. First-party bar-only
  widgets may use adjacent `*.manifest.json` files. Third-party plugins live
  at `~/.config/omarchy/plugins/<id>/` with a `manifest.json` at the root.
- Every plugin manifest declares `schemaVersion`, `id`, `name`, `version`,
  `kinds`, and `entryPoints`. See
  [`docs/omarchy-shell.md`](../../docs/omarchy-shell.md) and
  `shell/services/PluginRegistry.qml` for the current contract; fields such as
  `activation` are optional.
- Entry-point QML files are `Item`s (not `ShellRoot`), and accept the
  shell-injected properties `omarchyPath`, `shell`, `manifest`, and
  `pluginRegistry` / `barWidgetRegistry` as appropriate.
- Panel / overlay / menu plugins must expose `open(payloadJson)` and
  `close()` lifecycle methods for `shell summon` and `shell hide`.

## IPC

- `bin/omarchy-shell` is the canonical IPC entry point. It forwards to
  the running shell and does not start it. Prefer it over re-implementing
  direct Quickshell socket calls in every CLI.
- The `shell` IPC target exposes lifecycle and configuration methods including
  `ping`, `summon`, `hide`, `toggle`, `call`, `rescanPlugins`, `reloadConfig`,
  `setPluginEnabled`, and `listPlugins`. `shell.qml` also registers
  `image-selector`, which drives the `omarchy.image-picker` panel.
- Individual plugins register their own IPC targets, named for the plugin rather
  than for where they appear: the background switcher registers `background`, and
  bar widgets register one target each — `omarchy.indicators`,
  `omarchy.system-update`, `omarchy.clock`. There is no `bar` target.

## Editing widget files with glyphs

Widget files in `shell/plugins/bar/widgets/` contain Nerd Font glyphs as raw
unicode characters. Agent file-editing tools can strip multi-byte codepoints
in some positions — do **not** rewrite widget files wholesale through those
tools. For glyph fixes, make a targeted edit with the surrounding context, or
use a Python script that inserts codepoints via `chr(0xXXXXX)`.
