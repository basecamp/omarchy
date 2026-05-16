# First-party plugins

These plugins ship with Omarchy and are loaded by the shell at startup.
They use the same `manifest.json` contract as third-party plugins; the
only difference is that the shell flags them with `__isFirstParty: true`
so they cannot be disabled.

User-installed plugins live alongside these conceptually but on disk under
`~/.config/omarchy/plugins/<plugin-id>/` rather than in this directory.

| Plugin        | id                      | kinds     | activation | entry point                         |
|---------------|-------------------------|-----------|------------|-------------------------------------|
| Bar           | `omarchy.bar`           | `bar`     | persistent | `bar/Bar.qml`                       |
| Bar settings  | `omarchy.settings`      | `panel`   | on-demand  | `settings/SettingsPanel.qml`        |
| Image picker  | `omarchy.image-picker`  | `overlay` | on-demand  | `image-picker/ImagePicker.qml`      |
| Omarchy menu  | `omarchy.menu`          | `menu`    | on-demand  | `menu/Menu.qml`                     |
| Notifications | `omarchy.notifications` | `service` | persistent | `notifications/Service.qml`         |
| OSD           | `omarchy.osd`           | `panel`   | persistent | `osd/Osd.qml`                       |
| Polkit agent  | `omarchy.polkit`        | `service` | persistent | `polkit/PolkitAgent.qml`            |

## Bar

The status bar. Mounted at startup, lives forever. Layout lives in the
top-level `bar:` subtree of `~/.config/omarchy/shell.json` (with the shell
providing [`shell-defaults.json`](../shell-defaults.json) when the user has
no file). Owns the `bar` IPC target for refresh hooks fired by indicator
scripts. See [`bar/README.md`](bar/README.md) for the widget catalogue
and customization schema.

## Bar settings

Visual editor for the bar layout. Summoned by
`omarchy-shell-ipc shell summon omarchy.settings "{}"` (which is what
`omarchy launch settings` ultimately calls). Provides:

- bar position and center-anchor controls
- per-section add/move/remove/edit of bar widget entries
- dynamic per-widget settings forms that write inline back to the
  corresponding shell.json entry

## Image picker

Fullscreen image-grid selector overlay. Used by `omarchy-menu-images`
(wallpaper picker) and `omarchy-theme-switcher` (theme picker) and any
other caller that wants to present a directory of images with previews.

Two ways to drive it:

- Shell-level summon: `omarchy-shell-ipc shell summon omarchy.image-picker '<jsonPayload>'`.
  The payload can carry `imageDirs`, `imageRows`, `selectedImage`,
  `selectionFile`, `doneFile`, `showLabels`, `filterable`. Best for
  in-shell callers that already speak JSON.
- Direct IPC target: `omarchy-shell-ipc image-selector open <imageDirs> <imageRowsB64> <selectedImage> <selectionFile> <doneFile> <showLabels> <filterable>`.
  Positional args; `imageRowsB64` is base64-encoded so embedded newlines /
  tabs survive the bash argv handoff. This is what `omarchy-menu-images`
  uses. Colors come from the central shell theme singleton; there is no
  per-call override surface.

The selection round-trip remains file-based: callers create a
`selection_file` and `done_file` (both `mktemp`), pass the paths, and
poll `done_file` for existence. The plugin writes the chosen path into
`selection_file` and touches `done_file` when it's done. `cancel` IPC
clears it without writing a selection.

The plugin has `keepLoaded: true` so the layer-shell window survives
between summons within a single shell session.

## Polkit agent

Theme-aware authentication dialog for privileged actions. It uses
Quickshell's native `Quickshell.Services.Polkit.PolkitAgent` backend and
runs inside the long-lived `omarchy-shell` process, replacing the old
`polkit-gnome-authentication-agent-1` autostart.

## Omarchy menu

Quickshell-powered replacement for the legacy Walker-driven `omarchy-menu`.
The menu UI lives in `menu/Menu.qml` as a first-party `menu` plugin and is
summoned through the shell (`omarchy-shell-ipc shell summon omarchy.menu ...`),
so it shares the long-running `omarchy-shell` process instead of starting a
second Quickshell instance.

The menu definition lives outside the shell host code:

- defaults: `default/omarchy/omarchy-menu.jsonc`
- user extensions: `~/.config/omarchy/extensions/omarchy-menu.jsonc`

The shell parses both JSONC files at startup (with `watchChanges: true`
so edits take effect without a restart), evaluates `when:` / `checked:`
bash expressions in a single batched subprocess, and executes the
selected `action:` string directly via `Quickshell.execDetached`. The
long-running shell process keeps the parsed menu in memory, so the
keybind → IPC → visible path costs ~30ms cold.

## Coming soon

- `omarchy.theme-switcher` — folds theme switching into the shell.
