#!/bin/bash

# Fix /boot permissions security issue
# See: https://github.com/basecamp/omarchy/issues/5377

echo "Fixing /boot permissions for better security..."

# Fix /boot directory permissions (should be 700 for security)
sudo chmod 700 /boot 2>/dev/null || echo "Could not change /boot permissions"

# Fix random-seed file permissions if it exists
if [[ -f /boot/loader/random-seed ]]; then
  sudo chmod 600 /boot/loader/random-seed 2>/dev/null || echo "Could not change random-seed permissions"
fi

# Verify the fix
if [[ $(stat -c %a /boot 2>/dev/null) == "700" ]]; then
  echo "✓ /boot permissions fixed to 700"
fi

if [[ -f /boot/loader/random-seed ]] && [[ $(stat -c %a /boot/loader/random-seed 2>/dev/null) == "600" ]]; then
  echo "✓ random-seed permissions fixed to 600"
fi

# Guard notify-send for environments without GUI/DBUS
if command -v notify-send >/dev/null 2>&1 && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  notify-send "Boot permissions fixed" "Security improvement applied to /boot" || true
fi

exit 0