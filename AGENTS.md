# Style

- Two spaces for indentation, no tabs
- Use bash 5 conditionals: use `[[ ]]` for string/file tests and `(( ))` for numeric tests
- In `[[ ]]`, don't quote variables, but do quote string literals when comparing values (e.g., `[[ $branch == "dev" ]]`)
- Prefer `(( ))` over numeric operators inside `[[ ]]` (e.g., `(( count < 50 ))`, not `[[ $count -lt 50 ]]`)
- For strings/paths with spaces, quote them instead of escaping spaces with `\ ` (e.g., `"$APP_DIR/Disk Usage.desktop"`, not `$APP_DIR/Disk\ Usage.desktop`)
- Shebangs must use `#!/bin/bash` consistently (never `#!/usr/bin/env bash`)
- Scripts under `install/` and `migrations/` may be sourced and intentionally omit shebangs

# Command Naming

All commands start with `omarchy-`. Prefixes indicate purpose.

The authoritative command group list lives in `bin/omarchy` in `GROUP_DESCRIPTIONS`. Keep `GROUP_DESCRIPTIONS` updated when adding a new command prefix.

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

Other current prefixes include:

- `ac-`, `audio-`, `battery-`, `branch-`, `brightness-`, `channel-`, `config-`, `debug-`, `dev-`, `drive-`, `first-`, `font-`, `haptic-`, `hibernation-`, `hook-`, `hyprland-`, `menu-`, `migrate-`, `notification-`, `npm-`, `plymouth-`, `powerprofiles-`, `reinstall-`, `remove-`, `screensaver-`, `show-`, `snapshot-`, `state-`, `sudo-`, `system-`, `transcode-`, `tui-`, `tz-`, `upload-`, `version-`, `voxtype-`, `webapp-`, `wifi-`, `windows-`

# Command Metadata

Commands in `bin/` can declare CLI metadata in comments near the top of the file. `bin/omarchy` scans the first 80 lines, and tests expect command metadata to remain valid.

Supported metadata keys:

- `# omarchy:summary=...` - short help text
- `# omarchy:args=...` - usage arguments
- `# omarchy:examples=...` - examples separated with ` | `
- `# omarchy:alias=...` / `# omarchy:aliases=...` - alternate routes
- `# omarchy:hidden=true` - hide from default command listings
- `# omarchy:requires-sudo=true` - mark commands that require sudo

Only use `omarchy:examples` where there are args that need explaining.

Prefer explicit metadata for user-facing commands. Keep routes consistent with the filename unless there is a deliberate alias or compatibility route.

Example:

```bash
# omarchy:summary=Take a screenshot
# omarchy:args=[smart|region|windows|fullscreen] [slurp|copy]
# omarchy:examples=omarchy screenshot | omarchy capture screenshot region
```

# Runtime Environment

- `$OMARCHY_PATH` is set at the top level by the uwsm session environment and is always available to Omarchy runtime code.
- Commands in `bin/` and Quickshell QML should rely on `$OMARCHY_PATH` / `Quickshell.env("OMARCHY_PATH")`; do not derive fallback paths from `HOME`, `Quickshell.shellDir`, or re-export/default `OMARCHY_PATH` manually.

# Privileged Commands

- Whenever you need to trigger a sudo command, use `pkexec` so it results in a user prompt they can approve.

# Git

- Commits should be atomic: include only one coherent change or fix, and do not mix unrelated work.
- Commit messages should be succinct and describe the change being made.

# Install Scripts

The ISO owns installation orchestration. This repo ships target-side setup commands and reusable setup leaves:

- `bin/omarchy-setup-system` runs root-owned system setup during ISO finalization.
- `bin/omarchy-setup-hardware` runs idempotent hardware-specific setup and is called by `omarchy-setup-system`.
- `bin/omarchy-setup-user` runs user setup for the initial user and future users.
- leaf scripts under `install/` are sourced by `run_logged $OMARCHY_INSTALL/path/to/script.sh` and intentionally do not have shebangs.
- avoid `exit` in sourced setup scripts unless intentionally aborting setup.
- use `$OMARCHY_INSTALL` and `$OMARCHY_PATH` instead of hard-coded Omarchy paths.
- keep root-scoped hardware setup under `install/hardware/` and orchestrate it through `install/hardware/all.sh`.
- keep every per-user setup leaf under `install/user/` (including `install/user/hardware/` and `install/user/first-run/`) so it is clear what must run for each user.
- prefer helper commands for package and command checks where available.

Raw `command -v`, `pacman`, and `pacman-key` are acceptable in package-helper contexts where direct package-manager behavior is the point of the script.

# Helper Commands

Use these instead of raw shell commands:

- `omarchy-cmd-missing` / `omarchy-cmd-present` - check for commands
- `omarchy-pkg-missing` / `omarchy-pkg-present` - check for packages (don't use these if you can just use `omarchy-pkg-add`/`omarchy-pkg-drop`)
- `omarchy-pkg-add` - install packages (handles both pacman and AUR)
- `omarchy-pkg-drop` - remove packages; use this instead of raw `pacman -R*`
- `omarchy-notification-send` - send desktop notifications; do not call `notify-send` directly
- `omarchy-hw-asus-rog` - detect ASUS ROG hardware (and similar `hw-*` commands)

Exceptions are allowed for migration and package-helper scripts where the helper may not be available yet, where the helper itself is being implemented, or where direct package-manager behavior is required.

# Config Structure

- `config/` - default configs copied to `~/.config/`
- `default/themed/*.tpl` - templates with `{{ variable }}` placeholders for theme colors
- `themes/*/colors.toml` - theme color definitions (accent, background, foreground, red/green/yellow/blue/magenta/cyan and bright_* variants)

# Tests

Run focused automated tests for the area you changed. Current test entry points:

- `./test/all` - aggregate runner for CLI and shell tests
- `./test/cli` - CLI routing, command metadata, theme helpers, and safe dispatch coverage
- `./test/shell` - all Omarchy shell tests under `test/shell.d/`

New Omarchy shell tests should live in `test/shell.d/*-test.sh` so `./test/shell` picks them up automatically. Source `test/shell.d/base-test.sh` for shared root-path discovery, assertions, and Node test helpers.

For visual changes, such as omarchy-shell styling, desktop appearance, screenshots, or screen recording flows, verify with the running UI in addition to automated tests. Take and analyze screenshots with `omarchy capture screenshot fullscreen save`. For animation, transitions, capture, or screen recording behavior, make a short recording with `omarchy screenrecord --fullscreen`, stop it with `omarchy screenrecord --stop-recording`, and review the output before finishing.

For interactive UI work, use `wtype` to simulate keyboard input when available. Example: start the UI in the background, wait briefly for focus, then run `wtype -k Right -k Return` to exercise keyboard selection and confirm the resulting command output or state change. Prefer this over manual-only verification when a UI returns a selected value or changes a symlink/config.

When testing layer-shell UI, capture the reference and candidate states as separate screenshots, then compare them visually before further edits. If a launched UI would otherwise remain open, keep track of its PID and stop it after the screenshot; avoid broad process kills unless checking with `ps` first.

# Omarchy shell

The Quickshell desktop runs as a single long-running process out of
`shell/`. Hyprland autostart launches it directly with `quickshell -p`; do
not start additional standalone `quickshell -p` instances for individual
components.

Run `omarchy-restart-shell` after making changes to QML files.

Plugin contract:

- Each plugin lives in its own directory under
  `shell/plugins/<id>/` (first-party) or
  `~/.config/omarchy/plugins/<id>/` (third-party).
- Every plugin ships a `manifest.json` declaring `id`, `kinds`,
  `activation`, and `entryPoints`. The full schema is in
  [`docs/omarchy-shell.md`](docs/omarchy-shell.md).
- Entry-point QML files are `Item`s (not `ShellRoot`), and accept the
  shell-injected properties `omarchyPath`, `shell`, `manifest`, and
  `pluginRegistry` / `barWidgetRegistry` as appropriate.
- Panel / overlay / menu plugins must expose `open(payloadJson)` and
  `close()` lifecycle methods for `shell summon` and `shell hide`.

IPC:

- `bin/omarchy-shell` is the canonical IPC entry point. It forwards to
  the running shell and does not start it. Prefer it over re-implementing
  direct Quickshell socket calls in every CLI.
- The `shell` IPC target exposes `ping`, `summon`, `hide`, `toggle`,
  `rescanPlugins`, `setPluginEnabled`, and `listPlugins`. Individual
  plugins can register additional IPC targets (the bar registers `bar`,
  the background switcher registers `image-selector`).

Widget files in `shell/plugins/bar/widgets/` contain Nerd Font glyphs as raw
unicode characters. The `Write` and `Edit` tools strip multi-byte
codepoints in some positions — do **not** rewrite widget files wholesale
through those tools. For glyph fixes, use the targeted `Edit` tool with
the surrounding context, or a Python script that inserts codepoints via
`chr(0xXXXXX)`.

# Refresh Pattern

To copy a default config to user config with automatic backup:

```bash
omarchy-refresh-config hypr/hyprlock.conf
```

This copies `$OMARCHY_PATH/config/hypr/hyprlock.conf` to `~/.config/hypr/hyprlock.conf`.

# Migrations

To create a new migration, run `omarchy-dev-add-migration --no-edit`. This creates a migration file named after the unix timestamp of the last commit.

New migration format:
- File permissions must be `0644` (`-rw-r--r--`); migrations are sourced, not executed directly
- No shebang line
- Start with an `echo` describing what the migration does
- Use `$OMARCHY_PATH` to reference the omarchy directory
- Prefer helper commands such as `omarchy-cmd-present`, `omarchy-cmd-missing`, `omarchy-pkg-present`, and `omarchy-pkg-missing`

Omarchy 4.0 is upgraded through `bin/omarchy-upgrade-to-4`, not through the normal migration runner. Do not add compatibility migrations for old installer layouts; put pre-4 package-layout transition work in the upgrade command instead.

Migrations may use raw `pacman`, `command -v`, or direct config edits when needed for one-off repair work.
