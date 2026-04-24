#!/bin/bash

# Fix snapper /home config for chroot installations
# See: https://github.com/basecamp/omarchy/issues/5344

echo "Fixing snapper /home config..."

# Get absolute path for omarchy
OMARCHY_PATH="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"

# Check if /home is on btrfs and has .snapshots
if [[ -d /home/.snapshots ]] || mountpoint -q /home 2>/dev/null; then
  # Check if /home snapper config exists (use anchored match)
  if ! sudo snapper list-configs 2>/dev/null | grep -q "^home"; then
    echo "Creating snapper config for /home..."
    sudo snapper -c home create-config /home 2>/dev/null || echo "Warning: Could not create /home snapper config"
    
    # Copy and modify config from root if available
    if [[ -f /etc/snapper/configs/root ]]; then
      sudo cp /etc/snapper/configs/root /etc/snapper/configs/home 2>/dev/null || true
      sudo sed -i 's|SUBVOLUME="/"|SUBVOLUME="/home"|' /etc/snapper/configs/home 2>/dev/null || true
      sudo sed -i 's|TIMELINE_CREATE="yes"|TIMELINE_CREATE="no"|' /etc/snapper/configs/home 2>/dev/null || true
    elif [[ -f "$OMARCHY_PATH/default/snapper/root" ]]; then
      sudo cp "$OMARCHY_PATH/default/snapper/root" /etc/snapper/configs/home 2>/dev/null || true
      sudo sed -i 's|SUBVOLUME="/"|SUBVOLUME="/home"|' /etc/snapper/configs/home 2>/dev/null || true
      sudo sed -i 's|TIMELINE_CREATE="yes"|TIMELINE_CREATE="no"|' /etc/snapper/configs/home 2>/dev/null || true
    fi
    
    echo "✓ Created snapper /home config"
  else
    echo "Snapper /home config already exists"
  fi
else
  echo "/home is not on btrfs or separate subvolume, skipping"
fi

# Ensure root config exists (anchored match)
if ! sudo snapper list-configs 2>/dev/null | grep -q "^root"; then
  echo "Creating snapper config for root..."
  sudo snapper -c root create-config / 2>/dev/null || true
  if [[ -f "$OMARCHY_PATH/default/snapper/root" ]]; then
    sudo cp "$OMARCHY_PATH/default/snapper/root" /etc/snapper/configs/root 2>/dev/null || true
  fi
fi

echo "Snapper config fix complete!"
