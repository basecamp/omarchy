#!/bin/bash
# Configure Limine bootloader after archinstall completes
# This runs as part of the login scripts after the system is installed

echo "Configuring Limine bootloader for Omarchy..."

# Detect EFI vs BIOS
if [[ -d /sys/firmware/efi ]]; then
  EFI=true
fi

# Create drop-in directory if it doesn't exist
sudo mkdir -p /etc/limine-entry-tool.d

# Only extract cmdline on first install
if [[ ! -f /etc/limine-entry-tool.d/omarchy-cmdline.conf ]]; then
  # Extract kernel cmdline from archinstall-created limine config
  # Try multiple possible locations (USB, EFI, BIOS)
  for config_path in /boot/EFI/BOOT/limine.conf /boot/EFI/limine/limine.conf /boot/limine/limine.conf /boot/limine.conf; do
    if [[ -f "$config_path" ]]; then
      CMDLINE=$(grep "^[[:space:]]*cmdline:" "$config_path" | head -1 | sed 's/^[[:space:]]*cmdline:[[:space:]]*//')
      OLD_CONFIG="$config_path"
      break
    fi
  done

  if [[ -n "$CMDLINE" ]]; then
    # Write cmdline to drop-in config file
    sudo tee /etc/limine-entry-tool.d/omarchy-cmdline.conf >/dev/null <<EOF
# Omarchy kernel command line parameters
KERNEL_CMDLINE[default]="$CMDLINE"
EOF

    # Remove old archinstall-created config
    if [[ -n "$OLD_CONFIG" ]]; then
      sudo rm "$OLD_CONFIG"
    fi
  else
    echo "ERROR: Could not extract kernel cmdline from limine config" >&2
    echo "Please manually create /etc/limine-entry-tool.d/omarchy-cmdline.conf" >&2
    exit 1
  fi

  # Clean up archinstall-created Limine entries
  if [[ -n "$EFI" ]] && command -v efibootmgr &>/dev/null; then
    while IFS= read -r bootnum; do
      sudo efibootmgr -b "$bootnum" -B >/dev/null 2>&1 || true
    done < <(efibootmgr 2>/dev/null | grep -E "^Boot[0-9]{4}\*? Arch Linux Limine" | sed 's/^Boot\([0-9]\{4\}\).*/\1/')
  fi
fi

# Override UKI settings for BIOS systems
if [[ -z "$EFI" ]]; then
  # Disable UKI/fallback for BIOS systems by overriding the shipped config
  sudo tee /etc/limine-entry-tool.d/omarchy-uki.conf >/dev/null <<EOF
# BIOS systems don't support UKI or EFI fallback
ENABLE_UKI=no
EOF
fi

# Install themed bootloader config
sudo cp /usr/share/omarchy/limine/limine.conf /boot/limine.conf

# Configure snapper if not already configured
if command -v snapper &>/dev/null; then
  # Create configs if they don't exist, using Omarchy template
  if ! sudo snapper list-configs 2>/dev/null | grep -q "root"; then
    sudo snapper -c root create-config -t omarchy /
  fi

  if ! sudo snapper list-configs 2>/dev/null | grep -q "home"; then
    sudo snapper -c home create-config -t omarchy /home
  fi
fi

# Re-enable mkinitcpio hooks if they were disabled during installation
if [[ -f /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled ]]; then
  sudo mv /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled /usr/share/libalpm/hooks/90-mkinitcpio-install.hook
fi

if [[ -f /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled ]]; then
  sudo mv /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
fi

# Enable limine-snapper-sync service
chrootable_systemctl_enable limine-snapper-sync.service

# Run limine-update
sudo limine-update 2>/dev/null || true

echo "Limine configuration complete!"
