#!/bin/bash

# Install and replace Hyprland configuration files with Omarchy versions
echo "Replacing existing Hyprland configuration with Omarchy versions..."

# Create config directories if they don't exist
mkdir -p ~/.config
mkdir -p ~/.local/share/fonts

# Remove existing Hyprland configs to ensure clean replacement
echo "Removing existing Hyprland configuration files..."
rm -rf ~/.config/hypr
rm -rf ~/.config/waybar
rm -rf ~/.config/swayosd 2>/dev/null || true
rm -rf ~/.config/walker 2>/dev/null || true
rm -rf ~/.config/mako 2>/dev/null || true

# Copy fresh Omarchy Hyprland configs
echo "Installing fresh Omarchy Hyprland configuration files..."
cp -R ~/.local/share/omarchy/config/hypr ~/.config/
cp -R ~/.local/share/omarchy/config/waybar ~/.config/
cp -R ~/.local/share/omarchy/config/swayosd ~/.config/ 2>/dev/null || true
cp -R ~/.local/share/omarchy/config/walker ~/.config/ 2>/dev/null || true
cp -R ~/.local/share/omarchy/config/mako ~/.config/ 2>/dev/null || true

# Copy other application-specific configs (excluding starship and neovim)
echo "Installing other Omarchy application configurations..."
cp -R ~/.local/share/omarchy/config/Typora ~/.config/ 2>/dev/null || true
cp -R ~/.local/share/omarchy/config/alacritty ~/.config/ 2>/dev/null || true
cp -R ~/.local/share/omarchy/config/btop ~/.config/ 2>/dev/null || true
cp -R ~/.local/share/omarchy/config/chromium ~/.config/ 2>/dev/null || true
cp -R ~/.local/share/omarchy/config/fastfetch ~/.config/ 2>/dev/null || true
cp -R ~/.local/share/omarchy/config/fcitx5 ~/.config/ 2>/dev/null || true
cp -R ~/.local/share/omarchy/config/fontconfig ~/.config/ 2>/dev/null || true
cp -R ~/.local/share/omarchy/config/lazygit ~/.config/ 2>/dev/null || true
cp -R ~/.local/share/omarchy/config/systemd ~/.config/ 2>/dev/null || true
cp -R ~/.local/share/omarchy/config/uwsm ~/.config/ 2>/dev/null || true
cp -R ~/.local/share/omarchy/config/xournalpp ~/.config/ 2>/dev/null || true

# Copy environment configuration
cp -R ~/.local/share/omarchy/config/environment.d ~/.config/ 2>/dev/null || true

# Copy browser flags
cp ~/.local/share/omarchy/config/brave-flags.conf ~/.config/ 2>/dev/null || true
cp ~/.local/share/omarchy/config/chromium-flags.conf ~/.config/ 2>/dev/null || true

# Copy custom fonts
cp ~/.local/share/omarchy/config/omarchy.ttf ~/.local/share/fonts/ 2>/dev/null || true

echo "Omarchy configuration files installed successfully!"

# Refresh Hyprland services
echo "Refreshing Hyprland services..."
~/.local/share/omarchy/bin/omarchy-refresh-hyprland 2>/dev/null || true
~/.local/share/omarchy/bin/omarchy-refresh-waybar 2>/dev/null || true
~/.local/share/omarchy/bin/omarchy-refresh-swayosd 2>/dev/null || true
~/.local/share/omarchy/bin/omarchy-refresh-hypridle 2>/dev/null || true
~/.local/share/omarchy/bin/omarchy-refresh-hyprlock 2>/dev/null || true
~/.local/share/omarchy/bin/omarchy-refresh-hyprsunset 2>/dev/null || true
~/.local/share/omarchy/bin/omarchy-refresh-walker 2>/dev/null || true

echo "All Hyprland services refreshed with Omarchy configurations!"