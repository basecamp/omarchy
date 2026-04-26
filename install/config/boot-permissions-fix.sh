#!/bin/bash

# Fix /boot permissions security issue
# The random seed file and /boot mount should not be world accessible
# See: https://github.com/basecamp/omarchy/issues/5377

echo "Fixing /boot permissions for better security..."

# Detect boot filesystem type
boot_fs_type=""
boot_mount_options=""

if command -v findmnt >/dev/null 2>&1 && findmnt -n --target /boot >/dev/null 2>&1; then
  boot_fs_type="$(findmnt -n -o FSTYPE --target /boot 2>/dev/null)"
  boot_mount_options="$(findmnt -n -o OPTIONS --target /boot 2>/dev/null)"
fi

if [[ "$boot_fs_type" =~ ^(vfat|fat|msdos)$ ]]; then
  echo "/boot is on $boot_fs_type; applying mount masks because chmod doesn't change effective permissions on FAT"
  
  # Check if restrictive mount options already exist
  if [[ "$boot_mount_options" == *"umask=0077"* ]] || [[ "$boot_mount_options" == *"dmask=0077"* && "$boot_mount_options" == *"fmask=0177"* ]]; then
    echo "/boot already has restrictive mount options"
  else
    sudo mount -o remount,dmask=0077,fmask=0177 /boot 2>/dev/null || echo "Warning: Could not remount /boot with restrictive permissions"
  fi
else
  # Fix /boot directory permissions (should be 700)
  sudo chmod 700 /boot 2>/dev/null || echo "Warning: Could not change /boot permissions"

  # Fix random-seed file permissions if it exists
  if [[ -f /boot/loader/random-seed ]]; then
    sudo chmod 600 /boot/loader/random-seed 2>/dev/null || echo "Warning: Could not change random-seed permissions"
  fi

  # Check if /boot is in fstab with correct mountpoint (second column)
  if ! awk '!/^[[:space:]]*#/ && NF >= 2 && $2 == "/boot" { found=1; exit } END { exit !found }' /etc/fstab 2>/dev/null; then
    echo "Warning: /boot is not in fstab, permissions may not persist"
  fi
fi

# Run bootctl random-seed to ensure correct permissions on random seed
if command -v bootctl >/dev/null 2>&1; then
  sudo bootctl random-seed 2>/dev/null || true
fi

echo "Boot permissions fix complete!"