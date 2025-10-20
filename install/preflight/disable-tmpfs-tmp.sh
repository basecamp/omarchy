#!/bin/bash

# Conditionally disable tmpfs /tmp to prevent "no space left on device" errors during AUR builds
#
# By default, Arch Linux mounts /tmp as tmpfs (RAM-based), limited to 50% of RAM.
# This causes build failures for large AUR packages (obs-studio-git, chromium, firefox, etc.)
# that extract/build large files in /tmp.
#
# Strategy:
# - Systems with ≥16GB RAM: Keep tmpfs enabled (fast builds, unlikely to run out of space)
# - Systems with <16GB RAM: Disable tmpfs proactively (prevent build failures)
# - Error menu fallback: If build fails due to tmpfs, retry with disk-based /tmp
#
# Masking tmp.mount makes /tmp use actual disk space instead of RAM:
# - Performance impact: ~2-3 seconds slower on modern SSDs (negligible)
# - Reliability gain: Prevents installation failures on large packages
# - Cleanup: /tmp contents are still cleaned after 10 days via systemd-tmpfiles

echo "Checking /tmp filesystem configuration..."

# Get total RAM in GB
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/ {print $2}')

# Check if we should disable tmpfs
should_disable_tmpfs=false

# Force disable if OMARCHY_DISABLE_TMPFS is set to true (from error menu retry)
if [[ "${OMARCHY_DISABLE_TMPFS:-false}" == "true" ]]; then
  echo "  Force disabling tmpfs /tmp (requested after build failure)"
  should_disable_tmpfs=true
# Disable proactively if system has less than 16GB RAM
elif [[ $TOTAL_RAM_GB -lt 16 ]]; then
  echo "  System has ${TOTAL_RAM_GB}GB RAM (less than 16GB)"
  echo "  Disabling tmpfs /tmp to prevent build failures on large packages"
  should_disable_tmpfs=true
else
  echo "  System has ${TOTAL_RAM_GB}GB RAM - keeping tmpfs /tmp for faster builds"
  echo "  (Will auto-disable if build failures occur)"
fi

# Perform tmpfs disabling if needed
if [[ $should_disable_tmpfs == true ]]; then
  # Check if /tmp is currently mounted as tmpfs
  if mountpoint -q /tmp 2>/dev/null && mount | grep -q "tmpfs on /tmp"; then
    echo "  /tmp is currently tmpfs (RAM-limited to 50% of RAM)"
    echo "  Switching to disk-based /tmp..."
    echo

    # Mask the systemd unit to prevent tmpfs mounting
    if sudo systemctl mask tmp.mount 2>/dev/null; then
      echo "  ✓ Masked tmp.mount - /tmp will use disk space"

      # Unmount current tmpfs immediately to avoid needing reboot
      if sudo systemctl stop tmp.mount 2>/dev/null && sudo umount /tmp 2>/dev/null; then
        echo "  ✓ Unmounted tmpfs /tmp - now using disk space immediately"
      else
        echo "  ⚠ Could not unmount tmpfs /tmp - will take effect after reboot"
        echo "    (This is normal if files are open in /tmp)"
      fi
    else
      echo "  ⚠ Warning: Could not mask tmp.mount (may already be masked)"
    fi
  elif systemctl is-enabled tmp.mount &>/dev/null 2>&1; then
    # tmp.mount exists but isn't currently mounted (edge case)
    echo "  tmp.mount unit exists but not active"
    echo "  Masking to prevent future tmpfs mounting..."
    sudo systemctl mask tmp.mount 2>/dev/null || true
    echo "  ✓ Masked tmp.mount"
  else
    echo "  ✓ /tmp is already using disk space (not tmpfs)"
  fi
fi

echo
