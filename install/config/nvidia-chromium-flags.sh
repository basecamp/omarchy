#!/bin/bash

# Install Chromium flags for better NVIDIA Wayland stability
# Fix for: System lockups on NVIDIA GPUs when browsing media-heavy sites

CHROMIUM_FLAGS_DIR="$HOME/.config/chromium-flags"
mkdir -p "$CHROMIUM_FLAGS_DIR"

# Create a helper script that sets NVIDIA-optimized flags
cat > "$HOME/.config/chromium-flags/set-flags" << 'EOF'
#!/bin/bash
# NVIDIA-optimized Chromium flags for Wayland
# Prevents system lockups on media-heavy sites

# Use X11 backend instead of Wayland for Chromium on NVIDIA
# Wayland + NVIDIA + Chromium can cause lockups
export CHROMIUM_FLAGS="--ozone-platform=x11 --enable-features=VaapiVideoDecoder,VaapiVideoEncoder --disable-features=Vulkan, VulkanFromANGLE, DefaultANGLEVulkan"

# Apply to Electron apps too
export ELECTRON_OZONE_PLATFORM_HINT=x11
EOF

chmod +x "$HOME/.config/chromium-flags/set-flags"

notify-send "NVIDIA Chromium flags installed" "Stability improvements applied for NVIDIA GPUs"
