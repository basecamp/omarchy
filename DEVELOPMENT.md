# Omarchy Development Guide

This document provides guidance for developers contributing to Omarchy, an Arch Linux desktop environment installer based on Hyprland.

## Overview

Omarchy is a shell-based configuration system that transforms a fresh Arch installation into a fully-configured, beautiful, and modern web development system. The codebase is primarily bash scripts organized into modular components with a robust migration system for updates.

## Architecture Overview

### Directory Structure

- **`install/`** - Modular installation scripts organized by category:
  - `preflight/` - Pre-installation checks and setup
  - `config/` - System configuration (network, timezones, login, etc.)
  - `development/` - Development tools (terminal, nvim, docker, etc.)
  - `desktop/` - Desktop environment setup (Hyprland, themes, fonts, etc.)
  - `apps/` - Application installation and configuration

- **`config/`** - User configuration files that get copied to ~/.config/
  - Contains configs for alacritty, hypr, nvim, waybar, etc.

- **`default/`** - Default/template configuration files
  - `bash/` - Bash configuration (aliases, functions, prompt, etc.)
  - `hypr/` - Default Hyprland configuration modules
  - `walker/` - Application launcher themes

- **`themes/`** - Complete theme definitions
  - Each theme directory contains configs for all themed applications
  - Themes include: catppuccin, gruvbox, nord, tokyo-night, etc.

- **`bin/`** - Utility scripts (prefixed with `omarchy-`)
  - System management, theme switching, configuration refresh tools
  - These scripts are automatically added to `$PATH` during installation
  - Available system-wide after installation for user and system management
  - Examples: `omarchy-theme-set`, `omarchy-refresh-config`, `omarchy-migrate`

- **`migrations/`** - Timestamped migration scripts for system updates
  - Named with Unix timestamps (e.g., `1751134560.sh`)

### Key Concepts

**Modular Installation**: The installation process is broken into logical phases (preflight, config, development, desktop, apps) with each phase containing multiple focused scripts.

**Theme System**: Themes are complete configuration sets that override configs for alacritty, hyprland, waybar, etc. The theme system allows switching entire visual configurations atomically.

**Configuration Management**: The system uses a layered approach where default configs are copied and then overridden by theme-specific configs.

**Migration System**: Database-style migrations allow the system to evolve while maintaining user installations through incremental update scripts.

## Migration System

### Purpose
Migrations in Omarchy are **incremental update scripts** that handle breaking changes, new features, or system adjustments that need to be applied when users update their Omarchy installation. They ensure that existing installations can evolve smoothly without manual intervention.

### How Migrations Work

1. **Naming Convention**: Migration files are named with **Unix timestamps** (e.g., `1751134560.sh`, `1754922805.sh`). This ensures they run in chronological order.

2. **Storage Locations**:
   - **Migration scripts**: `~/.local/share/omarchy/migrations/*.sh`
   - **State tracking**: `~/.local/state/omarchy/migrations/` (empty files marking completed migrations)

3. **Execution Flow**:
   - `omarchy-migrate` iterates through all migration files in timestamp order
   - For each migration file, it checks if a corresponding state file exists
   - If no state file exists → migration hasn't run → execute it and create state file
   - If state file exists → migration already completed → skip it

4. **Integration Points**:
   - **Fresh installs**: `install/preflight/migrations.sh` creates state files for ALL existing migrations (marking them as "already completed" since fresh installs don't need them)
   - **Updates**: `omarchy-update` calls `omarchy-migrate` after pulling git changes

### Types of Migration Tasks

Looking at examples:
- **Environment setup**: Adding UWSM environment variables and relaunching Hyprland
- **File updates**: Copying missing application launcher icons
- **Configuration changes**: Updating config files for new features
- **System adjustments**: Installing new packages or changing system settings

### Developer Workflow

- **Creating migrations**: `omarchy-dev-add-migration` creates a new migration file with the current git commit timestamp and opens it in nvim
- **Testing**: Developers can test migrations locally before committing

### Key Benefits

1. **Incremental updates**: Only new changes get applied
2. **Idempotent**: Running migrations multiple times is safe
3. **Chronological order**: Timestamp naming ensures proper sequencing
4. **Fresh install optimization**: New installations skip all historical migrations
5. **Rollback protection**: Once a migration runs, it won't run again

This is essentially a **database-style migration system applied to system configuration**, allowing Omarchy to evolve over time while maintaining existing user installations seamlessly.

## Development Workflow

### Making Changes

1. **Edit files** in their respective directories (config/, default/, themes/, etc.)
2. **Test locally** using `omarchy-refresh-*` commands to reload configurations without restarting
3. **Add migrations** using `omarchy-dev-add-migration` for breaking changes that affect existing installations
4. **Test migrations** by running `omarchy-migrate` locally
5. **Commit changes** following the project's git workflow

### Code Quality Standards

#### Shell Script Best Practices

- **Use shellcheck**: All shell scripts should pass `shellcheck` analysis
  ```bash
  shellcheck install/**/*.sh bin/omarchy-* migrations/*.sh
  ```
- **Set error handling**: Use `set -e` for scripts that should fail fast
- **Quote variables**: Always quote variables to prevent word splitting
- **Use proper shebangs**: Start scripts with `#!/bin/bash`
- **Handle cd failures**: Always check that `cd` commands succeed (see SC2164 below)

#### Shellcheck Warning Suppressions

When shellcheck warnings are false positives or intentional, suppress them with explanatory comments:

**Common Legitimate Suppressions:**

- **SC2016** - Intentional literal variables in output:
  ```bash
  # shellcheck disable=SC2016  # We want literal $HOME and $PATH in the output
  echo 'export PATH="$HOME/.config/composer/vendor/bin:$PATH"' >>"$HOME/.bashrc"
  ```

- **SC1090** - Dynamic source files that can't be statically analyzed:
  ```bash
  # shellcheck source=/dev/null
  source "$file"
  ```

- **SC2034** - Intentionally unused variables (e.g., for future use):
  ```bash
  # shellcheck disable=SC2034  # Used by sourced scripts
  VARIABLE="value"
  ```

- **SC2086** - When word splitting is intentional:
  ```bash
  # shellcheck disable=SC2086  # Word splitting intended for args
  command $args_that_should_split
  ```

**Critical Warning - SC2164 (cd failures):**

The `cd` command can fail for many reasons and continuing execution in the wrong directory is dangerous:

```bash
# WRONG - dangerous if cd fails
cd /some/directory
rm -rf *  # Could delete files in wrong location!

# CORRECT - safe error handling
cd /some/directory || exit
rm -rf *

# ALTERNATIVE - use subshell to avoid changing working directory
(
  cd /some/directory || exit
  rm -rf *
)
```

**Why SC2164 fixes are critical:**
- **Security**: Operations in wrong directory can modify/delete unintended files
- **Data loss**: File operations may target wrong locations
- **Silent failures**: Scripts continue running with broken assumptions
- **Debugging**: Failures are hard to trace when directory context is lost

**Common cd failure causes:**
- Directory doesn't exist
- No permission to access directory  
- Path is a file, not a directory
- Network issues (mounted directories)
- Disk space/filesystem problems

**Important Guidelines:**
- Always include a comment explaining **why** the suppression is safe
- Only suppress warnings when the behavior is intentional, not to hide problems
- Prefer fixing the underlying issue over suppression when possible

#### Chroot Compatibility

The install scripts are designed to work in chroot environments (for automated system building). Key considerations:

- **Centralized chroot detection**: The `is_chroot()` function is available from the main `install.sh` script
  - Detects chroot via `CHROOT` environment variable, `/proc/1/root` accessibility, or filesystem comparison
- **Conditional execution patterns**:
  - For `systemctl`: Remove `--now` flag in chroot (services can't start)
  - For `ufw`: Skip firewall configuration entirely in chroot
  - For `reboot`: Show completion message instead of rebooting in chroot
- **Implementation example**:
  ```bash
  if is_chroot; then
    echo "⚠️  [CHROOT] Enabling service (without --now flag)"
    sudo systemctl enable service-name
  else
    sudo systemctl enable --now service-name
  fi
  ```
- **Test in chroot**: Set `CHROOT=1` environment variable to simulate chroot behavior

#### Configuration Files

The system manages configuration for:
- **Hyprland** (window manager)
- **Waybar** (status bar)
- **Alacritty** (terminal)
- **Walker** (application launcher)
- **Mako** (notifications)
- **Neovim** (editor)
- **Bash** (shell environment)

Most configs support theming and can be refreshed without restarting the desktop session.

### Theme Development

1. **Create theme directory** in `themes/` with descriptive name
2. **Include all application configs** that should change with the theme
3. **Follow naming conventions** used by existing themes
4. **Test theme switching** using `omarchy-theme-set <theme-name>`
5. **Update theme list** if adding new themes

### Testing

#### Local Testing
- Use `omarchy-refresh-*` commands to reload configurations
- Test theme switching with `omarchy-theme-set`
- Verify migrations run correctly with `omarchy-migrate`

#### Chroot Testing
```bash
# Simulate chroot environment
CHROOT=1 bash install.sh

# Test chroot detection
CHROOT=1 bash -c 'source install.sh && is_chroot && echo "Chroot detected" || echo "Not in chroot"'

# Test individual installation scripts in chroot mode
CHROOT=1 bash install/config/network.sh
CHROOT=1 bash install/development/firewall.sh
```

### Key Commands for Developers

#### Installation and Updates
- `bash install.sh` - Main installation script
- `omarchy-update` - Update Omarchy (git pull, migrations, system packages, restart services)
- `omarchy-migrate` - Run pending migrations

#### Development Tools
- `omarchy-dev-add-migration` - Add a new migration script
- `omarchy-install-dev-env` - Install development environment tools

#### Configuration Management
- `omarchy-refresh-config` - Refresh all configuration files
- `omarchy-refresh-hyprland` - Refresh Hyprland config
- `omarchy-refresh-waybar` - Refresh Waybar config

#### Theme Management
- `omarchy-theme-list` - List available themes
- `omarchy-theme-set <theme-name>` - Set the active theme
- `omarchy-theme-current` - Show current theme

## Contributing Guidelines

1. **Follow existing patterns**: Study how similar functionality is implemented
2. **Use existing utilities**: Leverage the bin/ scripts and helper functions
3. **Test thoroughly**: Verify changes work in both normal and chroot environments
4. **Document breaking changes**: Create migrations for changes that affect existing installations
5. **Run shellcheck**: Ensure all shell scripts pass static analysis
6. **Keep changes atomic**: Each commit should represent a single logical change

## Security Considerations

- **Never commit secrets**: Use environment variables or user prompts for sensitive data
- **Validate user input**: Sanitize any user-provided data in scripts
- **Use sudo judiciously**: Only elevate privileges when necessary
- **Follow principle of least privilege**: Scripts should only modify what they need to

## Dependencies

### Runtime Dependencies
- Arch Linux base system
- `yay` (AUR helper)
- `git` for updates and version control
- Standard shell utilities (`bash`, `awk`, `sed`, etc.)

### Development Dependencies
- `shellcheck` for script analysis
- `nvim` for editing (used by development scripts)
- `gum` for interactive prompts in some utilities

## Troubleshooting

### Common Issues
- **Permission errors**: Ensure proper sudo usage in install scripts
- **Missing dependencies**: Check that required packages are installed before use
- **Chroot failures**: Verify chroot detection is working with `CHROOT=1` testing
- **Migration failures**: Check migration state files in `~/.local/state/omarchy/migrations/`

### Debugging
- **Verbose output**: Add `set -x` to scripts for detailed execution tracing
- **Check logs**: Many operations log to system journals
- **Test incrementally**: Run individual install scripts rather than full installation

## Resources

- **Community Discord**: https://discord.gg/tXFUdasqhY
- **Manual**: https://manuals.omamix.org/2/the-omarchy-manual
- **Hyprland Wiki**: https://wiki.hypr.land/
- **Arch Wiki**: https://wiki.archlinux.org/
