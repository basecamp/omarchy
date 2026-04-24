#!/bin/bash

# Fix NVIDIA GPU system lockups on media-heavy sites
# See: https://github.com/basecamp/omarchy/issues/5372

echo "Adding NVIDIA Wayland stability fixes"

# Check if we're on NVIDIA
if command -v nvidia-smi &>/dev/null; then
  # Add NVIDIA-specific environment variables
  NVIDIA_ENV_FILE="$HOME/.config/hypr/env-nvidia.conf"
  
  if [[ ! -f $NVIDIA_ENV_FILE ]]; then
    cat > "$NVIDIA_ENV_FILE" << 'CONFEOF'
# NVIDIA-specific environment variables for better Wayland compatibility
# Fix for: System lockups on NVIDIA GPUs when browsing media-heavy sites
# These flags improve stability and prevent DMA allocation errors

# Use X11 platform hint for Chromium/Electron on NVIDIA Wayland
# This prevents VA-API/Vulkan conflicts that cause lockups
env = ELECTRON_OZONE_PLATFORM_HINT,x11
env = OZONE_PLATFORM,x11
CONFEOF
    notify-send "NVIDIA stability fix applied" "Restart Hyprland to apply NVIDIA stability improvements"
  fi
else
  echo "No NVIDIA GPU detected, skipping NVIDIA-specific fixes"
fi
