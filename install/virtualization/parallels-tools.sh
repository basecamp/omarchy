#!/bin/bash

# Skip if not virtualization and not Parallels
if command -v systemd-detect-virt &>/dev/null; then
  virt_type=$(systemd-detect-virt)
  if [[ "$virt_type" != "parallels" ]]; then
    return 0
  fi
else
  return 0
fi

# Check if Parallels Tools are already installed
if [ -d /usr/lib/parallels-tools ]; then
  echo "Parallels Tools already installed, skipping."
  return 0
fi

echo "Detected Parallels, installing Parallels Tools..."

# Tools not installed, ISO should be available (verified by preflight)
CDROM_DEV="/dev/cdrom"
[ -e /dev/sr0 ] && CDROM_DEV="/dev/sr0"

echo "Installing Parallels Tools from CD-ROM..."
sudo mkdir -p /mnt/parallels-tools

if sudo mount "$CDROM_DEV" /mnt/parallels-tools 2>/dev/null; then
  if sudo bash /mnt/parallels-tools/install; then
    echo "Parallels Tools installed successfully!"
  else
    echo "WARNING: Parallels Tools installation encountered errors, but continuing..."
  fi
  sudo umount /mnt/parallels-tools 2>/dev/null
else
  echo "ERROR: Could not mount Parallels Tools ISO"
  exit 1
fi

echo "Parallels Tools configuration complete!"
echo "Shared folders will be available via the 'Parallels Shared Folders' desktop icon"
