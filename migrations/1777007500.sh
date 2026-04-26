#!/bin/bash

# Fix /boot permissions security issue
# See: https://github.com/basecamp/omarchy/issues/5377

echo "Fixing /boot permissions for better security..."

# Detect boot filesystem type
boot_fs_type=""
boot_mount_options=""

if command -v findmnt >/dev/null 2>&1 && findmnt -n --target /boot >/dev/null 2>&1; then
  boot_fs_type="$(findmnt -n -o FSTYPE --target /boot 2>/dev/null)"
fi

if [[ "$boot_fs_type" =~ ^(vfat|fat|msdos)$ ]]; then
  echo "/boot is on $boot_fs_type; applying mount masks because chmod doesn't change effective permissions on FAT"
  
  # Get current mount options before remount
  boot_mount_options="$(findmnt -n -o OPTIONS --target /boot 2>/dev/null)"
  
  # Check if restrictive mount options already exist
  if [[ "$boot_mount_options" == *"umask=0077"* ]] || [[ "$boot_mount_options" == *"dmask=0077"* && "$boot_mount_options" == *"fmask=0177"* ]]; then
    echo "/boot already has restrictive mount options"
  else
    sudo mount -o remount,dmask=0077,fmask=0177 /boot 2>/dev/null || echo "Warning: Could not remount /boot with restrictive permissions"
    
    # Re-read mount options after remount to verify
    boot_mount_options="$(findmnt -n -o OPTIONS --target /boot 2>/dev/null)"
    
    if [[ "$boot_mount_options" == *"umask=0077"* ]] || [[ "$boot_mount_options" == *"dmask=0077"* && "$boot_mount_options" == *"fmask=0177"* ]]; then
      echo "✓ /boot mount options now include restrictive umask"
    else
      echo "Warning: /boot remounted but restrictive options not detected. Check /etc/fstab for persistence."
    fi
  fi
  
  echo "Note: Add dmask=0077,fmask=0177 to /etc/fstab for persistence across reboots"
else
  # Check if /boot is actually a separate mount
  if findmnt -n --target /boot >/dev/null 2>&1; then
    # Fix /boot directory permissions (should be 700 for security)
    sudo chmod 700 /boot 2>/dev/null || echo "Warning: Could not change /boot permissions"

    # Fix random-seed file permissions if it exists
    if [[ -f /boot/loader/random-seed ]]; then
      sudo chmod 600 /boot/loader/random-seed 2>/dev/null || echo "Warning: Could not change random-seed permissions"
    fi

    # Verify the fix
    boot_perms=$(stat -c %a /boot 2>/dev/null)
    if [[ "$boot_perms" == "700" ]]; then
      echo "✓ /boot permissions fixed to 700"
    fi
  else
    echo "/boot is not a separate mount (permissions handled by root filesystem)"
  fi
fi

# Also run bootctl random-seed to regenerate with correct permissions
if command -v bootctl >/dev/null 2>&1; then
  sudo bootctl random-seed 2>/dev/null || true
fi

# Guard notify-send for environments without GUI/DBUS
if command -v notify-send >/dev/null 2>&1 && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  notify-send "Boot permissions fixed" "Security improvement applied to /boot" || true
fi

exit 0