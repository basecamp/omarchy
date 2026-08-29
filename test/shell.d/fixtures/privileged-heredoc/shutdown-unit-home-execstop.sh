#!/usr/bin/env bash

# Install Plymouth package
echo "Installing Plymouth..."
yay -S --noconfirm --needed plymouth

# Skip if plymouth already exists for some reason
if ! grep -q "plymouth" /etc/mkinitcpio.conf; then
  # Backup original mkinitcpio.conf just in case
  backup_timestamp=$(date +"%Y%m%d%H%M%S")
  sudo cp /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak.${backup_timestamp}"

  # Add plymouth to HOOKS array. Should be added:
  # - After 'base' and 'udev' (or 'systemd' if using systemd hook)
  # - Before 'encrypt' or 'sd-encrypt' if present

  # Use sed to add plymouth in-place
  if grep -q "systemd" /etc/mkinitcpio.conf; then
    # Add after systemd
    sudo sed -i '/^HOOKS=/s/systemd/systemd plymouth/' /etc/mkinitcpio.conf
  elif grep -q "udev" /etc/mkinitcpio.conf; then
    # Add after udev
    sudo sed -i '/^HOOKS=/s/udev/udev plymouth/' /etc/mkinitcpio.conf
  else
    # Fallback: add after base
    sudo sed -i '/^HOOKS=/s/base/base plymouth/' /etc/mkinitcpio.conf
  fi
fi

# Regenerate initramfs
sudo mkinitcpio -P

# Add kernel parameters for Plymouth (systemd-boot only)
if [ -d "/boot/loader/entries" ]; then
  echo "Detected systemd-boot"

  for entry in /boot/loader/entries/*.conf; do
    if [ -f "$entry" ]; then
      # Skip fallback entries
      if [[ "$(basename "$entry")" == *"fallback"* ]]; then
        echo "Skipped: $(basename "$entry") (fallback entry)"
        continue
      fi

      # Skip if splash it already present for some reason
      if ! grep -q "splash" "$entry"; then
        sudo sed -i '/^options/ s/$/ splash quiet/' "$entry"
      else
        echo "Skipped: $(basename "$entry") (splash already present)"
      fi
    fi
  done
else
  echo ""
  echo "systemd-boot not detected. Please manually add these kernel parameters:"
  echo "  - splash (to see the graphical splash screen)"
  echo "  - quiet (for silent boot)"
  echo ""
fi

# Touch .plymouth-sync-needed to signal rebuild on shutdown / reboot
touch "$HOME/.config/omarchy/.plymouth-sync-needed"

# Create the systemd service
sudo tee /etc/systemd/system/omarchy-plymouth-shutdown.service >/dev/null <<EOF
[Unit]
Description=Sync Plymouth Theme on Shutdown
DefaultDependencies=yes
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=$HOME/.local/share/omarchy/bin/omarchy-plymouth-shutdown-sync

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the service
sudo systemctl daemon-reload
sudo systemctl enable omarchy-plymouth-shutdown.service
sudo systemctl start omarchy-plymouth-shutdown.service
