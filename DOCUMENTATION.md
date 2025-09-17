# Omarchy Documentation

## Overview

Omarchy is an opinionated Arch Linux distribution that transforms a fresh Arch installation into a fully-configured, beautiful, and modern web development system based on Hyprland. It provides a complete desktop environment with carefully selected applications and configurations optimized for development work.

## Table of Contents

- [Architecture](#architecture)
- [Installation](#installation)
- [Migration System](#migration-system)
- [Configuration Management](#configuration-management)
- [Package Management](#package-management)
- [Themes](#themes)
- [Command Reference](#command-reference)
- [Development](#development)
- [File Structure](#file-structure)

## Architecture

Omarchy follows a modular architecture with several key components:

### Core Components

1. **Installation System** (`install/`): Handles the initial setup and configuration
2. **Migration System** (`migrations/`): Manages system updates and configuration changes
3. **Configuration Management** (`config/`): Centralized configuration files for all applications
4. **Command Interface** (`bin/`): Collection of utility scripts for system management
5. **Theme System** (`themes/`): Modular theme support for consistent visual styling

### Directory Structure

```
omarchy/
├── applications/          # Desktop application configurations
├── bin/                  # Utility commands and scripts
├── config/               # Configuration files for all applications
├── default/              # Default settings and configurations
├── install/              # Installation scripts and procedures
├── migrations/           # Database-style migration scripts
├── themes/              # Theme definitions and assets
├── boot.sh              # Initial bootstrap script
└── install.sh           # Main installation script
```

## Installation

### Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/afpp3/omarchy/master/install.sh | bash
```

### Custom Installation

You can customize the installation using environment variables:

```bash
# Use a custom repository
OMARCHY_REPO="your-username/omarchy-fork" bash install.sh

# Use a specific branch
OMARCHY_REF="development" bash install.sh

# Combine both
OMARCHY_REPO="your-username/omarchy-fork" OMARCHY_REF="custom-branch" bash install.sh
```

### Installation Process

1. **Preflight Checks**: System validation and environment setup
2. **Package Installation**: Install core packages and dependencies
3. **Configuration**: Apply system-wide configurations
4. **Theme Setup**: Install and configure the default theme
5. **Finalization**: Complete setup and prepare for reboot

## Migration System

Omarchy uses a database-style migration system to manage system updates and configuration changes over time. This ensures that systems can be updated incrementally without breaking existing configurations.

### How Migrations Work

1. **Migration Files**: Located in `migrations/`, named with Unix timestamps (e.g., `1751134560.sh`)
2. **State Tracking**: Completed migrations are tracked in `~/.local/state/omarchy/migrations/`
3. **Execution Order**: Migrations run in chronological order based on their timestamp
4. **Error Handling**: Failed migrations can be skipped or retried

### Migration File Format

Each migration is a bash script that performs specific system changes:

```bash
#!/bin/bash
echo "Description of what this migration does"

# Migration logic here
omarchy-pkg-install new-package
omarchy-refresh-config some-app

# Optional: Handle migration-specific requirements
if some_condition; then
    # Do something
fi
```

### How to Generate Migrations

To create a new migration during development:

```bash
omarchy-dev-add-migration
```

This command:
1. Creates a new migration file with a timestamp-based name
2. Opens the file in your default editor (nvim)
3. Places the file in the correct migrations directory

**Example workflow:**
```bash
# Navigate to your omarchy development directory
cd ~/.local/share/omarchy

# Create a new migration
omarchy-dev-add-migration

# This creates a file like: migrations/1234567890.sh
# Edit the file to add your migration logic
```

### Running Migrations

Migrations are typically run automatically during updates, but can be run manually:

```bash
omarchy-migrate
```

This command:
- Scans all migration files in chronological order
- Skips migrations that have already been run
- Executes pending migrations
- Tracks completion state
- Handles failures gracefully with user prompts

### Migration State Management

- **Completed**: `~/.local/state/omarchy/migrations/[migration-name].sh`
- **Skipped**: `~/.local/state/omarchy/migrations/skipped/[migration-name].sh`

### Migration Best Practices

1. **Idempotent**: Migrations should be safe to run multiple times
2. **Descriptive**: Include clear echo statements explaining what's happening
3. **Error Handling**: Use proper exit codes and error messages
4. **Testing**: Test migrations on clean systems before deployment
5. **Reversible**: Consider how changes can be undone if needed

### Common Migration Patterns

**Package Installation:**
```bash
echo "Installing new development tools"
omarchy-pkg-install package-name
```

**Configuration Updates:**
```bash
echo "Updating application configuration"
omarchy-refresh-config app-name
```

**Service Management:**
```bash
echo "Restarting system services"
omarchy-restart-app service-name
```

**Conditional Changes:**
```bash
echo "Applying conditional updates"
if [[ -f ~/.config/some-app/config ]]; then
    # Update existing configuration
    sed -i 's/old/new/' ~/.config/some-app/config
fi
```

## Configuration Management

### Configuration Refresh System

Omarchy provides a centralized configuration management system through `omarchy-refresh-config` commands:

- `omarchy-refresh-hyprland`: Update Hyprland window manager configuration
- `omarchy-refresh-waybar`: Update status bar configuration
- `omarchy-refresh-walker`: Update application launcher configuration
- And many more...

### Configuration Structure

All configuration files are stored in `config/` and organized by application:

```
config/
├── alacritty/           # Terminal emulator
├── hypr/               # Hyprland window manager
├── nvim/               # Neovim editor
├── waybar/             # Status bar
├── walker/             # Application launcher
└── ...
```

## Package Management

### Package Installation Commands

- `omarchy-pkg-install`: Install packages with dependency resolution
- `omarchy-pkg-remove`: Remove packages safely
- `omarchy-pkg-present`: Check if packages are installed
- `omarchy-pkg-missing`: List missing packages
- `omarchy-pkg-aur-install`: Install AUR packages

### Package Lists

- `install/packages.sh`: Core system packages
- `install/packages.pinned`: Packages that should not be updated
- `install/packages.ignored`: Packages to exclude from installations

## Themes

Omarchy supports multiple themes located in the `themes/` directory:

### Available Themes

- Catppuccin (default)
- Catppuccin Latte
- Everforest
- Gruvbox
- Kanagawa
- Matte Black
- Nord
- Osaka Jade
- Ristretto
- Rose Pine
- Tokyo Night

### Theme Management Commands

- `omarchy-theme-list`: List available themes
- `omarchy-theme-set <theme>`: Apply a specific theme
- `omarchy-theme-next`: Cycle to the next theme
- `omarchy-theme-current`: Show current theme
- `omarchy-theme-install <theme>`: Install a new theme
- `omarchy-theme-remove <theme>`: Remove a theme

## Command Reference

### System Management

- `omarchy-update`: Update the entire system
- `omarchy-migrate`: Run pending migrations
- `omarchy-version`: Show current version
- `omarchy-state`: Show system state information

### Application Management

- `omarchy-restart-app <app>`: Restart specific applications
- `omarchy-refresh-applications`: Refresh desktop application cache
- `omarchy-launch-browser`: Launch default browser
- `omarchy-webapp-install <url>`: Install web applications

### Development Tools

- `omarchy-dev-add-migration`: Create a new migration file
- `omarchy-install-dev-env`: Set up development environment
- `omarchy-install-docker-dbs`: Install Docker database containers

### Hardware and System

- `omarchy-setup-fingerprint`: Configure fingerprint authentication
- `omarchy-setup-fido2`: Configure FIDO2 authentication
- `omarchy-battery-monitor`: Monitor battery status
- `omarchy-toggle-nightlight`: Toggle blue light filter

### Screenshots and Recording

- `omarchy-cmd-screenshot`: Take screenshots
- `omarchy-cmd-screenrecord`: Start screen recording
- `omarchy-cmd-screenrecord-stop`: Stop screen recording

## Development

### Setting Up a Development Environment

1. Clone the repository:
```bash
git clone https://github.com/afpp3/omarchy.git ~/.local/share/omarchy
```

2. Add to your PATH:
```bash
export PATH="$HOME/.local/share/omarchy/bin:$PATH"
```

3. Create development migrations:
```bash
omarchy-dev-add-migration
```

### Contributing Guidelines

1. **Test Migrations**: Always test migrations on a clean system
2. **Follow Naming**: Use descriptive names for migration files
3. **Document Changes**: Include clear descriptions in migration scripts
4. **Error Handling**: Implement proper error handling and recovery
5. **Idempotent Operations**: Ensure migrations can be run multiple times safely

### Development Workflow

1. Make changes to configuration files or scripts
2. Create a migration to apply changes to existing systems
3. Test the migration on a development system
4. Submit pull request with both changes and migration

## File Structure

### Key Files

- `boot.sh`: Initial bootstrap script that clones the repository and starts installation
- `install.sh`: Main installation orchestrator that sources all installation components
- `bin/omarchy-*`: Individual command scripts for system management
- `migrations/*.sh`: Timestamped migration scripts for system updates

### Configuration Directories

- `config/`: Template configurations for all applications
- `applications/`: Desktop application definitions and icons
- `themes/`: Theme definitions with color schemes and styling
- `default/`: Default settings and fallback configurations

### Installation Components

- `install/preflight/`: Pre-installation checks and setup
- `install/config/`: Configuration application scripts
- `install/packaging/`: Package installation and management
- `install/login/`: Login manager and boot configuration

This documentation provides a comprehensive overview of the Omarchy system. For specific implementation details, refer to the individual script files in the repository.