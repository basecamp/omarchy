# Automation Hooks

Read this before setting up scripts that run on system events (theme changes, updates, boot, low battery, etc.).

User hooks live in `~/.config/omarchy/hooks/<name>.d/` — one directory per event, holding any number of independent scripts. Install with `omarchy hook install <name> <script>` (copies the script in and makes it executable). The runner also executes a flat `~/.config/omarchy/hooks/<name>` file first, if one exists.

```
~/.config/omarchy/hooks/
├── battery-low.d/          # Low battery (percentage in $1)
├── font-set.d/             # After font change (font name in $1)
├── post-boot.d/            # After the desktop starts
├── post-update.d/          # During `omarchy update`, after system packages and migrations
├── pre-refresh-pacman.d/   # Before `omarchy refresh pacman` re-syncs packages
└── theme-set.d/            # After theme change (theme slug in $1)
```

Example hook script:

```bash
#!/bin/bash
THEME_NAME=$1
echo "Theme changed to: $THEME_NAME"
# Add custom actions here
```

## Package-managed hooks

Packages can install hooks under `omarchy/hooks/` in an absolute directory from `${XDG_DATA_DIRS:-/usr/local/share:/usr/share}`. For example, a package can install `/usr/share/omarchy/hooks/theme-set.d/50-windows-xp`. These hooks remain available when `omarchy dev link` points `$OMARCHY_PATH` at a source checkout.

The active Omarchy tree can also ship hooks under `$OMARCHY_PATH/hooks/`. The runner canonicalizes hook roots, so the normal `/usr/share/omarchy` tree is not run twice when it appears through both `$OMARCHY_PATH` and `XDG_DATA_DIRS`.

Hook roots run in this order:

1. The active core or development tree at `$OMARCHY_PATH/hooks`.
2. Package-managed data directories, in `XDG_DATA_DIRS` order. Empty and relative entries are ignored; an unset or empty variable defaults to `/usr/local/share:/usr/share`.
3. The user's `~/.config/omarchy/hooks` directory.

Within each root, the flat `<name>` hook runs first, followed by regular files in `<name>.d/` in filename order. A hook in the active tree shadows a package hook with the same relative name, and a hook in an earlier XDG data directory shadows one in a later directory. This prevents a core hook present in both a development checkout and the installed package from running twice. User hooks are a separate customization layer and always run after system hooks, even when their filenames match. Canonically identical roots run only once.

Files ending in `.sample` are skipped. A failing hook is reported but does not prevent later hooks from running. All hooks run as the user who invoked the Omarchy command, including package-managed hooks.
