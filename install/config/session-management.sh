#!/bin/bash

# Install session management systemd service

SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="omarchy-session-save.service"
SOURCE_SERVICE="$HOME/.local/share/omarchy/config/systemd/user/$SERVICE_FILE"

mkdir -p "$SYSTEMD_USER_DIR"

# Copy service file if it exists in source
if [[ -f "$SOURCE_SERVICE" ]]; then
  cp "$SOURCE_SERVICE" "$SYSTEMD_USER_DIR/"
  echo "✓ Installed $SERVICE_FILE"
else
  echo "Warning: $SERVICE_FILE not found in source"
fi

# Reload systemd daemon
systemctl --user daemon-reload 2>/dev/null || true

