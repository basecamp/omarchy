# Omarchy shell

`omarchy-shell` is a single long-running [Quickshell](https://quickshell.org/)
instance that hosts the Omarchy desktop. Hyprland autostart launches one shell
per graphical session; everything else — the bar, the bar settings UI, the
background switcher, future panels and overlays — runs **inside** the shell as
a plugin.

Hosting everything inside one shell means:

- shared services and singletons live once, not once per process
- summoning a panel is an IPC call into a process that is already running,
  not a fresh `quickshell -p ...` cold start
- third-party plugins can be loaded from disk without changing any source
  code in Omarchy itself

The runtime layout:

```
shell/
  shell.qml              entry point (ShellRoot)
  shell-defaults.json    canonical out-of-the-box config
  services/
    PluginRegistry.qml   discovers, validates plugins, looks up enabled state in shell.json
    BarWidgetRegistry.qml unified registry for bar widgets (1p + 3p)
  plugins/
    bar/                 first-party plugins (see plugins/README.md)
    settings/            settings panel + plugin-declared widget forms
    launcher/
    image-picker/
    menu/
    notifications/
    services/
      battery/
      idle/
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

Panels, overlays, and menus are loaded when summoned. Plugins that need
to outlive a single summon can set `keepLoaded: true` (e.g. the image
picker keeps its overlay window mounted between summons). First-party
services are loaded at startup.

The full schema lives in `services/PluginRegistry.qml`.

## Installing a third-party plugin

1. Drop the plugin into `~/.config/omarchy/plugins/<plugin-id>/`.
   The directory must contain a `manifest.json` plus the QML files
   referenced from its `entryPoints`.
2. `omarchy plugin rescan`.
3. Enable the plugin with `omarchy plugin enable <id>`.
4. If it's a `bar-widget`, place it with `omarchy plugin bar add <id>` or
   open the visual editor with `omarchy plugin bar edit`.

The lower-level IPC equivalents are still available via `omarchy-shell shell rescanPlugins`,
`omarchy-shell shell setPluginEnabled <id> true`, and `omarchy-shell shell listPlugins`.
The `omarchy plugin` command wraps those calls and can also edit the persisted
bar layout in `shell.json`.

To hack on an existing widget safely, clone it into a user plugin instead of
editing the built-in source. Third-party ids must be namespaced and may not use
the reserved `omarchy.*` prefix.

```bash
omarchy plugin clone omarchy.clock local.clock --replace --open pi
omarchy plugin clone                 # interactive source/name/tool picker
```

First-party plugins under `shell/plugins/`
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
quickshell ipc -p $OMARCHY_PATH/shell call shell ping
```

Hyprland autostart launches the shell directly with `quickshell -p
$OMARCHY_PATH/shell`. Use `omarchy-restart-shell` (`quickshell reload`) to
reload the long-running shell process.

A convenience wrapper, [`omarchy-shell`](../bin/omarchy-shell), forwards IPC
calls to the running shell. It does not start the shell.

```
omarchy-shell shell ping
omarchy-shell shell summon omarchy.settings "{}"
omarchy-shell shell listPlugins
omarchy-shell shell rescanPlugins
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
  "idle": {
    "screensaver": 150,
    "lock": 300
  },
  "bar": {
    "position": "top",
    "transparent": false,
    "centerAnchor": "omarchy.clock",
    "layout": {
      "left":   [ { "id": "omarchy.menu" }, { "id": "omarchy.workspaces" } ],
      "center": [ { "id": "omarchy.clock", "format": "HH:mm" } ],
      "right": [
        { "id": "omarchy.audio" }
      ]
    }
  },
  "plugins": []
}
```

### Storage rules

1. **Every plugin instance is one entry.** Either in `bar.layout.<section>`
   for bar widgets, or in `plugins[]` for panels, overlays, services,
   menus, and anything else non-bar.
2. **Settings are inline on the entry.** No `config:` sub-object, no
   separate per-plugin settings file, no merge layers. The fields on each
   entry are the values the plugin sees.
3. **Built-in widget ids are namespaced.** Use ids such as `omarchy.clock`,
   `omarchy.audio`, and `omarchy.network`. Legacy ids like `Clock` and
   `AudioPanel` are accepted as aliases and migrated forward.
4. **Third-party enabled ⇔ present.** A third-party plugin is enabled iff
   its id appears somewhere in shell.json. For bar widgets, the bar
   settings UI adds/removes layout entries; other plugin kinds are enabled
   with the shell IPC. First-party plugins are always enabled.
5. **Multiple instances** are allowed when a manifest sets
   `allowMultiple: true`. Each instance is independent — e.g. two clock
   widgets in different timezones are just two `{"id":"omarchy.clock", "timezone": ...}`
   entries with their own values.
6. **Idle timings are top-level.** `idle.screensaver` and `idle.lock`
   are seconds since user idle began, so the default lock fires at 300s
   even if the 150s screensaver starts first.
7. **`version: 1` is required** at the top level. The shell will fall back
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
