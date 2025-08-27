# Installation Script Modifications

## Changes Made

### 1. Modified `install/packages.sh`
- Added a function `is_installed()` to check if a package is already installed
- Created arrays to track all packages and only install missing ones
- The script now checks each package individually and only installs those not already present
- Uses `pacman -Q` to determine if a package is installed

### 2. Modified `install/config/config.sh`
- Changed to replace existing Hyprland configurations with Omarchy versions
- Removes existing Hyprland configs before installing fresh Omarchy configs
- Focuses on Hyprland, Waybar, SwayOSD, Walker, and Mako configurations
- Preserves environment configuration and bashrc
- Includes most application-specific configs except for starship and neovim
- Avoids copying only starship and neovim configurations as requested

### 3. Added `install/config/hyprland-config.sh`
- New specialized script that replaces existing Hyprland configurations with Omarchy versions
- Removes existing configs before installing fresh Omarchy configs
- Includes refreshing of Hyprland services after installation
- Can be run separately to update only Hyprland configurations
- Includes most application-specific configs except for starship and neovim

### 4. Added `custom-install.sh`
- New all-in-one installation script that combines the functionality of multiple scripts
- Provides a dry run option to show what would be done without making changes
- Allows for selection of optional packages and web applications
- Properly handles the installation of themes to avoid dependency on the original download location
- Separates required packages from optional ones
- Gives individual control over each optional application installation
- Features optional installation of web apps including:
  - Figma, Zoom, Discord, GitHub, YouTube
  - ChatGPT, Grok
  - Google services (Contacts, Photos, Mail, Drive, Docs, Calendar)
  - WhatsApp, Basecamp, Hey
- Includes optional installation of Neovim and Starship prompt with their configurations

## Usage

### Standard Installation Scripts
When you run the standard installation script:
1. It will check if each package is already installed
2. Only install packages that are missing
3. Replace your existing Hyprland configuration with Omarchy configurations
4. Include most application-specific configs except for starship and neovim

To use the specialized Hyprland configuration script:
```bash
./install/config/hyprland-config.sh
```

### Custom Installation Script
The new custom installation script provides more flexibility:

```bash
./custom-install.sh            # Run with interactive prompts
./custom-install.sh --dry-run  # Show what would be done without making changes
./custom-install.sh -n         # Short form for dry run
```

This script:
1. Prompts for dry run mode to preview changes without modifying anything
2. Installs required Hyprland packages automatically
3. Asks about each optional web application individually
4. Properly sets up the theme structure by:
   - Copying themes to ~/.local/share/omarchy/themes/
   - Creating proper symlinks to ~/.config/omarchy/themes/
5. Offers optional installation of Neovim and Starship prompt
6. Fixes common installation issues automatically

This approach ensures that:
- You don't reinstall packages you already have
- Your existing Hyprland setup is completely replaced with Omarchy configurations
- Configuration files are installed with preference for Omarchy setup
- Services are properly refreshed after configuration changes
- You have full control over which optional components are installed
- The installation is not dependent on the original download location