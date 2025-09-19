# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Core Update and Maintenance
- `omarchy-update` - Main update command that creates a snapshot, pulls latest changes, and performs update
- `omarchy-update-git` - Pull latest changes from the Git repository
- `omarchy-update-perform` - Run system updates including packages and migrations
- `omarchy-migrate` - Run pending database migrations from `migrations/` directory
- `omarchy-snapshot create` - Create a system snapshot before major changes

### Development
- `omarchy-dev-add-migration` - Create a new migration file with current git timestamp
- `bash install.sh` - Run the full installation process (sources from `$OMARCHY_INSTALL/` subdirectories)
- `bash boot.sh` - Initial bootstrap script for curl installations (online mode)

### Theme Management
- `omarchy-theme-list` - List all available themes
- `omarchy-theme-current` - Show current active theme
- `omarchy-theme-next` - Switch to next theme in rotation
- `omarchy-theme-install <theme>` - Install a specific theme

### State Management
- `omarchy-state set <name>` - Set a state flag in `~/.local/state/omarchy/`
- `omarchy-state clear <pattern>` - Clear state flags matching pattern

### System Restarts
- `omarchy-restart-waybar` - Restart Waybar
- `omarchy-restart-walker` - Restart Walker launcher
- `omarchy-restart-wifi` - Restart WiFi
- `omarchy-restart-bluetooth` - Restart Bluetooth

## Architecture

### Installation Framework
Omarchy uses a modular shell script installation system organized into phases:

1. **Helpers** (`install/helpers/`) - Logging, error handling, presentation utilities
2. **Preflight** (`install/preflight/`) - Environment checks, guards, initial setup
3. **Packaging** (`install/packaging/`) - Package installation (base, fonts, icons, webapps, TUIs)
4. **Config** (`install/config/`) - System configuration, hardware-specific fixes
5. **Login** (`install/login/`) - Boot loader, Plymouth, display manager setup
6. **Post-install** (`install/post-install/`) - Final steps and cleanup

Each phase sources an `all.sh` file that includes individual scripts. Installation paths are defined as:
- `$OMARCHY_PATH` = `~/.local/share/omarchy`
- `$OMARCHY_INSTALL` = `$OMARCHY_PATH/install`

### Migration System
- Migrations are timestamped shell scripts in `migrations/` (format: `{unix_timestamp}.sh`)
- State tracked in `~/.local/state/omarchy/migrations/`
- Each migration runs once; failed migrations can be skipped
- New migrations created with git commit timestamp via `omarchy-dev-add-migration`

### Theme System
Themes are complete configuration sets in `themes/` containing:
- Window manager configs (Hyprland)
- Terminal configs (Alacritty, Kitty, Ghostty)
- UI component styling (Waybar, Walker, SwayOSD)
- Editor themes (Neovim, VSCode)
- Wallpapers in `backgrounds/`

Each theme provides consistent styling across all applications.

### Binary Scripts
Utility scripts in `bin/` follow naming pattern `omarchy-{category}-{action}`:
- `omarchy-cmd-*` - User commands (screenshot, screenrecord, etc.)
- `omarchy-install-*` - Component installers
- `omarchy-setup-*` - System setup utilities
- `omarchy-refresh-*` - Refresh without restart
- `omarchy-restart-*` - Service restarts

### State Management
Omarchy tracks state using filesystem flags:
- State files in `~/.local/state/omarchy/`
- Migration completion in `~/.local/state/omarchy/migrations/`
- Simple touch/delete file operations for boolean states