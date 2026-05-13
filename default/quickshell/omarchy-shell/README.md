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
  services/
    PluginRegistry.qml   discovers, validates, persists plugin state
    BarWidgetRegistry.qml unified registry for bar widgets (1p + 3p)
  ui/
    settings/
      DynamicSettingsForm.qml  renders plugin-declared schemas
  plugins/
    bar/                 first-party plugins (see plugins/README.md)
    bar-settings/
    background-switcher/
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

`activation` is either `persistent` (loaded on startup, never unloaded) or
`on-demand` (loaded by `shell summon <id>` and unloaded by `shell hide`).
Plugins that need their IPC socket to outlive a single summon can set
`keepLoaded: true` (e.g. background-switcher's legacy unix socket).

The full schema lives in `services/PluginRegistry.qml`.

## Installing a third-party plugin

1. Drop the plugin into `~/.config/omarchy/plugins/<plugin-id>/`.
   The directory must contain a `manifest.json` plus the QML files
   referenced from its `entryPoints`.
2. `omarchy-shell-ipc shell rescanPlugins` — or open the Plugin Manager
   tab in `omarchy launch bar-settings` and click **Rescan**.
3. Enable the plugin (Plugin Manager **Enable** toggle, or
   `omarchy-shell-ipc shell setPluginEnabled <id> true`).
4. If it's a `bar-widget`, add it to a layout section from the bar editor.

First-party plugins under `default/quickshell/omarchy-shell/plugins/`
are discovered the same way and cannot be disabled.

## IPC contract

The shell exposes a single `shell` IPC target plus whatever extra targets
individual plugins register (e.g. the bar's `bar` target for refresh
hooks, the background switcher's `image-selector` target).

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

A convenience wrapper, [`omarchy-shell-ipc`](../../../bin/omarchy-shell-ipc),
starts the shell if it is not already running, then forwards a `call`. It
is the canonical way for other Omarchy CLIs to talk to the shell.

```
omarchy-shell-ipc shell ping
omarchy-shell-ipc shell summon omarchy.bar-settings "{}"
omarchy-shell-ipc shell listPlugins
omarchy-shell-ipc shell rescanPlugins
```

**Note on `setPluginEnabled`:** the `enabled` argument is a string. Only the
literal `"true"` enables the plugin; every other value (including `"True"`,
`"1"`, `"yes"`, or omitted) disables it. This keeps the IPC surface
type-stable across QML's `string`-only IPC arguments.

## Persisted state

| Path                                      | Owner          | Purpose                              |
|-------------------------------------------|----------------|--------------------------------------|
| `~/.config/omarchy/bar.json`              | bar plugin     | section layout + per-entry settings  |
| `~/.config/omarchy/plugins.json`          | PluginRegistry | enabled/disabled state               |
| `~/.config/omarchy/plugins/<id>/`         | user           | manifest + entry points + assets     |
| `~/.config/omarchy/plugins/<id>/settings.json` | user      | optional per-plugin overrides        |

## Implementation history

Built up in phases on this branch:

- Phase 1 — `omarchy-shell phase 1: host the existing bar in a single shell`
- Phase 2 — `omarchy-shell phase 2: plugin registry and bar widget registry`
- Phase 3 — `omarchy-shell phase 3: fold bar-settings into the shell as a panel plugin`
- Phase 4 — `omarchy-shell phase 4: absorb background-switcher as a plugin`
- Phase 5 — `omarchy-shell phase 5: docs, cleanup, and migration crumbs` (this commit)

Shared services and Pipewire/UPower/Hyprland consolidation are explicitly
out of scope here and deferred to a follow-up after a review pass.
