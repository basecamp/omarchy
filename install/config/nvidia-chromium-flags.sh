#!/bin/bash

# Install Chromium flags for better NVIDIA Wayland stability
# Fix for: System lockups on NVIDIA GPUs when browsing media-heavy sites

CHROMIUM_FLAGS_DIR="$HOME/.config"
mkdir -p "$CHROMIUM_FLAGS_DIR"

# Write NVIDIA-optimized Chromium flags to the config file Omarchy reads
cat > "$CHROMIUM_FLAGS_DIR/chromium-flags.conf" << 'CONFEOF'
# NVIDIA-optimized Chromium flags for Wayland systems with NVIDIA GPUs
--ozone-platform=x11
--enable-features=VaapiVideoDecoder,VaapiVideoEncoder
--disable-features=Vulkan,VulkanFromANGLE,DefaultANGLEVulkan
CONFEOF

# Also set environment variables for Electron apps
NVIDIA_ENV_FILE="$HOME/.config/hypr/envs.conf"
if ! grep -q "OZONE_PLATFORM,x11" "$NVIDIA_ENV_FILE" 2>/dev/null; then
  cat >> "$NVIDIA_ENV_FILE" << 'ENVEOF'

# NVIDIA Chromium/Electron stability
env = ELECTRON_OZONE_PLATFORM_HINT,x11
env = OZONE_PLATFORM,x11
ENVEOF
fi

notify-send "NVIDIA Chromium flags installed" "Stability improvements applied for NVIDIA GPUs"
