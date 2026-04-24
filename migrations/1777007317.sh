#!/bin/bash

# Fix NVIDIA GPU system lockups on media-heavy sites
# See: https://github.com/basecamp/omarchy/issues/5372

echo "Adding NVIDIA Wayland stability fixes"

# Check if we're on NVIDIA
if command -v nvidia-smi &>/dev/null; then
  # Add NVIDIA-specific environment variables to the existing envs.conf
  NVIDIA_ENV_FILE="$HOME/.config/hypr/envs.conf"
  
  # Ensure the file exists and is sourced
  if [[ ! -f $NVIDIA_ENV_FILE ]]; then
    mkdir -p "$(dirname "$NVIDIA_ENV_FILE")"
    touch "$NVIDIA_ENV_FILE"
  fi
  
  # Check if NVIDIA fixes are already applied
  if ! grep -q "# NVIDIA Wayland stability fixes" "$NVIDIA_ENV_FILE" 2>/dev/null; then
    cat >> "$NVIDIA_ENV_FILE" << 'CONFEOF'

# NVIDIA Wayland stability fixes
# Use X11 platform hint for Chromium/Electron on NVIDIA Wayland
# This prevents VA-API/Vulkan conflicts that cause lockups
env = ELECTRON_OZONE_PLATFORM_HINT,x11
env = OZONE_PLATFORM,x11
CONFEOF
    notify-send "NVIDIA stability fix applied" "Restart Hyprland to apply NVIDIA stability improvements"
  else
    echo "NVIDIA stability fix already applied"
  fi
else
  echo "No NVIDIA GPU detected, skipping NVIDIA-specific fixes"
fi
