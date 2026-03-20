#!/usr/bin/env bash
set -eu

CONFIG_DIR="/etc/sddm.conf.d"

DEFAULT_CONFIG_FILE="$CONFIG_DIR/autologin.conf"
CONFIG_FILE="$CONFIG_DIR/50-wayland.conf"

# Ensure weston exists
omarchy-pkg-add weston

# Only create config if it doesn't exist
if ! rg -q "DisplayServer=wayland" "$DEFAULT_CONFIG_FILE"; then
  echo "Add SDDM Wayland config."

  sudo tee "$CONFIG_FILE" > /dev/null <<'EOF'
[General]
DisplayServer=wayland
EOF

else
  echo "Config already exists for SDDM Wayland."
fi

