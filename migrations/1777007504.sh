#!/bin/bash

# Fix NVIDIA GPU detection when supergfxd is blacklisting modules
# See: https://github.com/basecamp/omarchy/issues/5408

echo "Fixing NVIDIA GPU detection..."

# Check for blacklist directly - file can persist even when service is inactive
if grep -q "blacklist nvidia" /etc/modprobe.d/supergfxd.conf 2>/dev/null; then
  echo "Found nvidia blacklist from supergfxd!"
  echo "Removing supergfxd nvidia blacklist and restoring Hybrid mode..."

  # Remove blacklist and rebuild initramfs - must succeed, otherwise abort migration
  if sudo rm -f /etc/modprobe.d/supergfxd.conf && sudo mkinitcpio -P 2>/dev/null; then
    # Keep supergfxd enabled for GPU mode switching (best-effort, don't fail migration if this warns)
    sudo systemctl enable --now supergfxd 2>/dev/null || echo "Warning: could not re-enable supergfxd" >&2
    sudo supergfxctl --mode Hybrid 2>/dev/null || echo "Warning: could not set Hybrid mode" >&2

    echo "✓ supergfxd blacklist removed"
    echo "✓ supergfxd left enabled for GPU mode switching"
    echo "⚠️  Please reboot for NVIDIA modules to load"
    notify-send "NVIDIA fix applied" "Removed supergfxd blacklist and restored Hybrid mode; please reboot" 2>/dev/null || true
  else
    echo "Failed to remove blacklist or rebuild initramfs" >&2
    exit 1
  fi
else
  echo "No supergfxd nvidia blacklist found, no action needed"
fi
