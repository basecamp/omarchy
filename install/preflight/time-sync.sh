#!/bin/bash

# Skip if not online install
if [[ -z ${OMARCHY_ONLINE_INSTALL:-} ]]; then
  return 0
fi

echo "Syncing system time (required for SSL certificates)..."

# Enable and start systemd-timesyncd
sudo timedatectl set-ntp true
sudo systemctl enable --now systemd-timesyncd 2>/dev/null

# Wait a moment for initial sync
sleep 2

# Verify time sync is active
if timedatectl status | grep -q "System clock synchronized: yes"; then
  echo "System time synchronized"
else
  echo "Time sync started (may take a few moments)"
fi

return 0
