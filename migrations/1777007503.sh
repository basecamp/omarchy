#!/bin/bash

# Fix NVIDIA + hyprlock suspend freeze issue
# See: https://github.com/basecamp/omarchy/issues/5277

echo "Applying NVIDIA suspend fix..."

# Check if user is on NVIDIA
if command -v nvidia-smi &>/dev/null; then
  echo "NVIDIA GPU detected, applying suspend fix..."
  
  # Create a systemd service to stop hyprlock before suspend
  cat << 'SYSTEMD' | sudo tee /etc/systemd/system/hyprlock-suspend.service > /dev/null
[Unit]
Description=Stop hyprlock before suspend/hibernate
Before=suspend.target hibernate.target hybrid-suspend.target
DefaultDependencies=no
After=hypridle.service

[Service]
Type=oneshot
ExecStart=/usr/bin/pkill -STOP hyprlock
RemainAfterExit=yes
ExecStop=/usr/bin/pkill -CONT hyprlock
TimeoutStopSec=5

[Install]
WantedBy=suspend.target hibernate.target hybrid-suspend.target
SYSTEMD

  # Reload systemd daemon to recognize the new unit
  sudo systemctl daemon-reload
  
  # Enable the service using chrootable helper if available
  if command -v chrootable_systemctl_enable >/dev/null 2>&1; then
    chrootable_systemctl_enable hyprlock-suspend.service 2>/dev/null || echo "Warning: Could not enable hyprlock-suspend service"
  else
    sudo systemctl enable hyprlock-suspend.service 2>/dev/null || echo "Warning: Could not enable hyprlock-suspend service"
  fi
  
  echo "✓ Created hyprlock-suspend service"
  echo "✓ hyprlock will stop before suspend and resume after"
else
  echo "No NVIDIA GPU detected, skipping NVIDIA-specific fixes"
fi