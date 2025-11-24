# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Omarchy is a beautiful, modern & opinionated Linux distribution built on Arch Linux by DHH. It provides a polished desktop experience using Hyprland (Wayland compositor) with carefully curated packages, themes, and utilities. Current version: 3.2.0.

**This is a custom branch maintained by [constantinchik](https://github.com/constantinchik).** This fork contains personal customizations and modifications to the upstream Omarchy distribution.

## Architecture

### Installation System

The installation follows a modular, phase-based approach orchestrated through `install.sh`:

```
boot.sh (online installer)
    └─> install.sh
        ├─> helpers/all.sh (utilities, logging, error handling)
        ├─> preflight/all.sh (system validation, pacman setup)
        ├─> packaging/all.sh (package installation)
        ├─> config/all.sh (system configuration)
        ├─> login/all.sh (boot and login setup)
        └─> post-install/all.sh (finalization)
```

**Key Installation Directories:**
- `install/helpers/` - Core utilities (logging, presentation, error handling, chroot)
- `install/preflight/` - Pre-installation checks and pacman configuration
- `install/packaging/` - Package installation scripts
- `install/config/` - System configuration (34 scripts including hardware-specific fixes)
- `install/login/` - Boot splash, display manager, bootloader setup
- `install/post-install/` - Final package updates and completion
- `install/first-run/` - Post-reboot configuration (executed once on first login)

**Package Files:**
- `install/omarchy-base.packages` - Core 140+ packages
- `install/omarchy-other.packages` - Optional packages
- `install/packages.pinned` - Version-locked packages
- `install/packages.ignored` - Excluded packages

**Logging:** All operations logged to `/var/log/omarchy-install.log` with real-time tail display during installation.

### Migration System

Idempotent, timestamp-based update system for existing installations:

- **Location:** `migrations/` directory (70+ migration scripts)
- **Naming:** Unix timestamp format (e.g., `1762121828.sh`)
- **State Tracking:** `~/.local/state/omarchy/migrations/` stores completion markers
- **Execution:** `omarchy-migrate` runs pending migrations in chronological order
- **Integration:** Runs during initial install (all marked complete) and system updates

### Configuration System

**Layered Configuration Pattern:**
```
Default configs (default/) → Theme configs (themes/) → User configs (~/.config/)
```

- `config/` - Default configurations deployed to `~/.config/`
- `default/` - Base configuration templates that configs source from
- User configs in `~/.config/` override defaults
- Apps source theme-specific configs from `~/.config/omarchy/current/theme/`

**Example:** Hyprland config layers:
```conf
# ~/.config/hypr/hyprland.conf
source = ~/.local/share/omarchy/default/hypr/autostart.conf
source = ~/.local/share/omarchy/default/hypr/bindings/media.conf
source = ~/.config/omarchy/current/theme/hyprland.conf
source = ~/.config/hypr/monitors.conf  # User overrides
```

### Theme System

14 complete theme definitions in `themes/` directory (catppuccin, tokyo-night, gruvbox, nord, etc.).

**Theme Structure:** Each theme includes configs for alacritty, btop, chromium, ghostty, hyprland, hyprlock, kitty, mako, neovim, vscode, walker, waybar, plus backgrounds and preview images.

**Theme Application:**
- Symlink chain: `~/.config/omarchy/current/theme` → selected theme
- `omarchy-theme-set <name>` updates links and restarts all themed components
- Individual theme setters: `omarchy-theme-set-cursor/gnome/browser/vscode/obsidian`

### Bin Utilities (136 scripts)

Organized by function prefix:

- `omarchy-pkg-*` - Package management (add, drop, missing, aur-install)
- `omarchy-theme-*` - Theme management (set, next, per-app setters)
- `omarchy-cmd-*` - System commands (screenshot, screenrecord, share, audio-switch, first-run)
- `omarchy-install-*` - Installation helpers (dev-env, docker-dbs, chromium-google-account)
- `omarchy-refresh-*` - Configuration refresh (config, hyprland, waybar, hypridle)
- `omarchy-drive-*` - Drive management (select, info, set-password)
- `omarchy-update-*` - Update system (perform, available-reset, system-pkgs)
- `omarchy-hook` - Extensibility system (executes user scripts in `~/.config/omarchy/hooks/`)

## Development Workflows

### Creating a Migration

When making changes that need to be applied to existing installations:

```bash
omarchy-dev-add-migration
```

This creates a new migration file in `migrations/` named with the current git commit timestamp. Edit the migration to include necessary commands (package installations, config updates, etc.).

**Migration Structure:**
```bash
#!/bin/bash
# Brief description of what this migration does

# Example: Install new package
omarchy-pkg-add package-name

# Example: Refresh config file
omarchy-refresh-config hypr/hyprlock.conf
```

### Refreshing Configuration Files

To deploy updated config files from the repo to user's `~/.config/`:

```bash
omarchy-refresh-config <path>
```

Example: `omarchy-refresh-config hypr/hyprlock.conf`

This creates timestamped backups and shows diffs when changes occur.

### Testing Installation Changes

**Installation Environment:**
- Fresh installs use `boot.sh` which sets `OMARCHY_ONLINE_INSTALL=true`
- Repository cloned to `~/.local/share/omarchy/`
- Can specify custom repo: `OMARCHY_REPO=username/omarchy`
- Can specify custom branch: `OMARCHY_REF=branch-name`

**Testing Migrations:**
```bash
omarchy-migrate  # Run pending migrations
```

State files in `~/.local/state/omarchy/migrations/` track completion. Delete state files to re-run migrations during testing.

### Package Management

**Adding Packages:**
- Core packages: Add to `install/omarchy-base.packages`
- Optional packages: Add to `install/omarchy-other.packages`
- Pinned versions: Add to `install/packages.pinned`
- Ignored packages: Add to `install/packages.ignored`

**Installing Packages:**
```bash
omarchy-pkg-add package-name  # With verification
sudo pacman -S package-name   # Direct installation
```

### System Updates

Full update workflow:
```bash
omarchy-update-perform
    ├─> omarchy-update-time (sync system clock)
    ├─> omarchy-update-keyring (update keys)
    ├─> omarchy-update-system-pkgs (pacman -Syu)
    ├─> omarchy-migrate (run pending migrations)
    ├─> omarchy-hook post-update (user extensibility)
    └─> omarchy-update-restart (restart services)
```

### Hooks System

User extensibility via `~/.config/omarchy/hooks/`:
- `theme-set` - Called when theme changes
- `post-update` - Called after system updates
- Custom hooks can be added for new integration points

## File Locations

**Repository:** `~/.local/share/omarchy/`
**User Config:** `~/.config/`
**Theme Symlinks:** `~/.config/omarchy/current/theme/`, `~/.config/omarchy/current/background`
**State Tracking:** `~/.local/state/omarchy/migrations/`, `~/.local/state/omarchy/first-run.mode`
**Logs:** `/var/log/omarchy-install.log`

## Key Design Principles

1. **Idempotency** - Scripts can be run multiple times safely
2. **Layered Configuration** - Defaults → Theme → User overrides
3. **Modular Architecture** - Each phase is independent and loggable
4. **User Extensibility** - Hooks system for customization without forking
5. **Safety First** - Guards, backups, and error recovery throughout
6. **Migration-Based Updates** - Breaking changes handled gracefully via timestamped migrations

## Common Patterns

**Error Handling:**
All install scripts use `set -eEo pipefail` and trap-based error handling with retry/upload options.

**Logging:**
Use `run_logged` function from `install/helpers/logging.sh` to log command execution with timestamps.

**Config Deployment:**
- Copy from `config/` to `~/.config/` during install
- Use `omarchy-refresh-config` for updates
- Source defaults from `default/` in config files

**Theme Integration:**
- Add theme files for new applications to all theme directories
- Update `omarchy-theme-set` to restart new themed components
- Use symlink pattern: `~/.config/omarchy/current/theme/<app>.conf`
