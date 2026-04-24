#!/bin/bash

# Fix /boot permissions security issue
# See: https://github.com/basecamp/omarchy/issues/5377

echo "Fixing /boot permissions for better security..."

# Check filesystem type of /boot
boot_fs_type=""
boot_mount_options=""

if command -v findmnt &>/dev/null && findmnt -n --target /boot &>/dev/null; then
  boot_fs_type="$(findmnt -n -o FSTYPE --target /boot 2>/dev/null)"
  boot_mount_options="$(findmnt -n -o OPTIONS --target /boot 2>/dev/null)"
fi

if [[ "$boot_fs_type" =~ ^(vfat|fat|msdos)$ ]]; then
  echo "/boot is on $boot_fs_type filesystem; applying mount masks"
  
  # Check if already has restrictive options
  if [[ "$boot_mount_options" == *"umask=0077"* ]] || \
     ([[ "$boot_mount_options" == *"dmask=0077"* ]] && [[ "$boot_mount_options" == *"fmask=0177"* ]]); then
    echo "✓ /boot already has restrictive mount options"
  else
    # Try to remount with restrictive options
    sudo mount -o remount,dmask=0077,fmask=0177 /boot 2>/dev/null || echo "Warning: Could not remount /boot with restrictive permissions"
  fi
  
  # chmod is not reliable on FAT, but try anyway for the random-seed file
  if [[ -f /boot/loader/random-seed ]]; then
    sudo chmod 600 /boot/loader/random-seed 2>/dev/null || echo "Warning: Could not change random-seed permissions on FAT"
  fi
else
  # Fix /boot directory permissions for non-FAT filesystems
  sudo chmod 700 /boot 2>/dev/null || echo "Could not change /boot permissions"
  
  # Fix random-seed file permissions
  if [[ -f /boot/loader/random-seed ]]; then
    sudo chmod 600 /boot/loader/random-seed 2>/dev/null || echo "Could not change random-seed permissions"
  fi
fi

# Verify the fix
if [[ "$boot_fs_type" =~ ^(vfat|fat|msdos)$ ]]; then
  new_options="$(findmnt -n -o OPTIONS --target /boot 2>/dev/null)"
  if [[ "$new_options" == *"umask=0077"* ]] || \
     ([[ "$new_options" == *"dmask=0077"* ]] && [[ "$new_options" == *"fmask=0177"* ]]); then
    echo "✓ /boot mount options fixed"
  fi
else
  if [[ $(stat -c %a /boot 2>/dev/null) == "700" ]]; then
    echo "✓ /boot permissions fixed to 700"
  fi
fi

# Notify user (with error handling)
if command -v notify-send >/dev/null 2>&1 && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  notify-send "Boot permissions fixed" "Security improvement applied to /boot" 2>/dev/null || true
fi
