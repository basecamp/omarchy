# Automation Hooks

Read this before setting up scripts that run on system events (theme changes, updates, boot, low battery, etc.).

## Supported hook paths

For an event named `<name>`, `omarchy-hook` recognizes these path shapes:

| Layer | Flat hook | Hook directory |
| ----- | --------- | -------------- |
| Active Omarchy tree | `$OMARCHY_PATH/hooks/<name>` | `$OMARCHY_PATH/hooks/<name>.d/*` |
| Package data directory | `<data-dir>/omarchy/hooks/<name>` | `<data-dir>/omarchy/hooks/<name>.d/*` |
| User configuration | `$HOME/.config/omarchy/hooks/<name>` | `$HOME/.config/omarchy/hooks/<name>.d/*` |

`<data-dir>` is each absolute entry in `${XDG_DATA_DIRS:-/usr/local/share:/usr/share}`. With the default value, package hooks are therefore read from `/usr/local/share/omarchy/hooks/` and `/usr/share/omarchy/hooks/`. Empty and relative entries are ignored. `XDG_DATA_HOME` is not searched; per-user hooks belong under `$HOME/.config/omarchy/hooks/`.

The flat hook and `<name>.d/` form can coexist in the same root. The flat hook runs first, followed by non-hidden regular files directly inside `<name>.d/` in filename order. Nested directories, names beginning with `.`, and directory entries ending in `.sample` are ignored. The runner invokes hook files with `/bin/bash`, so the executable bit is not required, although `omarchy hook install` sets it.

Event names must start with an ASCII letter or number and may contain only ASCII letters, numbers, `.`, `_`, and `-`. Empty names, names beginning with punctuation, path separators, whitespace, and other characters are rejected by both the runner and installer.

## Available events

User hooks can be installed with `omarchy hook install <name> <script>`, which preserves the script's basename, copies it to `$HOME/.config/omarchy/hooks/<name>.d/`, and makes it executable. Rename a hidden script or one ending in `.sample` before installing it, since those names are intentionally skipped. Omarchy currently emits these events:

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

Distribution packages should normally install hooks below `/usr/share/omarchy/hooks/`; locally administered hooks can use `/usr/local/share/omarchy/hooks/`. For example, a package can install `/usr/share/omarchy/hooks/theme-set.d/50-windows-xp`. Additional absolute data directories can be supplied through `XDG_DATA_DIRS`. These hooks remain available when `omarchy dev link` points `$OMARCHY_PATH` at a source checkout.

Package hook paths are executable trust boundaries. A package hook path is supported only when all of the following are true:

- No component in the path from `/` through the hook file is a symlink.
- Every path component is owned by root or the invoking user.
- The package root (`<data-dir>/omarchy/hooks`) and everything below it are not group- or other-writable.
- A group- or other-writable directory above the package root has the sticky bit set, as `/tmp` normally does.
- The package root and event directory are directories, and the hook itself is a regular file.

Existing paths that fail these checks are reported and skipped before duplicate-hook shadowing is applied, so an unsafe entry cannot suppress a safe hook with the same name in a later package root. Missing package roots are skipped silently. The explicit active-tree and user roots are trusted separately: their symlinks are supported, and the package ownership and mode checks do not apply to them.

The active Omarchy tree can also ship hooks under `$OMARCHY_PATH/hooks/`. The runner canonicalizes hook roots, so the normal `/usr/share/omarchy` tree is not run twice when it appears through both `$OMARCHY_PATH` and `XDG_DATA_DIRS`.

Hook roots run in this order:

1. The active core or development tree at `$OMARCHY_PATH/hooks`.
2. Package-managed data directories, in `XDG_DATA_DIRS` order. Empty and relative entries are ignored; an unset or empty variable defaults to `/usr/local/share:/usr/share`.
3. The user's `~/.config/omarchy/hooks` directory.

Within each root, the flat `<name>` hook runs first, followed by non-hidden regular files in `<name>.d/` in filename order. A hook in the active tree shadows a package hook with the same relative name, and a hook in an earlier XDG data directory shadows one in a later directory. This prevents a core hook present in both a development checkout and the installed package from running twice. User hooks are a separate customization layer and always run after system hooks, even when their filenames match. Canonically identical roots run only once.

Directory entries ending in `.sample` are skipped. A failing hook is reported but does not prevent later hooks from running. All hooks run as the user who invoked the Omarchy command, including package-managed hooks.
