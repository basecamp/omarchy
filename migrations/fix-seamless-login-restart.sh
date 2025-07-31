#!/bin/bash

SERVICE_FILE="/etc/systemd/system/omarchy-seamless-login.service"

if [ -f "$SERVICE_FILE" ]; then
  # Check if the service file contains 'Restart=always'
  if grep -q '^Restart=always' "$SERVICE_FILE"; then
    echo "Found 'Restart=always', patching $SERVICE_FILE..."

    # Replace 'Restart=always' with 'Restart=on-failure'
    sed -i 's/^Restart=always$/Restart=on-failure/' "$SERVICE_FILE"

    # Check if RestartSec is set to 2, if yes, change it to 5
    if grep -q '^RestartSec=2' "$SERVICE_FILE"; then
      sed -i 's/^RestartSec=2$/RestartSec=5/' "$SERVICE_FILE"
      echo "Changed RestartSec from 2 to 5."
    else
      echo "RestartSec is not 2, leaving it as is."
    fi

    # Reload systemd to apply changes
    systemctl daemon-reload
    echo "Patched and reloaded systemd."
  else
    echo "$SERVICE_FILE already patched or uses a different restart setting."
  fi
else
  echo "$SERVICE_FILE not found, skipping migration."
fi
