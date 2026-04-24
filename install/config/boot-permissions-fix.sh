#!/bin/bash

# Fix /boot permissions security issue
# The random seed file and /boot mount should not be world accessible
# See: https://github.com/basecamp/omarchy/issues/5377

echo "Fixing /boot permissions for better security..."

# Fix /boot directory permissions (should be 700)
sudo chmod 700 /boot 2>/dev/null || echo "Could not change /boot permissions"

# Fix random-seed file permissions if it exists
if [[ -f /boot/loader/random-seed ]]; then
  sudo chmod 600 /boot/loader/random-seed 2>/dev/null || echo "Could not change random-seed permissions"
fi

# Ensure /boot is mounted with proper permissions
# Add to fstab if not already present with correct options
if ! grep -q "^/boot" /etc/fstab 2>/dev/null; then
  echo "Warning: /boot is not in fstab, permissions may not persist"
fi

# Disable bootctl random seed generation warnings by setting correct permissions
if command -v bootctl &>/dev/null; then
  # Run bootctl with proper environment to set correct permissions
  sudo bootctl random-seed 2>/dev/null || true
fi

echo "Boot permissions fix complete!"
