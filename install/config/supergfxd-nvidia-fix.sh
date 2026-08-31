#!/bin/bash

# Fix NVIDIA GPU detection when supergfxd is blacklisting modules
# See: https://github.com/basecamp/omarchy/issues/5408

echo "Fixing NVIDIA GPU detection..."

# Check for blacklist directly - works regardless of service state
if grep -q "blacklist nvidia" /etc/modprobe.d/supergfxd.conf 2>/dev/null; then
  echo "Found nvidia blacklist from supergfxd!"
  echo "Removing blacklist and restoring Hybrid mode..."

  # Remove blacklist and rebuild initramfs (best-effort during install, don't abort)
  sudo rm -f /etc/modprobe.d/supergfxd.conf 2>/dev/null || true
  sudo mkinitcpio -P 2>/dev/null || true

  # Keep supergfxd available for hybrid-GPU switching
  sudo systemctl enable --now supergfxd 2>/dev/null || true
  sudo supergfxctl --mode Hybrid 2>/dev/null || true

  echo "✓ supergfxd blacklist removed"
  echo "✓ supergfxd left enabled for GPU mode switching"
  echo "⚠️  Please reboot for NVIDIA modules to load"
else
  echo "No blacklist found, no action needed"
fi

echo "NVIDIA GPU detection fix complete!"
