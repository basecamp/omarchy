# Omarchy shell

`omarchy-shell` is a single long-running [Quickshell](https://quickshell.org/)
instance that hosts the Omarchy desktop. Hyprland autostarts one shell per
session; everything else — the bar, the bar settings UI, the background
switcher, future panels and overlays — runs **inside** the shell as a
plugin.

Hosting everything inside one shell means:

- shared services and singletons live once, not once per process
- summoning a panel is an IPC call into a process that is already running,
  not a fresh `quickshell -p ...` cold start
- third-party plugins can be loaded from disk without changing any source
  code in Omarchy itself

The runtime layout in this branch:

```
default/quickshell/omarchy-shell/
  shell.qml              entry point (ShellRoot)
  shell-defaults.json    canonical out-of-the-box config
  services/
    PluginRegistry.qml   discovers, validates plugins, looks up enabled state in shell.json
    BarWidgetRegistry.qml unified registry for bar widgets (1p + 3p)
  ui/
    settings/
      DynamicSettingsForm.qml  renders plugin-declared schemas
  plugins/
    bar/                 first-party plugins (see plugins/README.md)
    settings/
    image-picker/
    menu/
    notifications/
    osd/
    polkit/
```

The plugin discovery path is documented in [plugins/README.md](plugins/README.md).

## Plugin manifest

Every plugin ships a `manifest.json` describing what it is and how the
shell should load it. Minimal example:

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
  "entryPoints": { "barWidget": "Widget.qml" },
  "barWidget": {
    "displayName": "Cool clock",
    "category": "Time",
    "allowMultiple": false,
    "defaults": { "format": "HH:mm" },
    "schema": [
      { "key": "format", "type": "string", "label": "Format" }
    ]
  }
}
```

Supported `kinds`:

| Kind         | What it is                                                   |
|--------------|--------------------------------------------------------------|
| `bar-widget` | A component that the bar can drop into a section             |
| `panel`      | A persistent or summoned floating window (e.g. bar settings) |
| `overlay`    | A fullscreen overlay (e.g. background switcher)              |
| `menu`       | A summoned menu surface                                      |
| `service`    | A headless singleton, no UI                                  |
| `bar`        | Reserved for the first-party bar host (`omarchy.bar`). Third-party plugins should ship `bar-widget`s; they do not replace the host bar. |

`activation` is either `persistent` (loaded on startup, never unloaded) or
`on-demand` (loaded by `shell summon <id>` and unloaded by `shell hide`).
Plugins that need to outlive a single summon can set `keepLoaded: true`
(e.g. the image picker keeps its overlay window mounted between
summons).

The full schema lives in `services/PluginRegistry.qml`.

## Installing a third-party plugin

1. Drop the plugin into `~/.config/omarchy/plugins/<plugin-id>/`.
   The directory must contain a `manifest.json` plus the QML files
   referenced from its `entryPoints`.
2. `omarchy-shell-ipc shell rescanPlugins`.
3. Enable the plugin with `omarchy-shell-ipc shell setPluginEnabled <id> true`.
4. If it's a `bar-widget`, add it to a layout section from the bar editor.

First-party plugins under `default/quickshell/omarchy-shell/plugins/`
are discovered the same way and cannot be disabled.

## IPC contract

The shell exposes a single `shell` IPC target plus whatever extra targets
individual plugins register (e.g. the bar's `bar` target for refresh
hooks, the image picker's `image-selector` target). `omarchy-menu` uses the
shell target to summon the first-party `omarchy.menu` plugin instead of
running a separate Quickshell instance.

| Method                                   | Returns | Effect                                                |
|------------------------------------------|---------|-------------------------------------------------------|
| `ping`                                   | `ok`    | health check                                          |
| `summon <id> <payloadJson>`              | `ok` / `unknown` | load + open a panel/overlay plugin           |
| `hide <id>`                              | —       | close a previously-summoned plugin                    |
| `toggle <id> <payloadJson>`              | —       | summon if closed, hide if open                        |
| `rescanPlugins`                          | —       | re-walk plugin dirs and pick up new/changed manifests |
| `setPluginEnabled <id> <enabled>`        | —       | flip the persisted enabled bit (see note)             |
| `listPlugins`                            | JSON    | every discovered plugin (id, name, kinds, enabled)    |

Direct invocation:

```
quickshell ipc -p $OMARCHY_PATH/default/quickshell/omarchy-shell call shell ping
```

Hyprland starts the shell through `omarchy-restart-shell` on boot.
Use `omarchy-restart-shell` to reload the long-running shell process.

A convenience wrapper, [`omarchy-shell-ipc`](../../../bin/omarchy-shell-ipc),
starts the shell if it is not already running, then forwards a `call`. It
is the canonical way for other Omarchy CLIs to talk to the shell.

```
omarchy-shell-ipc shell ping
omarchy-shell-ipc shell summon omarchy.settings "{}"
omarchy-shell-ipc shell listPlugins
omarchy-shell-ipc shell rescanPlugins
```

**Note on `setPluginEnabled`:** the `enabled` argument is a string. Only the
literal `"true"` enables the plugin; every other value (including `"True"`,
`"1"`, `"yes"`, or omitted) disables it. This keeps the IPC surface
type-stable across QML's `string`-only IPC arguments.

## Persisted state

There is one user config file. Everything that distinguishes your
customization from the shipped defaults lives in it.

| Path                              | Owner          | Purpose                                                |
|-----------------------------------|----------------|--------------------------------------------------------|
| `~/.config/omarchy/shell.json`    | the shell      | full layout + per-entry settings + enabled plugin list |
| `~/.config/omarchy/plugins/<id>/` | user           | drop-in third-party plugin source files                |

The `shell-defaults.json` bundled with the shell describes the
fresh-install state. When the user has no `shell.json`, the shell uses
the defaults verbatim. Once the user customizes anything, `shell.json`
becomes the authoritative file — we do **not** deep-merge defaults back
in. Pressing **Reset bar to defaults** in `omarchy launch bar settings`
rewrites the `bar` subtree from the current `shell-defaults.json`.

### shell.json shape

```json
{
  "version": 1,
  "bar": {
    "position": "top",
    "centerAnchor": "calendar",
    "fontFamily": "JetBrainsMono Nerd Font",
    "layout": {
      "left":   [ { "id": "omarchy" }, { "id": "workspaces" } ],
      "center": [ { "id": "calendar", "format": "HH:mm" } ],
      "right": [
        { "id": "audioPanel" }
      ]
    }
  },
  "plugins": [
    { "id": "omarchy.settings" },
    { "id": "omarchy.image-picker" }
  ]
}
```

### Storage rules

1. **Every plugin instance is one entry.** Either in `bar.layout.<section>`
   for bar widgets, or in `plugins[]` for panels, overlays, services,
   menus, and anything else non-bar.
2. **Settings are inline on the entry.** No `config:` sub-object, no
   separate per-plugin settings file, no merge layers. The fields on each
   entry are the values the plugin sees.
3. **Enabled ⇔ present.** A plugin is enabled iff its id appears somewhere
   in shell.json. For bar widgets, the bar settings UI adds/removes layout
   entries; other plugin kinds are enabled with the shell IPC.
4. **Multiple instances** are allowed when a manifest sets
   `allowMultiple: true`. Each instance is independent — e.g. two clocks
   in different timezones are just two `{"id":"calendar", "timezone": ...}`
   entries with their own values.
5. **`version: 1` is required** at the top level. The shell will fall back
   to defaults rather than load an unknown version.

## Implementation history

Built up in phases on this branch:

- Phase 1 — `omarchy-shell phase 1: host the existing bar in a single shell`
- Phase 2 — `omarchy-shell phase 2: plugin registry and bar widget registry`
- Phase 3 — `omarchy-shell phase 3: fold bar-settings into the shell as a panel plugin`
- Phase 4 — `omarchy-shell phase 4: absorb background-switcher as a plugin`
- Phase 5 — `omarchy-shell phase 5: docs, cleanup, and migration crumbs`
- Phase 6 — `omarchy-shell phase 6: reviewer cleanup (path traversal, collision, races)`
- Phase 7 — `omarchy-shell phase 7: replace socket with IpcHandler, rename to image-picker`
- Phase 8a — `omarchy-shell phase 8a: unified shell.json with inline plugin settings`

Shared services and Pipewire/UPower/Hyprland consolidation are explicitly
out of scope here and deferred to a follow-up after a review pass.
