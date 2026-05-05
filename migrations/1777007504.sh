#!/bin/bash

# Fix NVIDIA GPU detection when supergfxd is blacklisting modules
# See: https://github.com/basecamp/omarchy/issues/5408

echo "Fixing NVIDIA GPU detection..."

# Check if supergfxd is causing issues
if systemctl is-active --quiet supergfxd 2>/dev/null; then
  echo "supergfxd is active - checking for blacklist issues..."
  
  # Check if nvidia modules are blacklisted
  if grep -q "blacklist nvidia" /etc/modprobe.d/supergfxd.conf 2>/dev/null; then
    echo "Found nvidia blacklist from supergfxd!"
    echo "Disabling supergfxd to enable NVIDIA..."
    
    sudo systemctl disable --now supergfxd 2>/dev/null || true
    sudo rm -f /etc/modprobe.d/supergfxd.conf 2>/dev/null || true
    
    # Regenerate initramfs
    sudo mkinitcpio -P 2>/dev/null || true
    
    echo "✓ supergfxd disabled"
    echo "⚠️  Please reboot for NVIDIA modules to load"
    
    notify-send "NVIDIA fix applied" "Please reboot to enable NVIDIA GPU" 2>/dev/null || true
  fi
else
  echo "supergfxd is not active, no action needed"
fi
