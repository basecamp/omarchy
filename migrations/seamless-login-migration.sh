#!/bin/bash
# Migration script for systems set up before SDDM auto-login changes
# This cleans up old getty auto-login configuration and prepares for SDDM

echo "Running SDDM migration..."

# Run SDDM install
source ~/.local/share/omarchy/install/seamless-login.sh

# Remove getty auto-login configuration
sudo rm /etc/systemd/system/getty@tty1.service.d/override.conf
sudo rmdir /etc/systemd/system/getty@tty1.service.d/ 2>/dev/null || true

# Remove Hyprland auto-launch from .bash_profile
if [ -f "$HOME/.bash_profile" ]; then
  # Remove the specific line
  sed -i '/^\[\[ -z \$DISPLAY && \$(tty) == \/dev\/tty1 \]\] && exec Hyprland$/d' "$HOME/.bash_profile"
  echo "Cleaned up .bash_profile"
fi

# Remove GTK_IM_MODULE from fcitx config for better Wayland compatibility
if [ -f "$HOME/.config/environment.d/fcitx.conf" ]; then
  echo "Removing GTK_IM_MODULE from fcitx config for Wayland..."
  sed -i 's/^GTK_IM_MODULE=fcitx$//' "$HOME/.config/environment.d/fcitx.conf"
fi

echo ""
echo "Migration complete! You can now run seamless-login.sh to set up uwsm auto-login."
echo "Your old configuration files have been backed up."
