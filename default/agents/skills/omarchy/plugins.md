# Omarchy Shell and Plugins

Use this guide for the bar, widgets, notifications, menus, shell plugins, idle,
and lock behavior. These surfaces run in one long-lived Quickshell process,
`omarchy-shell`.

## State and Defaults

```text
~/.config/omarchy/shell.json                    # User bar, plugin, and idle overrides
~/.config/omarchy/extensions/omarchy-menu.jsonc # User menu and launcher overrides
~/.config/omarchy/plugins/<plugin-id>/          # User-owned shell plugins
$OMARCHY_PATH/config/omarchy/shell.json         # Packaged shell defaults
$OMARCHY_PATH/shell/plugins/                    # Packaged plugin source
```

`shell.json`, menu extensions, and user plugin files hot-reload when saved.
Use `omarchy restart shell` when a live reload does not apply cleanly. With user
confirmation, `omarchy refresh shell` restores packaged shell configuration.

## Shell Configuration Loop

1. Read the user override and matching packaged default.
2. Prefer the relevant `omarchy bar` or `omarchy plugin` command when available.
3. Otherwise edit the narrowest value in `~/.config/omarchy/shell.json`.
4. Validate JSON with `jq empty ~/.config/omarchy/shell.json`.
5. Observe the requested bar, notification, menu, idle, or lock behavior.

The shell change is complete when JSON validation is clean and the affected
surface behaves as requested. If hot reload does not apply, restart the shell
and repeat the observation.

## Bar Layout

Discover current bar commands with `omarchy bar --help`. For example:

```bash
omarchy bar move omarchy.clock --section right
```

Use `~/.config/omarchy/shell.json` for layout changes not exposed by a command.
Verify every moved, added, removed, or configured widget in the running bar.

## Built-In Plugins and Widgets

Clone a built-in plugin before customizing its code:

```bash
omarchy plugin clone omarchy.workspaces
# Edit ~/.config/omarchy/plugins/<username>.workspaces/
```

Cloning switches the relevant configuration to the user-owned copy. Saved
changes under `~/.config/omarchy/plugins/` reload automatically and survive
package updates. Force discovery after a failed reload with:

```bash
omarchy-shell shell rescanPlugins
```

Plugin work is complete when the user-owned plugin is active, the requested
behavior has been observed, and the packaged source remains unchanged.

## Menus and Launcher

Put menu overrides in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`; inspect
`$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc` for current entries and
schema examples. Saved changes hot-reload.

Menu work is complete when the changed entry can be found and its action runs
successfully from the live menu.

## Idle and Lock

Set `idle.screensaver` and `idle.lock` in `~/.config/omarchy/shell.json`. Values
are seconds from the beginning of user inactivity. For example, ten minutes is
`600`.

Idle work is complete when the file passes JSON validation and the configured
screensaver and lock transitions occur at the requested thresholds. Long waits
that were not exercised must be reported as unverified.

## Recovery

After user confirmation:

```bash
omarchy refresh shell
```

Confirm the backup, check the restored JSON, and observe the affected shell
surface before reporting recovery complete.
