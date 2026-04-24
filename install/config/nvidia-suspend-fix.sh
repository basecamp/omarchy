#!/bin/bash

# Fix NVIDIA + hyprlock suspend freeze issue
# See: https://github.com/basecamp/omarchy/issues/5277

echo "Applying NVIDIA suspend fix..."

# The issue is that hyprlock holds DRM/GBM resources during suspend,
# preventing NVIDIA from entering proper suspend state

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

  sudo systemctl enable hyprlock-suspend.service 2>/dev/null || echo "Warning: Could not enable hyprlock-suspend service"
  
  echo "✓ Created hyprlock-suspend service"
else
  echo "No NVIDIA GPU detected, skipping NVIDIA-specific fixes"
fi

echo "NVIDIA suspend fix complete!"
