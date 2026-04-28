#!/bin/bash

# Fix snapper /home config creation for chroot installations
# See: https://github.com/basecamp/omarchy/issues/5344

echo "Ensuring snapper /home config is created..."

# Check if /home is on a separate subvolume or btrfs
if mountpoint -q /home 2>/dev/null; then
  # /home is a separate mount point
  if ! sudo snapper list-configs 2>/dev/null | grep -qE '^home[[:space:]]'; then
    echo "Creating snapper config for /home..."
    sudo snapper -c home create-config /home 2>/dev/null || echo "Warning: Could not create /home snapper config"
  fi
elif [[ -d /home/.snapshots ]]; then
  # /home has .snapshots subdirectory, ensure config exists
  if ! sudo snapper list-configs 2>/dev/null | grep -qE '^home[[:space:]]'; then
    echo "Creating snapper config for /home subvolume..."
    sudo snapper -c home create-config /home 2>/dev/null || echo "Warning: Could not create /home snapper config"
  fi
else
  echo "/home is not on a separate subvolume, skipping /home snapper config"
fi

# Also ensure root snapper config exists
if ! sudo snapper list-configs 2>/dev/null | grep -qE '^root[[:space:]]'; then
  echo "Creating snapper config for root..."
  sudo snapper -c root create-config / 2>/dev/null || echo "Warning: Could not create root snapper config"
  sudo cp $OMARCHY_PATH/default/snapper/root /etc/snapper/configs/root 2>/dev/null || true
fi

echo "Snapper config check complete!"