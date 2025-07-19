# Omarchy User Guide for LLMs

## Overview

Omarchy is an Arch Linux setup script that transforms a minimal Arch Linux installation into a fully-configured desktop environment. It's designed to be installable via `install.sh` and provides a modern, beautiful, and functional desktop experience using Hyprland (Wayland compositor) with a carefully curated set of applications and utilities.

## Installation

To install Omarchy, run:
```bash
bash ~/.local/share/omarchy/install.sh
```

The installation process includes automatic package installation, configuration deployment, and system optimization.

## Desktop Environment

Omarchy uses:
- **Window Manager**: Hyprland (Wayland-based tiling window manager)
- **Status Bar**: Waybar
- **Application Launcher**: Wofi
- **Notifications**: Mako
- **Terminal**: Alacritty
- **File Manager**: Nautilus
- **Web Browser**: Chromium

## Installed Applications

### Core Desktop Applications
- **Alacritty** - Modern terminal emulator
- **Chromium** - Primary web browser (with Wayland support)
- **Nautilus** - GNOME file manager with Sushi previews
- **MPV** - Media player for video files
- **Imv** - Image viewer for all image formats
- **Evince** - PDF viewer
- **Signal Desktop** - Secure messaging
- **Obsidian** - Note-taking and knowledge management
- **1Password** - Password manager

### Office & Productivity (if not OMARCHY_BARE)
- **LibreOffice** - Full office suite
- **GNOME Calculator** - System calculator
- **Xournalpp** - Handwriting and PDF annotation
- **Pinta** - Simple image editor (optional)
- **Typora** - Markdown editor (optional)

### Development Tools
- **Neovim** - Modern text editor with LazyVim configuration
- **Git** - Version control with helpful aliases
- **GitHub CLI** - Command-line interface for GitHub
- **Docker** - Containerization platform with Docker Compose
- **Lazygit** - Terminal UI for Git
- **Lazydocker** - Terminal UI for Docker
- **Cargo** - Rust package manager
- **Mise** - Runtime version manager
- **Clang/LLVM** - C/C++ compiler

### Terminal Utilities
- **Eza** - Modern replacement for `ls`
- **Fzf** - Fuzzy finder
- **Ripgrep** - Fast text search
- **Fd** - User-friendly find replacement
- **Bat** - Cat replacement with syntax highlighting
- **Zoxide** - Smart directory navigation
- **Btop** - Resource monitor
- **Fastfetch** - System information display
- **Tldr** - Simplified man pages

### Media & Graphics
- **OBS Studio** - Screen recording and streaming
- **Kdenlive** - Video editing
- **LocalSend** - File sharing across devices

### Optional Applications (Xtras)
- **Spotify** - Music streaming
- **Dropbox** - Cloud storage
- **Zoom** - Video conferencing

### Web Applications (automatically created)
- **HEY** - Email service
- **Basecamp** - Project management
- **WhatsApp Web** - Messaging
- **Google Photos** - Photo storage
- **Google Contacts** - Contact management
- **Google Messages** - SMS from web
- **ChatGPT** - AI assistant
- **YouTube** - Video platform
- **GitHub** - Code hosting
- **X (Twitter)** - Social media

## Hyprland Keyboard Shortcuts

### Window Management
- `SUPER + W` - Close active window
- `SUPER + V` - Toggle floating mode
- `SUPER + J` - Toggle split direction
- `SUPER + P` - Enable pseudo-tiling

### Navigation
- `SUPER + Arrow Keys` - Move focus between windows
- `SUPER + 1-9,0` - Switch to workspace 1-10
- `SUPER + SHIFT + 1-9,0` - Move window to workspace 1-10
- `SUPER + SHIFT + Arrow Keys` - Swap windows
- `SUPER + Mouse Scroll` - Switch workspaces

### Window Resizing
- `SUPER + -` - Decrease window width
- `SUPER + =` - Increase window width
- `SUPER + SHIFT + -` - Decrease window height
- `SUPER + SHIFT + =` - Increase window height
- `SUPER + Mouse Drag` - Move window
- `SUPER + Right Mouse Drag` - Resize window

### Application Launching
- `SUPER + Return` - Open terminal (Alacritty)
- `SUPER + Space` - Application launcher (Wofi)
- `SUPER + F` - File manager (Nautilus)
- `SUPER + B` - Web browser (Chromium)
- `SUPER + N` - Neovim in terminal
- `SUPER + T` - System monitor (btop)
- `SUPER + D` - Docker manager (lazydocker)
- `SUPER + M` - Music (Spotify)
- `SUPER + G` - Messaging (Signal)
- `SUPER + O` - Notes (Obsidian)
- `SUPER + /` - Password manager (1Password)

### Web Application Shortcuts
- `SUPER + A` - ChatGPT
- `SUPER + SHIFT + A` - Grok
- `SUPER + C` - HEY Calendar
- `SUPER + E` - HEY Email
- `SUPER + Y` - YouTube
- `SUPER + SHIFT + G` - WhatsApp Web
- `SUPER + ALT + G` - Google Messages
- `SUPER + X` - X (Twitter)
- `SUPER + SHIFT + X` - Compose Tweet

### System Controls
- `SUPER + Escape` - Power menu (lock, suspend, restart, shutdown)
- `SUPER + K` - Show keybindings help
- `SUPER + CTRL + I` - Toggle idle/auto-lock

### Media Controls
- `F1-F12` (Function Keys) - Standard media controls (volume, brightness)
- `XF86AudioRaiseVolume/LowerVolume` - Volume up/down
- `XF86AudioMute` - Toggle mute
- `XF86MonBrightnessUp/Down` - Screen brightness
- `XF86AudioPlay/Pause` - Media playback control

### Screenshots
- `Print Screen` - Screenshot selection
- `SHIFT + Print Screen` - Screenshot window
- `CTRL + Print Screen` - Screenshot entire screen
- `SUPER + Print Screen` - Color picker

### Aesthetics & Themes
- `SUPER + SHIFT + Space` - Refresh Waybar
- `SUPER + CTRL + Space` - Next background
- `SUPER + SHIFT + CTRL + Space` - Theme menu

### Notifications
- `SUPER + ,` - Dismiss notification
- `SUPER + SHIFT + ,` - Dismiss all notifications
- `SUPER + CTRL + ,` - Toggle do-not-disturb mode

### Apple Display Controls (if available)
- `CTRL + F1` - Decrease external display brightness
- `CTRL + F2` - Increase external display brightness
- `SHIFT + CTRL + F2` - Maximum external display brightness

## Shell Aliases and Functions

### File System Navigation
- `ls` → `eza -lh --group-directories-first --icons=auto`
- `lsa` → `ls -a` (list all files including hidden)
- `lt` → `eza --tree --level=2 --long --icons --git` (tree view)
- `lta` → `lt -a` (tree view with hidden files)
- `cd` → `zd` (smart directory navigation with zoxide)
- `..` → `cd ..`
- `...` → `cd ../..`
- `....` → `cd ../../..`

### Tool Shortcuts
- `n` → `nvim` (Neovim)
- `g` → `git`
- `d` → `docker`
- `r` → `rails`
- `ff` → `fzf --preview 'bat --style=numbers --color=always {}'` (fuzzy file finder with preview)

### Git Shortcuts
- `gcm` → `git commit -m`
- `gcam` → `git commit -a -m`
- `gcad` → `git commit -a --amend`

Predefined git aliases (set automatically):
- `git co` → `git checkout`
- `git br` → `git branch`
- `git ci` → `git commit`
- `git st` → `git status`

### Package Management
- `yayf` → Interactive package search and installation with preview

### Utility Functions
- `compress <directory>` - Create tar.gz archive
- `decompress <file.tar.gz>` - Extract tar.gz archive
- `iso2sd <iso_file> <device>` - Write ISO to SD card/USB
- `web2app <Name> <URL> <IconURL>` - Create desktop app from website
- `web2app-remove <Name>` - Remove web app
- `refresh-xcompose` - Reload text expansion shortcuts
- `open <file>` - Open file with default application

## Text Expansion (XCompose)

Omarchy includes extensive text expansion using XCompose. Trigger with `CapsLock + key combinations`:

### Emoji Shortcuts (CapsLock + m + letter)
- `m s` → 😄 (smile)
- `m c` → 😂 (cry/laugh)
- `m l` → 😍 (love)
- `m v` → ✌️ (victory)
- `m h` → ❤️ (heart)
- `m y` → 👍 (yes/thumbs up)
- `m n` → 👎 (no/thumbs down)
- `m f` → 🖕 (middle finger)
- `m w` → 🤞 (wish/crossed fingers)
- `m r` → 🤘 (rock on)
- `m k` → 😘 (kiss)
- `m e` → 🙄 (eyeroll)
- `m d` → 🤤 (drool)
- `m m` → 💰 (money)
- `m x` → 🎉 (celebrate)
- `m 1` → 💯 (100%)
- `m t` → 🥂 (toast)
- `m p` → 🙏 (pray)
- `m i` → 😉 (wink)
- `m o` → 👌 (OK)
- `m g` → 👋 (greeting/wave)
- `m a` → 💪 (arm/strength)
- `m b` → 🤯 (mind blown)

### Typography
- `Space Space` → — (em dash)

### Personal Information
- `Space n` → Your full name (set during installation)
- `Space e` → Your email address (set during installation)

## Omarchy Utility Scripts

### Main Control Panel
- `omarchy` - Interactive menu system for managing Omarchy

### Theme Management
- `omarchy-theme-menu` - Interactive theme selector
- `omarchy-theme-next` - Cycle to next theme
- `omarchy-theme-set <theme-name>` - Set specific theme
- `omarchy-theme-install <git-url>` - Install theme from Git repository
- `omarchy-theme-remove <theme-name>` - Remove installed theme
- `omarchy-theme-bg-next` - Cycle background images

### System Updates
- `omarchy-update` - Update Omarchy and optionally system packages
- `omarchy-refresh-waybar` - Refresh Waybar configuration
- `omarchy-refresh-wofi` - Refresh Wofi configuration
- `omarchy-refresh-plymouth` - Refresh boot splash screen
- `omarchy-refresh-applications` - Refresh desktop application entries

### Security Setup
- `omarchy-setup-fingerprint` - Set up fingerprint authentication
- `omarchy-setup-fingerprint --remove` - Remove fingerprint authentication
- `omarchy-setup-fido2` - Set up FIDO2/WebAuthn device
- `omarchy-setup-fido2 --remove` - Remove FIDO2 device

### System Control
- `omarchy-toggle-idle` - Enable/disable automatic screen locking
- `omarchy-battery-monitor` - Battery monitoring script (runs automatically)
- `omarchy-apple-display-brightness <value>` - Control external Apple display brightness

### Menus
- `omarchy-menu-power` - Power management menu (lock, suspend, restart, shutdown)
- `omarchy-menu-keybindings` - Interactive keybinding reference

### Development Tools
- `omarchy-dev-config-link` - Link Omarchy configs for development
- `omarchy-dev-add-migration` - Create new migration script

## Available Themes

Omarchy includes several built-in themes:
- **Tokyo Night** - Dark theme with purple/blue accents
- **Catppuccin** - Pastel color scheme
- **Everforest** - Green forest-inspired theme
- **Gruvbox** - Retro groove color scheme  
- **Kanagawa** - Inspired by Japanese art
- **Nord** - Arctic, north-bluish color palette
- **Matte Black** - Minimal dark theme
- **Rose Pine** - Includes light mode support

Each theme includes configurations for:
- Alacritty (terminal)
- Btop (system monitor)
- Hyprland (window manager)
- Hyprlock (lock screen)
- Mako (notifications)
- Neovim (editor)
- Waybar (status bar)
- Wofi (launcher)
- Background images

## Configuration Files

### Important User-Editable Configs
- `~/.config/hypr/hyprland.conf` - Main Hyprland configuration
- `~/.config/hypr/monitors.conf` - Monitor setup
- `~/.config/alacritty/alacritty.toml` - Terminal configuration
- `~/.config/waybar/config.jsonc` - Status bar configuration
- `~/.config/wofi/config` - Launcher configuration
- `~/.bashrc` - Shell configuration

### Omarchy System Files (auto-updated)
- `~/.local/share/omarchy/default/` - Default configurations
- `~/.local/share/omarchy/themes/` - Theme definitions
- `~/.local/share/omarchy/bin/` - Utility scripts

### Current Theme Links
- `~/.config/omarchy/current/theme/` - Active theme configuration
- `~/.config/omarchy/current/background` - Active background image

## Default Applications & MIME Types

- **Images**: imv (PNG, JPEG, GIF, WebP, BMP, TIFF)
- **Videos**: mpv (MP4, AVI, MKV, FLV, WMV, MPEG, OGG, WebM, MOV, 3GP)
- **PDFs**: Evince (Document Viewer)
- **Web**: Chromium (HTTP/HTTPS links)

## System Features

### Authentication
- Fingerprint authentication support (optional)
- FIDO2/WebAuthn device support (optional)
- Traditional password authentication

### Power Management
- Automatic performance profile selection
- Battery monitoring with low battery notifications
- Screen auto-lock with hypridle
- Suspend/hibernate support

### Network
- Wireless networking via iwd
- Firewall configured with ufw
- Docker network isolation

### Boot Experience
- Plymouth splash screen with Omarchy branding
- Seamless auto-login to desktop
- Quiet boot process

### Development Environment
- Multiple runtime version management with mise
- Docker with automatic startup
- Git with helpful aliases and defaults
- Language-specific tooling (Rust, Ruby, etc.)

## Troubleshooting & Support

- Manual available at: https://manuals.omamix.org/2/the-omarchy-manual
- Community Discord: https://discord.gg/tXFUdasqhY
- Configuration issues: Run `omarchy-update` to refresh
- Theme issues: Use `omarchy-theme-set <theme-name>` to reapply
- Application issues: Run `omarchy-refresh-applications`

## Advanced Usage

### Creating Custom Themes
Themes are stored in `~/.config/omarchy/themes/` and can be installed from Git repositories using `omarchy-theme-install`.

### Migration System
Omarchy includes automatic migration scripts for updating configurations and applying new features during updates.

### Bare Installation
Set `OMARCHY_BARE=1` during installation to skip optional applications and get a minimal setup.

### Custom XCompose Shortcuts
Edit `~/.XCompose` to add personal text expansion shortcuts. Run `refresh-xcompose` after changes.

This guide covers the essential features and functionality of Omarchy. For specific configuration changes or troubleshooting, users can reference the configuration files and use the built-in utility scripts. 