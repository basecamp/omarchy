# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Development Commands

### Installation and Setup
```bash
# Bootstrap Omarchy from remote (production install)
bash <(curl -s https://raw.githubusercontent.com/basecamp/omarchy/master/boot.sh)

# Local development install (from cloned repo)
source install.sh

# Run migrations after updates
omarchy-migrate

# Update Omarchy from git
omarchy-update-git
omarchy-update-perform

# Check update status and system information
omarchy-update-available
omarchy-state
```

### Development Tools
```bash
# Add a new migration (creates timestamped migration file)
omarchy-dev-add-migration

# Test individual installation scripts
bash install/packaging/base.sh
bash install/config/theme.sh

# State management for migrations and features
omarchy-state set feature-name
omarchy-state clear pattern-*

# Take system snapshots
omarchy-snapshot
```

### Package Management
```bash
# Interactive package installation with fzf
omarchy-pkg-install

# AUR package management
omarchy-pkg-aur-install package-name
omarchy-pkg-aur-accessible

# Package operations
omarchy-pkg-add package-name      # Add to tracking
omarchy-pkg-remove package-name   # Remove package
omarchy-pkg-drop package-name     # Remove from tracking

# Package status
omarchy-pkg-pinned                # List pinned packages
omarchy-pkg-ignored               # List ignored packages
omarchy-pkg-missing               # Show missing packages
omarchy-pkg-present               # Show present packages
```

### Theme and Configuration Management
```bash
# Theme operations
omarchy-theme-list                # List available themes
omarchy-theme-set theme-name      # Set active theme
omarchy-theme-next                # Cycle to next theme
omarchy-theme-current             # Show current theme
omarchy-theme-install             # Install new theme
omarchy-theme-remove theme-name   # Remove theme

# Configuration refresh
omarchy-refresh-config hypr/hyprlock.conf  # Refresh specific config
omarchy-refresh-applications               # Refresh app registrations
omarchy-refresh-hyprland                   # Reload Hyprland config
omarchy-refresh-waybar                     # Refresh status bar

# Font management
omarchy-font-list                          # List available fonts
omarchy-font-set font-name                 # Set system font
omarchy-font-current                       # Show current font
```

### System Management
```bash
# Service restarts
omarchy-restart-waybar            # Restart status bar
omarchy-restart-hypridle          # Restart idle daemon
omarchy-restart-bluetooth         # Restart Bluetooth
omarchy-restart-wifi              # Restart network

# System utilities
omarchy-lock-screen               # Lock the screen
omarchy-toggle-idle               # Toggle idle management
omarchy-toggle-nightlight         # Toggle blue light filter

# Hardware management
omarchy-drive-select              # Select and mount drives
omarchy-drive-info                # Show drive information
```

### WebApp Management
```bash
# Install web applications as desktop apps
omarchy-webapp-install            # Interactive webapp installer
omarchy-webapp-install "App Name" https://url.com icon.png

# Launch webapps
omarchy-launch-webapp https://url.com
omarchy-launch-or-focus-webapp app-name
```

## High-Level Architecture

**Omarchy** is a comprehensive Arch Linux system configuration framework that transforms a fresh Arch installation into a fully-configured Hyprland-based development environment.

### Core Components

- **`install.sh`**: Main installation orchestrator that sources modular installation scripts
- **`boot.sh`**: Remote bootstrap script that clones the repo and initiates installation
- **`bin/omarchy-*`**: 80+ command-line utilities organized by function (cmd-, install-, launch-, pkg-, refresh-, restart-, theme-)
- **`install/`**: Modular installation scripts organized by category with dependency management
- **`migrations/`**: Timestamped migration scripts with automatic state tracking
- **`config/`**: Configuration templates that get deployed to `~/.config/`
- **`default/`**: Fallback configurations and Hyprland bindings

### Installation Pipeline

1. **Preflight** (`install/preflight/`): System validation, pacman updates, migration state check, first-run mode detection
2. **Packaging** (`install/packaging/`): Base packages (150+ from `omarchy-base.packages`), fonts, icons, TUI tools, webapp creation
3. **Configuration** (`install/config/`): Theme deployment, hardware fixes (Apple T2, networking, Bluetooth), development setup
4. **Login Setup** (`install/login/`): SDDM configuration, Plymouth boot screens, keyring setup, Limine integration
5. **Post-Install** (`install/post-install/`): Final pacman cleanup, reboot preparation, completion reporting

### Logging and Execution System

- **`install/helpers/logging.sh`**: Sophisticated logging with real-time display, timing analysis, and failure handling
- **`run_logged()`**: Executes scripts in clean subshells with full logging to `/var/log/omarchy-install.log`
- **Installation timing**: Tracks both Archinstall and Omarchy phases with minute/second breakdowns
- **Live monitoring**: Real-time log display during installation with ANSI formatting

### Migration System Architecture

- **Naming Convention**: Unix timestamps (e.g., `1751134562.sh`) for chronological ordering
- **State Tracking**: Empty files in `~/.local/state/omarchy/migrations/` mark completed migrations
- **Skip Handling**: Failed migrations can be skipped and tracked separately in `skipped/` subdirectory
- **Migration Patterns**: System updates, config fixes, hardware-specific adjustments, package installations

### Theme and Configuration Management

- **Dynamic Theming**: Symlink-based system with `~/.config/omarchy/current/theme` pointing to active theme
- **Configuration Deployment**: `omarchy-refresh-config` copies templates from `config/` to `~/.config/` with backup creation
- **Multi-Application Theming**: Coordinated theming across Hyprland, waybar, terminal, browser, VS Code, and desktop environment
- **Theme Switching**: Single command (`omarchy-theme-set`) updates all applications and restarts necessary services

### Package Management Integration

- **Interactive Installation**: `omarchy-pkg-install` uses fzf for package selection with live previews
- **Package Tracking**: Separate commands for adding (`omarchy-pkg-add`) vs installing vs removing from tracking (`omarchy-pkg-drop`)
- **AUR Support**: Dedicated AUR package management with accessibility checking
- **State Queries**: Commands to check package status (pinned, ignored, missing, present)

### WebApp Integration System

- **Desktop Integration**: `omarchy-webapp-install` creates `.desktop` files with custom icons and MIME type handling
- **Icon Management**: Automatic icon downloading with local caching in `~/.local/share/applications/icons/`
- **Launch System**: Specialized launchers for different webapp types with custom handlers (e.g., Zoom, HEY email)
- **Default Apps**: Pre-configured webapps for common services (GitHub, ChatGPT, Discord, etc.)

### Command Organization Patterns

- **`omarchy-cmd-*`**: System commands (screenshot, audio switching, window management)
- **`omarchy-install-*`**: Application installers (VS Code, Docker, Tailscale, development environments)
- **`omarchy-launch-*`**: Application launchers with focus management
- **`omarchy-refresh-*`**: Configuration reloaders for specific services
- **`omarchy-restart-*`**: Service restart utilities
- **`omarchy-theme-*`**: Theme management and application

### File Structure and State Management

- **Runtime State**: `~/.local/state/omarchy/` for migrations, feature flags, and persistent state
- **Configuration Deployment**: `~/.config/omarchy/current/` for active theme symlinks
- **Resource Storage**: `~/.local/share/omarchy/` for binaries, configs, and repository data
- **Backup Strategy**: Timestamped backups for configuration files during updates
- **Hook System**: User-customizable hooks in `~/.config/omarchy/hooks/` for extending functionality

The system uses a reproducible, declarative approach with strong separation between templates, active configs, and user state, enabling safe updates and rollbacks.
