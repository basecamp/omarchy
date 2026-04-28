#!/bin/bash

# Fix NVIDIA GPU detection when supergfxd is blacklisting modules
# See: https://github.com/basecamp/omarchy/issues/5408

echo "Fixing NVIDIA GPU detection..."

SUPERGFXD_CONF="/etc/modprobe.d/supergfxd.conf"

# Check for persisted NVIDIA blacklists from supergfxd regardless of service state
if grep -Eq '^[[:space:]]*blacklist[[:space:]]+nvidia([_-][[:alnum:]_]+)?([[:space:]]|$)' "$SUPERGFXD_CONF" 2>/dev/null; then
  echo "Found nvidia blacklist from supergfxd!"
  echo "Disabling supergfxd to enable NVIDIA..."

  # Disable supergfxd if active or enabled
  if systemctl is-active --quiet supergfxd 2>/dev/null || systemctl is-enabled --quiet supergfxd 2>/dev/null; then
    sudo systemctl disable --now supergfxd 2>/dev/null || true
  fi
  
  sudo rm -f "$SUPERGFXD_CONF" 2>/dev/null || true
  
  # Regenerate initramfs
  sudo mkinitcpio -P 2>/dev/null || true
  
  echo "✓ Removed supergfxd NVIDIA blacklist"
  echo "⚠️  Please reboot for changes to take effect"
else
  echo "No supergfxd NVIDIA blacklist found, no action needed"
fi

# Also ensure NVIDIA modules are not blocked elsewhere
if ls /etc/modprobe.d/*nvidia*.conf 2>/dev/null | grep -v supergfxd | grep -q .; then
  echo "Warning: Other nvidia blacklist files found:"
  ls /etc/modprobe.d/*nvidia*.conf 2>/dev/null | grep -v supergfxd
fi

echo "NVIDIA GPU detection fix complete!"