#!/bin/bash

# Disable tmpfs /tmp to prevent "no space left on device" errors during AUR builds
#
# By default, Arch Linux mounts /tmp as tmpfs (RAM-based), limited to 50% of RAM.
# This causes build failures for large AUR packages (obs-studio-git, chromium, firefox, etc.)
# that extract/build large files in /tmp, even with 12GB+ RAM.
#
# Masking tmp.mount makes /tmp use actual disk space instead of RAM.
# - Performance impact: Negligible (~2-3 seconds slower on modern SSDs)
# - Reliability gain: Prevents installation failures on large packages
# - Cleanup: /tmp contents are still cleaned after 10 days via systemd-tmpfiles
#
# This is permanent and safe - a better default for systems that build from source.

echo "Checking /tmp filesystem configuration..."

# Check if /tmp is currently mounted as tmpfs
if mountpoint -q /tmp 2>/dev/null && mount | grep -q "tmpfs on /tmp"; then
  echo "  /tmp is currently tmpfs (RAM-limited to 50% of RAM)"
  echo "  Disabling tmpfs /tmp to prevent build failures..."
  echo

  # Mask the systemd unit to prevent tmpfs mounting
  if sudo systemctl mask tmp.mount 2>/dev/null; then
    echo "  Masked tmp.mount - /tmp will use disk space"

    # Unmount current tmpfs immediately to avoid needing reboot
    if sudo systemctl stop tmp.mount 2>/dev/null && sudo umount /tmp 2>/dev/null; then
      echo "  Unmounted tmpfs /tmp - now using disk space immediately"
    else
      echo "  Could not unmount tmpfs /tmp - will take effect after reboot"
      echo "    (This is normal if files are open in /tmp)"
    fi
  else
    echo "  Warning: Could not mask tmp.mount (may already be masked)"
  fi
elif systemctl is-enabled tmp.mount &>/dev/null 2>&1; then
  # tmp.mount exists but isn't currently mounted (edge case)
  echo "  tmp.mount unit exists but not active"
  echo "  Masking to prevent future tmpfs mounting..."
  sudo systemctl mask tmp.mount 2>/dev/null || true
  echo "  Masked tmp.mount"
else
  echo "  /tmp is already using disk space (not tmpfs)"
fi

echo
