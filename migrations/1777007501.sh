#!/bin/bash

# Fix snapper root config for chroot installations
# See: https://github.com/basecamp/omarchy/issues/5344

echo "Fixing snapper root config..."

# Only proceed if snapper is available
if ! command -v snapper >/dev/null 2>&1; then
  echo "snapper not installed, skipping"
  exit 0
fi

# Ensure root config exists
if ! sudo snapper list-configs 2>/dev/null | grep -qE '^root[[:space:]]'; then
  echo "Creating snapper config for root..."
  sudo snapper -c root create-config / 2>/dev/null || true
  
  # Copy default omarchy snapper config if available
  if [[ -f "$OMARCHY_PATH/default/snapper/root" ]]; then
    sudo cp "$OMARCHY_PATH/default/snapper/root" /etc/snapper/configs/root 2>/dev/null || true
  fi
  
  echo "✓ Created snapper root config"
else
  echo "Snapper root config already exists"
fi

# Note: /home snapper config creation removed as it conflicts with
# migration 1776927490 which intentionally disables /home snapshots
# to prevent accidental user data rollback

echo "Snapper config fix complete!"