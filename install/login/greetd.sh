#!/bin/bash

# greetd - Wayland-native display manager with persistent autologin
# Lighter weight than SDDM, no X greeter overhead, instant restart on Hyprland exit

echo "Configuring greetd..."

# Install greetd if not already installed (tuigreet not needed for autologin)
if ! pacman -Qi greetd &>/dev/null; then
  sudo pacman -S --needed --noconfirm greetd
fi

# Create greetd config directory
sudo mkdir -p /etc/greetd

# Configure greetd with persistent autologin (matches SDDM behavior)
cat <<EOF | sudo tee /etc/greetd/config.toml
[terminal]
vt = 1

[default_session]
# Autologin - launches Hyprland directly via uwsm (same as SDDM autologin)
command = "uwsm start -e -D Hyprland hyprland.desktop"
user = "$USER"
EOF

# Disable SDDM if it's enabled (might be installed from base packages)
if systemctl is-enabled sddm.service &>/dev/null; then
  echo "Disabling SDDM (switching to greetd)..."
  sudo systemctl disable sddm.service
fi

# Enable greetd
sudo systemctl enable greetd.service

echo "greetd configured with autologin"
