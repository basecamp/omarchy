#!/bin/bash
# Migration script for systems set up before SDDM auto-login changes
# This cleans up old getty auto-login configuration and prepares for SDDM

echo "Running SDDM migration..."

# Run SDDM install
source ~/.local/share/omarchy/install/sddm.sh

# Remove getty auto-login configuration
sudo rm /etc/systemd/system/getty@tty1.service.d/override.conf
sudo rmdir /etc/systemd/system/getty@tty1.service.d/ 2>/dev/null || true

# Remove 'quiet' kernel parameter from boot entries
echo "Removing 'quiet' kernel parameters..."

# Handle systemd-boot entries
if [ -d "/boot/loader/entries" ]; then
  for entry in /boot/loader/entries/*.conf; do
    if [ -f "$entry" ] && grep -q "quiet" "$entry"; then
      echo "Removing quiet from $(basename "$entry")"
      sudo sed -i 's/ quiet//g' "$entry"
    fi
  done
fi

# Handle GRUB
if [ -f "/etc/default/grub" ]; then
  if grep -q "quiet" /etc/default/grub; then
    echo "Removing quiet from GRUB configuration"
    sudo sed -i 's/ quiet//g' /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg
  fi
fi

# Handle UKI cmdline.d
if [ -d "/etc/cmdline.d" ]; then
  for conf in /etc/cmdline.d/*.conf; do
    if [ -f "$conf" ] && grep -q "quiet" "$conf"; then
      echo "Removing quiet from $(basename "$conf")"
      sudo sed -i 's/quiet//g' "$conf"
      # Clean up empty lines
      sudo sed -i '/^[[:space:]]*$/d' "$conf"
    fi
  done
fi

# Handle alternate UKI location
if [ -f "/etc/kernel/cmdline" ]; then
  if grep -q "quiet" /etc/kernel/cmdline; then
    echo "Removing quiet from /etc/kernel/cmdline"
    sudo sed -i 's/ quiet//g' /etc/kernel/cmdline
  fi
fi

# Remove Hyprland auto-launch from .bash_profile
if [ -f "$HOME/.bash_profile" ]; then
  # Remove the specific line
  sed -i '/^\[\[ -z \$DISPLAY && \$(tty) == \/dev\/tty1 \]\] && exec Hyprland$/d' "$HOME/.bash_profile"
  echo "Cleaned up .bash_profile"
fi

echo ""
echo "Migration complete! You can now run sddm.sh to set up SDDM auto-login."
echo "Your old .bash_profile has been backed up."
