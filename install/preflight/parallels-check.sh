#!/bin/bash

# Skip if not Parallels
virt_type=$(systemd-detect-virt 2>/dev/null || echo "none")
if [[ "$virt_type" != "parallels" ]]; then
  return 0
fi

# Allow skipping Parallels Tools check via environment variable
if [[ -n "${OMARCHY_SKIP_PARALLELS_TOOLS:-}" ]]; then
  echo "Skipping Parallels Tools check (OMARCHY_SKIP_PARALLELS_TOOLS is set)"
  echo "You can install Parallels Tools manually later if needed"
  return 0
fi

echo "Detected Parallels VM, checking prerequisites..."

# Check if Parallels Tools are already installed
if [ -d /usr/lib/parallels-tools ]; then
  echo "Parallels Tools already installed"
  return 0
fi

# Tools not installed, verify Parallels Tools ISO is available and mount it
CDROM_DEV=""
if [ -e /dev/sr0 ]; then
  CDROM_DEV="/dev/sr0"
elif [ -e /dev/cdrom ]; then
  CDROM_DEV="/dev/cdrom"
else
  echo
  echo "ERROR: No CD-ROM device found (/dev/sr0 or /dev/cdrom)"
  echo
  echo "------------------------------------------------------------"
  echo "Mount Parallels Tools ISO: Actions > Install Parallels Tools"
  echo "------------------------------------------------------------"
  echo
  echo "Then click 'Retry installation' below"
  exit 1
fi

echo "Found CD-ROM device: $CDROM_DEV"

# Try to mount and verify it's the Parallels Tools ISO
MOUNT_POINT="/tmp/parallels-tools-check"
sudo mkdir -p "$MOUNT_POINT"

echo "Attempting to mount $CDROM_DEV..."
if sudo mount "$CDROM_DEV" "$MOUNT_POINT" 2>/dev/null; then
  echo "Successfully mounted CD-ROM"

  # List contents for debugging
  echo "CD-ROM contents:"
  ls -la "$MOUNT_POINT" | head -10

  if [ -f "$MOUNT_POINT/installer/prltoolsd.sh" ] || [ -f "$MOUNT_POINT/install" ]; then
    echo "✓ Parallels Tools installation media verified"
    sudo umount "$MOUNT_POINT"
    sudo rmdir "$MOUNT_POINT"
    return 0
  else
    echo
    echo "ERROR: CD-ROM mounted but doesn't contain Parallels Tools installer"
    echo "Found contents:"
    ls -la "$MOUNT_POINT"
    sudo umount "$MOUNT_POINT"
    sudo rmdir "$MOUNT_POINT"
  fi
else
  echo
  echo "ERROR: Failed to mount CD-ROM device $CDROM_DEV"
  echo
  MOUNT_ERROR=$(sudo mount "$CDROM_DEV" "$MOUNT_POINT" 2>&1)
  echo "Mount error: $MOUNT_ERROR"
fi

echo
echo "------------------------------------------------------------"
echo "Mount Parallels Tools ISO: Actions > Install Parallels Tools"
echo "------------------------------------------------------------"
echo
echo "Then click 'Retry installation' below"
exit 1
