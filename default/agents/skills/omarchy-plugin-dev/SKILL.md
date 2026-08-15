---
name: omarchy-plugin-dev
description: >
  Use when the user wants to WRITE, SCAFFOLD, or PUBLISH a third-party Omarchy
  shell plugin (a bar widget, panel, overlay, menu, service, or full bar
  replacement) — as opposed to just enabling/moving/configuring one. Triggers:
  "create an omarchy plugin", "write a bar widget", "omarchy-shell plugin",
  manifest.json for omarchy, publishing to omarchyplugins.com, `omarchy plugin
  validate`, custom QML bar module. For end-user customization of an
  already-installed system (theming, keybindings, moving widgets around,
  editing shell.json), use the `omarchy` skill instead — that skill's
  plugins.md covers cloning and configuring existing plugins, not authoring
  new ones.
---

# Authoring Omarchy Shell Plugins

A plugin is a **git repo with a `manifest.json` at its root**, loaded by
`omarchy-shell` (the long-running Quickshell process that hosts the bar,
panels, overlays, menus, and background services). This skill covers writing
one from scratch through publishing it. For the end-user side (installing,
enabling, moving, cloning plugins on an already-set-up system), defer to the
`omarchy` skill's `plugins.md`.

**Read these on-disk files before writing a manifest** — they are the
authoritative, always-current schema (this file summarizes them, but the shell
enforces what they say, not what's written here):

```
$OMARCHY_PATH/shell/README.md                # manifest schema, IPC contract, shell.json shape
$OMARCHY_PATH/shell/plugins/README.md         # first-party plugin catalogue (ids, kinds, entry points)
$OMARCHY_PATH/shell/plugins/bar/README.md     # bar widget catalogue, bar properties, custom module examples
```

Reading `$OMARCHY_PATH` is always safe. **Never edit it directly** on an
installed system — it's package-owned and gets overwritten on `omarchy
update`. Study real examples there freely; a lot of first-party plugins are
excellent templates.

## 1. Pick a kind

| Kind | What it is | Needs |
|---|---|---|
| `bar-widget` | Small always-visible bar module, optionally with a popup | `entryPoints.barWidget` |
| `bar` | Full bar replacement (only one active at a time) | `entryPoints.bar` |
| `panel` | Persistent or summoned floating window | `entryPoints.panel` |
| `overlay` | Fullscreen overlay (e.g. a picker) | `entryPoints.overlay` |
| `menu` | Summoned menu surface | `entryPoints.menu` |
| `service` | Headless singleton, no UI | `entryPoints.service` |

A manifest can declare multiple kinds (e.g. `omarchy.media` is both `service`
and `bar-widget`). Most third-party plugins are a single `bar-widget`.

If all you need is a static command's output on the bar (no popup, no state),
you don't need a plugin at all — a `type: "command"` entry directly in
`~/.config/omarchy/shell.json` (see `shell/plugins/bar/README.md`) is simpler
and requires no manifest. Reach for a real plugin when you need a popup,
persistent state, or something distributable to other users.

## 2. Fastest start: clone something similar

Before scaffolding from scratch, find a first-party plugin close to what you
want (`shell/plugins/panels/weather/` for a bar widget with a popup,
`omarchy.workspaces` for a bare bar widget, `omarchy.media` for a
widget+service pair) and use it as a reference implementation. You can even
have the user clone it live to get a working copy to study:

```bash
omarchy plugin clone omarchy.weather
# lands at ~/.config/omarchy/plugins/<username>.weather/ — read it, then
# start your own plugin fresh rather than publishing a rename of it.
```

## 3. Scaffold from scratch

Work in a normal git repo anywhere (not directly under
`~/.config/omarchy/plugins/` — you'll copy it in for testing, see §4).
Minimum layout for a bar widget:

```
my-omarchy-widget/
├── manifest.json
├── Widget.qml
└── README.md
```

Minimal `manifest.json`:

```json
{
  "schemaVersion": 1,
  "id": "yourhandle.cool-clock",
  "name": "Cool clock",
  "version": "1.0.0",
  "author": "Your Name",
  "description": "A clock that does cool things",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml" },
  "barWidget": {
    "displayName": "Cool clock",
    "description": "A clock that does cool things",
    "category": "Time",
    "allowMultiple": false,
    "defaultSection": "right",
    "defaults": { "format": "HH:mm" },
    "schema": [
      { "key": "format", "type": "string", "label": "Format" }
    ]
  }
}
```

Field notes:

- `id` must match `^[A-Za-z0-9][A-Za-z0-9._-]*$`, contain no `..`, and **must
  not start with `omarchy.`** — that namespace is reserved for first-party
  plugins and the validator rejects it. Namespace with your handle
  (`yourhandle.thing`).
- `schemaVersion` must be the literal JSON number `1`.
- `entryPoints` values are relative paths from the plugin root; they must
  exist and contain no `..` or absolute paths.
- `barWidget.defaultSection`, if set, must be `left`, `center`, or `right`.
- `barWidget.allowMultiple: true` lets a user add more than one instance
  (each with its own settings entry in `shell.json`).
- `barWidget.settingsForm` names a settings-panel form id if you want a
  configurable settings UI beyond raw JSON editing (see `omarchy.weather` for
  a real example — `shell/plugins/panels/weather/manifest.json`).

Bar widget QML skeleton — an `Item` receiving `bar`, `moduleName`, `settings`
injected by the host:

```qml
import QtQuick

Item {
  property var bar
  property string moduleName
  property var settings

  implicitWidth: 28
  implicitHeight: bar ? bar.barSize : 26

  Text {
    anchors.centerIn: parent
    text: settings && settings.format ? settings.format : "--"
    color: bar ? bar.foreground : "white"
    font.family: bar ? bar.fontFamily : "monospace"
    font.pixelSize: 12
  }

  MouseArea {
    anchors.fill: parent
    onClicked: if (bar) bar.run("some-command")
  }
}
```

Useful `bar` properties/methods: `bar.foreground` / `bar.background` /
`bar.urgent` (live theme colors), `bar.fontFamily`, `bar.position`,
`bar.vertical`, `bar.barSize`, `bar.run(cmd)` (fire-and-forget bash),
`bar.shellQuote(value)`, `bar.showTooltip(target, text)` /
`bar.hideTooltip(target)`, `bar.requestPopout(owner)` /
`bar.releasePopout(owner)` (one-popup-at-a-time coordinator for a popup
widget). Full list and popup examples in `shell/plugins/bar/README.md`.

For `panel` / `overlay` / `menu` / `service` kinds, there's no shared skeleton
this short — go read the matching first-party plugin
(`shell/plugins/image-picker/`, `shell/plugins/services/battery/`, etc.) and
mirror its shape; the IPC contract they use (`summon`/`hide`/`toggle`/`call`)
is documented in `shell/README.md`.

## 4. Validate and test locally

```bash
omarchy plugin validate ./my-omarchy-widget
```

This mirrors the shell's own registry checks: valid JSON, `schemaVersion == 1`,
required fields present, a legal non-`omarchy.*` id, entry points that exist
and stay inside the plugin folder, every declared kind having its required
entry point, and no symlinks anywhere in the tree (symlinks are refused
outright — a copied plugin could otherwise point back at arbitrary files on
disk once it lands in the trusted plugins directory). Fix everything it flags
before moving on.

To actually run it inside the live shell, drop it into the user plugin
directory and rescan:

```bash
mkdir -p ~/.config/omarchy/plugins
cp -r ./my-omarchy-widget ~/.config/omarchy/plugins/yourhandle.cool-clock
omarchy-shell shell rescanPlugins
omarchy plugin enable yourhandle.cool-clock
```

Saving a file anywhere under `~/.config/omarchy/plugins/` hot-reloads that
plugin's code automatically — keep editing your working copy there and it
picks up changes live. Move it around the bar with `omarchy bar move`, or
check load state with `omarchy plugin list --json` and
`omarchy-shell shell listPlugins`. When you're done testing, copy the
(now-final) files back into your actual git repo, since the plugins directory
copy is a throwaway working copy, not your source of truth.

## 5. Publish

A plugin is installed by cloning a git repo, so publishing is just pushing
one:

```bash
gh repo create yourhandle/omarchy-cool-clock --public --source=. --push
```

Anyone (including on another machine) installs it with:

```bash
omarchy plugin add https://github.com/yourhandle/omarchy-cool-clock.git --enable --yes
```

Give the repo a README describing what it does and any `settings` keys it
reads — plugin authors commonly list themselves on
[omarchyplugins.com](https://omarchyplugins.com/) and the community-curated
[awesome-omarchy](https://github.com/aorumbayev/awesome-omarchy) list; mention
these to the user if they want visibility, but don't submit on their behalf
without asking.

## Safety notes to pass on to the user

- **Plugins run as unsandboxed code inside `omarchy-shell`.** There's no
  process isolation — a malicious or buggy plugin can do anything the user's
  session can. `omarchy plugin add` clones disabled by default specifically so
  the code can be reviewed before enabling; don't skip that review when
  helping a user install someone else's plugin.
- Never edit `$OMARCHY_PATH` to "fix" a first-party plugin as a shortcut —
  clone it (`omarchy plugin clone <id>`) into user config instead, which is
  exactly the `omarchy` skill's territory, not this one.
