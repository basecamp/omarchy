echo "Modernize initramfs hooks to systemd-based"

HOOKS_CONF="/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
LIMINE_CONF="/etc/default/limine"

# Skip if already migrated
if [[ -f "$HOOKS_CONF" ]] && grep -q "sd-encrypt" "$HOOKS_CONF"; then
  exit 0
fi

# Only migrate if old hooks are present
if [[ -f "$HOOKS_CONF" ]] && grep -q "base udev.*keymap consolefont.*encrypt" "$HOOKS_CONF"; then
  # Update hooks with targeted replacements (preserves custom modules like nvidia)
  sudo sed -i 's/\budev\b/systemd/' "$HOOKS_CONF"
  sudo sed -i 's/\bkeymap\b *//' "$HOOKS_CONF"
  sudo sed -i 's/\bconsolefont\b/sd-vconsole/' "$HOOKS_CONF"
  sudo sed -i 's/\bencrypt\b/sd-encrypt/' "$HOOKS_CONF"
  sudo sed -i 's/\bbtrfs-overlayfs\b/sd-btrfs-overlayfs/' "$HOOKS_CONF"

  # Update kernel cmdline for encrypted systems: cryptdevice=PARTUUID= → rd.luks.name=UUID=
  if [[ -f "$LIMINE_CONF" ]] && grep -q "cryptdevice=PARTUUID=" "$LIMINE_CONF"; then
    PARTUUID=$(grep -oP 'cryptdevice=PARTUUID=\K[0-9a-f\-]+' "$LIMINE_CONF" | head -1)
    if [[ -n "$PARTUUID" ]]; then
      LUKS_DEVICE="/dev/disk/by-partuuid/$PARTUUID"
      if [[ -b "$LUKS_DEVICE" ]]; then
        LUKS_UUID=$(cryptsetup luksUUID "$LUKS_DEVICE" 2>/dev/null)
        if [[ -n "$LUKS_UUID" ]]; then
          sudo cp "$LIMINE_CONF" "$LIMINE_CONF.backup-$(date +%s)"
          sudo sed -i "s|cryptdevice=PARTUUID=${PARTUUID}:root|rd.luks.name=${LUKS_UUID}=root rd.luks.options=tries=0|g" "$LIMINE_CONF"
        fi
      fi
    fi
  fi

  # Rebuild initramfs and update bootloader
  sudo limine-update
fi
