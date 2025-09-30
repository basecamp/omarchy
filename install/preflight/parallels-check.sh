#!/bin/bash

# Skip if not Parallels
virt_type=$(systemd-detect-virt 2>/dev/null || echo "none")
if [[ "$virt_type" != "parallels" ]]; then
  return 0
fi

echo "Detected Parallels VM, checking prerequisites..."

# Check if Parallels Tools are already installed
if [ -d /usr/lib/parallels-tools ]; then
  echo "Parallels Tools already installed"
  return 0
fi

# Tools not installed, verify Parallels Tools ISO is mounted
if [ -e /dev/cdrom ] || [ -e /dev/sr0 ]; then
  CDROM_DEV="/dev/cdrom"
  [ -e /dev/sr0 ] && CDROM_DEV="/dev/sr0"

  # Try to mount and verify it's the Parallels Tools ISO
  MOUNT_POINT="/tmp/parallels-tools-check"
  sudo mkdir -p "$MOUNT_POINT"

  if sudo mount "$CDROM_DEV" "$MOUNT_POINT" 2>/dev/null; then
    if [ -f "$MOUNT_POINT/installer/prltoolsd.sh" ]; then
      echo "Parallels Tools installation media verified"
      sudo umount "$MOUNT_POINT"
      sudo rmdir "$MOUNT_POINT"
      return 0
    else
      # Not Parallels Tools ISO (probably Archboot or other ISO)
      sudo umount "$MOUNT_POINT"
      sudo rmdir "$MOUNT_POINT"
    fi
  fi
fi

echo
echo "ERROR: Parallels Tools installation media not found"
echo
echo "------------------------------------------------------------"
echo "Mount Parallels Tools ISO: Actions > Install Parallels Tools"
echo "------------------------------------------------------------"
echo
echo "Then click 'Retry installation' below"
exit 1
