# Omarchy Shell: Bar, Plugins, and Idle

Read this before changing the status bar, notifications, shell plugins,
widgets, or idle/lock behavior.

The bar, notification daemon, settings panel, and assorted overlays all run
inside a single long-running Quickshell process (`omarchy-shell`).

```
~/.config/omarchy/shell.json             # User overrides: bar, plugins, idle
~/.config/omarchy/plugins/<plugin-id>/   # User-owned shell plugins
$OMARCHY_PATH/config/omarchy/shell.json  # Canonical defaults
```

The shell hot-reloads `shell.json` on save — no restart needed for layout
changes. `idle.screensaver` and `idle.lock` are seconds since user idle began.

**Commands:** `omarchy restart shell`, `omarchy refresh shell`

## Bar Layout

Use the `omarchy bar` group to move and manage widgets:

```bash
omarchy bar move omarchy.clock --section right
```

For layout edits beyond what the commands cover, edit the bar configuration
in `~/.config/omarchy/shell.json`; it hot-reloads on save.

## Customizing Built-In Plugins and Widgets

To customize a built-in bar widget, never edit `$OMARCHY_PATH/shell/plugins/`.
Clone it into the user plugin directory instead:

```bash
omarchy plugin clone omarchy.workspaces
# Edit ~/.config/omarchy/plugins/<username>.workspaces/; saved changes reload automatically.
```

Cloning switches the bar to the cloned copy (e.g. `<username>.workspaces`),
which is yours to edit and survives updates.

Saving a file anywhere under `~/.config/omarchy/plugins/` reloads plugin code
automatically. If a change somehow fails to apply, force a reload with
`omarchy-shell shell rescanPlugins`.

## Plugin Safety: Bound Every File Read

`omarchy-shell` is a single long-running process. Never read a file into it
without a size bound — an oversized or corrupted file (a plugin's state or
config file grown by a bug, or written by another process) forces unbounded
allocation in a process the user cannot afford to have balloon.

- `FileView` (`Quickshell.Io`) reads the *entire* file before any code can
  validate or reject it. Do not use it for user-writable files.
- Read such files with a bounded `Process` instead: read at most one byte over
  the hard cap (e.g. `timeout 5 head -c 65537 -- "$path"` for a 64 KiB cap)
  and reject output over the cap. A preliminary `stat -c%s` can fast-reject an
  oversized file, but cannot enforce the bound because the file may change.
- Bound the in-memory model too. A file under the byte cap can still hold a
  huge array — cap collection counts (dice lists, side lists, rows) to a sane
  maximum while parsing.

## Idle and Lock

Set `idle.screensaver` and `idle.lock` in `~/.config/omarchy/shell.json`,
in seconds since user idle began. Example: "lock after ten minutes" means
setting `idle.lock` to `600`.
