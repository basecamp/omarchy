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

echo ""
echo "Migration complete! You can now run sddm.sh to set up SDDM auto-login."
echo "Your old .bash_profile has been backed up."
