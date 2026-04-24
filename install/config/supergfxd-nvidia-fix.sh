#!/bin/bash

# Fix NVIDIA GPU detection when supergfxd is blacklisting modules
# See: https://github.com/basecamp/omarchy/issues/5408

echo "Fixing NVIDIA GPU detection..."

# Get absolute path for scripts
OMARCHY_SCRIPT="$(realpath "$HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set" 2>/dev/null || echo "$HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set")"

# Check if supergfxd is causing issues
if systemctl is-active --quiet supergfxd 2>/dev/null; then
  echo "supergfxd is active - checking for blacklist issues..."
  
  # Check if nvidia modules are blacklisted
  if grep -q "blacklist nvidia" /etc/modprobe.d/supergfxd.conf 2>/dev/null; then
    echo "Found nvidia blacklist from supergfxd!"
    
    if [[ -t 0 ]]; then
      read -p "Disable supergfxd to enable NVIDIA? (y/N) " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo systemctl disable --now supergfxd
        sudo rm -f /etc/modprobe.d/supergfxd.conf
        sudo mkinitcpio -P
        echo "✓ supergfxd disabled, NVIDIA modules will load"
        echo "Please reboot for changes to take effect"
      else
        echo "Skipping supergfxd disable"
      fi
    else
      # Non-interactive: just disable
      sudo systemctl disable --now supergfxd 2>/dev/null || true
      sudo rm -f /etc/modprobe.d/supergfxd.conf 2>/dev/null || true
      echo "Auto-disabled supergfxd for NVIDIA compatibility"
    fi
  fi
else
  echo "supergfxd is not active, no action needed"
fi

# Also ensure NVIDIA modules are not blocked elsewhere
if ls /etc/modprobe.d/*nvidia*.conf 2>/dev/null | grep -v supergfxd | grep -q .; then
  echo "Warning: Other nvidia blacklist files found:"
  ls /etc/modprobe.d/*nvidia*.conf 2>/dev/null | grep -v supergfxd
fi

echo "NVIDIA GPU detection fix complete!"
