# Style

- Two spaces for indentation, no tabs
- Use bash 5 conditionals: use `[[ ]]` for string/file tests and `(( ))` for numeric tests
- In `[[ ]]`, don't quote variables, but do quote string literals when comparing values (e.g., `[[ $branch == "dev" ]]`)
- Prefer `(( ))` over numeric operators inside `[[ ]]` (e.g., `(( count < 50 ))`, not `[[ $count -lt 50 ]]`)
- For strings/paths with spaces, quote them instead of escaping spaces with `\ ` (e.g., `"$APP_DIR/Disk Usage.desktop"`, not `$APP_DIR/Disk\ Usage.desktop`)
- Shebangs must use `#!/bin/bash` consistently (never `#!/usr/bin/env bash`)

# Command Naming

All commands start with `omarchy-`. Prefixes indicate purpose:

- `cmd-` - check if commands exist, misc utility commands
- `pkg-` - package management helpers
- `hw-` - hardware detection (return exit codes for use in conditionals)
- `refresh-` - copy default config to user's `~/.config/`
- `restart-` - restart a component
- `launch-` - open applications
- `install-` - install optional software
- `setup-` - interactive setup wizards
- `toggle-` - toggle features on/off
- `theme-` - theme management
- `update-` - update components

# Helper Commands

Use these instead of raw shell commands:

- `omarchy-cmd-missing` / `omarchy-cmd-present` - check for commands
- `omarchy-pkg-missing` / `omarchy-pkg-present` - check for packages
- `omarchy-pkg-add` - install packages (handles both pacman and AUR)
- `omarchy-hw-asus-rog` - detect ASUS ROG hardware (and similar `hw-*` commands)

# Config Structure

- `config/` - default configs copied to `~/.config/`
- `default/themed/*.tpl` - templates with `{{ variable }}` placeholders for theme colors
- `themes/*/colors.toml` - theme color definitions (accent, background, foreground, color0-15)

# Refresh Pattern

To copy a default config to user config with automatic backup:

```bash
omarchy-refresh-config hypr/hyprlock.conf
```

This copies `~/.local/share/omarchy/config/hypr/hyprlock.conf` to `~/.config/hypr/hyprlock.conf`.

# Migrations

To create a new migration, run `omarchy-dev-add-migration --no-edit`. This creates a migration file named after the unix timestamp of the last commit.

Migration format:
- No shebang line
- Start with an `echo` describing what the migration does
- Use `$OMARCHY_PATH` to reference the omarchy directory

Example:
```bash
echo "Disable fingerprint in hyprlock if fingerprint auth is not configured"

if omarchy-cmd-missing fprintd-list || ! fprintd-list "$USER" 2>/dev/null | grep -q "finger"; then
  sed -i 's/fingerprint:enabled = .*/fingerprint:enabled = false/' ~/.config/hypr/hyprlock.conf
fi
```
