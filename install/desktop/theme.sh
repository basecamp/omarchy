#!/bin/bash

# get cool icons
yay -S --noconfirm suru-plus-aspromauros

# Use dark mode for QT apps too (like kdenlive)
if ! yay -Q kvantum-qt5 &>/dev/null; then
  yay -S --noconfirm kvantum-qt5
fi

# Prefer dark mode everything
if ! yay -Q gnome-themes-extra &>/dev/null; then
  yay -S --noconfirm gnome-themes-extra # Adds Adwaita-dark theme
fi

# clone theme repo and init a neutral color
rm -rf ~/.local/share/orchis-gtk-theme
git clone https://github.com/vinceliuice/Orchis-theme.git ~/.local/share/orchis-gtk-theme
~/.local/share/orchis-gtk-theme/install.sh -n Systheme -t grey

gsettings set org.gnome.desktop.interface gtk-theme "Systheme-Grey-Dark-Compact"
gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
gsettings set org.gnome.desktop.interface icon-theme "HighContrast"
gsettings set org.gnome.desktop.interface icon-theme "Suru++-Asprómauros"

# Setup theme links
mkdir -p ~/.config/autarky/themes
for f in ~/.local/share/autarky/themes/*; do ln -nfs "$f" ~/.config/autarky/themes/; done

# Set initial theme
mkdir -p ~/.config/autarky/current
ln -snf ~/.config/autarky/themes/master_camera ~/.config/autarky/current/theme
ln -snf ~/.config/autarky/current/theme/backgrounds/02-fill-camera.png ~/.config/autarky/current/background

# init colorscheme for nvim and theme
wal --backend colorz -i ~/.config/autarky/current/background

# Set specific app links for current theme
# osc.conf includes current theme osc config, leaving these folder paths just in case
mkdir -p ~/.config/mpv
mkdir -p ~/.config/mpv/script-opts/
# ln -snf ~/.config/autarky/current/theme/mpv.osc.conf osc.conf

mkdir -p ~/.config/btop/themes
ln -snf ~/.config/autarky/current/theme/btop.theme ~/.config/btop/themes/current.theme

mkdir -p ~/.config/mako
ln -snf ~/.config/autarky/current/theme/mako.ini ~/.config/mako/config
