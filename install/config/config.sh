#!/bin/bash

# Copy over Omarchy configs, replacing existing Hyprland configs
echo "Installing Omarchy configuration files and replacing existing Hyprland configs..."
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
OMARCHY_REPO_DIR="$(cd "$(dirname "$OMARCHY_INSTALL")/.." && pwd)"
echo "Repo directory: $OMARCHY_REPO_DIR"
# Use the correct path for local installation
LOCAL_REPO_DIR="$(pwd)"
echo "Local repo directory: $LOCAL_REPO_DIR"
cp -R "$LOCAL_REPO_DIR/config/hypr" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/hypr ~/.config/ 2>/dev/null || true
cp -R "$LOCAL_REPO_DIR/config/waybar" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/waybar ~/.config/ 2>/dev/null || true
cp -R "$LOCAL_REPO_DIR/config/swayosd" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/swayosd ~/.config/ 2>/dev/null || true
cp -R "$LOCAL_REPO_DIR/config/walker" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/walker ~/.config/ 2>/dev/null || true
cp -R "$LOCAL_REPO_DIR/config/mako" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/mako ~/.config/ 2>/dev/null || true

# Copy other application-specific configs (excluding starship and neovim)
echo "Installing other Omarchy application configurations..."
cp -R "$LOCAL_REPO_DIR/config/Typora" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/Typora ~/.config/ 2>/dev/null || true
cp -R "$LOCAL_REPO_DIR/config/alacritty" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/alacritty ~/.config/ 2>/dev/null || true
cp -R "$LOCAL_REPO_DIR/config/btop" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/btop ~/.config/ 2>/dev/null || true
cp -R "$LOCAL_REPO_DIR/config/chromium" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/chromium ~/.config/ 2>/dev/null || true
cp -R "$LOCAL_REPO_DIR/config/fastfetch" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/fastfetch ~/.config/ 2>/dev/null || true
cp -R "$LOCAL_REPO_DIR/config/fcitx5" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/fcitx5 ~/.config/ 2>/dev/null || true
cp -R "$LOCAL_REPO_DIR/config/fontconfig" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/fontconfig ~/.config/ 2>/dev/null || true
cp -R "$LOCAL_REPO_DIR/config/lazygit" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/lazygit ~/.config/ 2>/dev/null || true
cp -R "$LOCAL_REPO_DIR/config/systemd" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/systemd ~/.config/ 2>/dev/null || true
cp -R "$LOCAL_REPO_DIR/config/uwsm" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/uwsm ~/.config/ 2>/dev/null || true
cp -R "$LOCAL_REPO_DIR/config/xournalpp" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/xournalpp ~/.config/ 2>/dev/null || true

# Copy environment configuration
cp -R "$LOCAL_REPO_DIR/config/environment.d" ~/.config/ 2>/dev/null || cp -R ~/.local/share/omarchy/config/environment.d ~/.config/ 2>/dev/null || true

# Copy browser flags
cp "$LOCAL_REPO_DIR/config/brave-flags.conf" ~/.config/ 2>/dev/null || cp ~/.local/share/omarchy/config/brave-flags.conf ~/.config/ 2>/dev/null || true
cp "$LOCAL_REPO_DIR/config/chromium-flags.conf" ~/.config/ 2>/dev/null || cp ~/.local/share/omarchy/config/chromium-flags.conf ~/.config/ 2>/dev/null || true

# Copy custom fonts
cp "$LOCAL_REPO_DIR/config/omarchy.ttf" ~/.local/share/fonts/ 2>/dev/null || cp ~/.local/share/omarchy/config/omarchy.ttf ~/.local/share/fonts/ 2>/dev/null || true

# Copy default bashrc from Omarchy
cp "$LOCAL_REPO_DIR/default/bashrc" ~/.bashrc 2>/dev/null || cp ~/.local/share/omarchy/default/bashrc ~/.bashrc 2>/dev/null || true

echo "Omarchy configuration files installed successfully!"
