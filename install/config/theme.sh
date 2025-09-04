#!/bin/bash

gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
gsettings set org.gnome.desktop.interface icon-theme "Yaru-blue"

# Set links for Nautilius action icons
sudo ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-previous-symbolic.svg
sudo ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-next-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-next-symbolic.svg
sudo gtk-update-icon-cache /usr/share/icons/Yaru

# Setup theme links
mkdir -p ~/.config/omarchy/themes
for f in ~/.local/share/omarchy/themes/*; do ln -nfs "$f" ~/.config/omarchy/themes/; done

# Set initial theme
mkdir -p ~/.config/omarchy/current
ln -snf ~/.config/omarchy/themes/catppuccin ~/.config/omarchy/current/theme
ln -snf ~/.config/omarchy/current/theme/backgrounds/1-catppuccin.png ~/.config/omarchy/current/background


mkdir -p ~/.config/btop/themes
ln -snf ~/.config/omarchy/current/theme/btop.theme ~/.config/btop/themes/current.theme

mkdir -p ~/.config/mako
ln -snf ~/.config/omarchy/current/theme/mako.ini ~/.config/mako/config
