# Task Guides

Deeper instructions for specific kinds of work live in `agents/skills/`. Read the
matching guide before starting:

- [`agents/skills/command-metadata.md`](agents/skills/command-metadata.md) - adding or changing commands in `bin/`
- [`agents/skills/install-scripts.md`](agents/skills/install-scripts.md) - working under `install/` or on system/user setup commands
- [`agents/skills/shell-dev.md`](agents/skills/shell-dev.md) - editing the Quickshell desktop under `shell/`
- [`agents/skills/icon-font.md`](agents/skills/icon-font.md) - adding branded glyphs to `default/fonts/omarchy/omarchy.ttf`
- [`agents/skills/acceptance-tests.md`](agents/skills/acceptance-tests.md) - writing or running graphical acceptance tests under `test/acceptance.d/`
- [`agents/skills/visual-verification.md`](agents/skills/visual-verification.md) - verifying any change with a visual effect in the running UI
- [`agents/skills/migrations.md`](agents/skills/migrations.md) - creating or changing migrations under `migrations/`

# Documentation Layout

Three documentation trees, split by genre and audience:

- `agents/skills/` - task procedure ("do this when doing X"), for anyone working on the codebase
- `docs/` - reference on how the system is shaped (file layout, update pipeline, theming, shell architecture), for anyone working on the codebase; skills link here for depth
- `manual/` - end-user documentation for using Omarchy, published; never codebase internals

# Style

- Two spaces for indentation, no tabs
- Use bash 5 conditionals: use `[[ ]]` for string/file tests and `(( ))` for numeric tests
- In `[[ ]]`, don't quote variables, but do quote string literals when comparing values (e.g., `[[ $branch == "dev" ]]`)
- Prefer `(( ))` over numeric operators inside `[[ ]]` (e.g., `(( count < 50 ))`, not `[[ $count -lt 50 ]]`)
- Prefer a full `if`/`else` conditional for simple two-path control flow; don't rely on `exec` or `exit` in one branch to make following statements unreachable
- For strings/paths with spaces, quote them instead of escaping spaces with `\ ` (e.g., `"$APP_DIR/Disk Usage.desktop"`, not `$APP_DIR/Disk\ Usage.desktop`)
- Shebangs must use `#!/bin/bash` consistently (never `#!/usr/bin/env bash`)
- Scripts under `install/` and `migrations/` may be sourced and intentionally omit shebangs

# Command Naming

All commands start with `omarchy-`. Prefixes indicate purpose.

The authoritative list of user-facing command groups lives in `bin/omarchy` in `GROUP_DESCRIPTIONS`. Keep `GROUP_DESCRIPTIONS` updated when adding a new command prefix users are meant to browse to.

A group whose commands are all `# omarchy:hidden=true` gets no entry. That table drives the top-level group listing on its own, so an entry there advertises the group even when every command in it is hidden. `apply-` and `provision-` are deliberately absent for that reason; both still route, and `omarchy <group>` still prints a group header without one.

Common prefixes include:

- `cmd-` - check if commands exist, misc utility commands
- `capture-` - screenshots, screen recordings, and other capture tools
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

Do not maintain a second exhaustive prefix list here. Consult
`GROUP_DESCRIPTIONS` when selecting or checking a command group so this
guidance does not drift from the router.

# Runtime Environment

- `$OMARCHY_PATH` is set at the top level by the uwsm session environment and is always available to Omarchy runtime code.
- Commands in `bin/` and Quickshell QML should rely on `$OMARCHY_PATH` / `Quickshell.env("OMARCHY_PATH")`; do not derive fallback paths from `HOME`, `Quickshell.shellDir`, or re-export/default `OMARCHY_PATH` manually.

# Privileged Commands

- Follow the "Privilege Escalation" section of `default/agents/skills/omarchy/SKILL.md`. It draws the
  `sudo`/`pkexec` line by whether the caller has a terminal to enter a password in, and the repo's
  own scripts follow it.

# Git

- Commits should be atomic: include only one coherent change or fix, and do not mix unrelated work.
- Commit messages should be succinct and describe the change being made.

# Helper Commands

Use these instead of raw shell commands:

- `omarchy-cmd-missing` / `omarchy-cmd-present` - check for commands
- `omarchy-pkg-missing` / `omarchy-pkg-present` - check for packages (don't use these if you can just use `omarchy-pkg-add`/`omarchy-pkg-drop`)
- `omarchy-pkg-add` - install packages (handles both pacman and AUR)
- `omarchy-pkg-drop` - remove packages; use this instead of raw `pacman -R*`
- `omarchy-notification-send` - send desktop notifications; do not call `notify-send` directly
- `omarchy-hw-asus-rog` - detect ASUS ROG hardware (and similar `hw-*` commands)

Commands installed by Omarchy's default package set are runtime invariants. Invoke them directly; do not add defensive `omarchy-cmd-present` / `omarchy-cmd-missing` checks around them. Use command-presence helpers only for genuinely optional dependencies or code that can run before the default package set is installed.

Exceptions are allowed for migration and package-helper scripts where the helper may not be available yet, where the helper itself is being implemented, or where direct package-manager behavior is required.

# Menu

- The menu definition lives in `default/omarchy/omarchy-menu.jsonc`.
- Do not add `aliases` to new menu entries. Aliases are reserved for
  established alternate names users already type, kept for compatibility.

# Config Structure

- `config/` - default configs copied to `~/.config/`
- `default/themed/*.tpl` - templates with `{{ variable }}` placeholders for theme colors
- `themes/*/colors.toml` - theme color definitions (accent, background, foreground, red/green/yellow/blue/magenta/cyan and bright_* variants)

# Tests

Run focused automated tests for the area you changed. Current test entry points:

- `./test/all` - aggregate runner for CLI and shell tests; it intentionally does not run graphical acceptance tests
- `./test/cli` - CLI routing, command metadata, theme helpers, and safe dispatch coverage
- `./test/shell` - all Omarchy shell tests under `test/shell.d/`

New Omarchy shell tests should live in `test/shell.d/*-test.sh` so `./test/shell` picks them up automatically. Source `test/shell.d/base-test.sh` for shared root-path discovery, assertions, and Node test helpers.

The graphical acceptance suite runs in a disposable VM, not in the active
development session; see [`agents/skills/acceptance-tests.md`](agents/skills/acceptance-tests.md).

Visual changes must be verified in the running UI in addition to automated
tests; follow [`agents/skills/visual-verification.md`](agents/skills/visual-verification.md).

# Refresh Pattern

To copy a default config to user config with automatic backup:

```bash
omarchy-refresh-config hypr/hyprland.lua
```

This copies `$OMARCHY_PATH/config/hypr/hyprland.lua` to `~/.config/hypr/hyprland.lua`. The argument
is interpolated into both paths and only checked with `[[ -e ]]`, so pass a plain relative path: a
name containing `..` resolves and copies, landing outside `~/.config` rather than being rejected.
