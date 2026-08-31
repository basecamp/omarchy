# Automation Hooks

Read this before setting up scripts that run on system events (theme changes,
updates, boot, low battery, etc.).

Hooks live in `~/.config/omarchy/hooks/<name>.d/` — one directory per event,
holding any number of independent scripts. Install with
`omarchy hook install <name> <script>` (copies the script in and makes it
executable). The runner also executes a flat `~/.config/omarchy/hooks/<name>`
file first, if one exists.

```
~/.config/omarchy/hooks/
├── battery-low.d/          # Low battery (percentage in $1)
├── font-set.d/             # After font change (font name in $1)
├── post-boot.d/            # After the desktop starts
├── post-update.d/          # At the end of `omarchy update`, after privileged work
├── pre-refresh-pacman.d/   # After `omarchy refresh pacman` finishes (legacy name)
└── theme-set.d/            # After theme change (theme slug in $1)
```

Example hook script:
```bash
#!/bin/bash
THEME_NAME=$1
echo "Theme changed to: $THEME_NAME"
# Add custom actions here
```

Update-related hooks run only after the workflow's privileged work and after Omarchy invalidates its sudo timestamp. A hook that invokes `sudo` must therefore request its own explicit authorization. The legacy-named `pre-refresh-pacman` hook runs after the refresh transaction; during `omarchy channel set`, it is deferred further until the package switch and complete update finish. Executable user code cannot safely run before a later sudo authentication because a detached child could wait for the new timestamp.
