#!/bin/bash

# Fix NVIDIA GPU detection when supergfxd is blacklisting modules
# See: https://github.com/basecamp/omarchy/issues/5408

echo "Fixing NVIDIA GPU detection..."

SUPERGFXD_CONF="/etc/modprobe.d/supergfxd.conf"

# Check for persisted NVIDIA blacklists from supergfxd regardless of service state
if grep -Eq '^[[:space:]]*blacklist[[:space:]]+nvidia([_-][[:alnum:]_]+)?([[:space:]]|$)' "$SUPERGFXD_CONF" 2>/dev/null; then
  echo "Found nvidia blacklist from supergfxd!"
  echo "Disabling supergfxd to enable NVIDIA..."

  sudo systemctl disable --now supergfxd 2>/dev/null || true
  sudo rm -f "$SUPERGFXD_CONF" 2>/dev/null || true

  # Regenerate initramfs
  sudo mkinitcpio -P 2>/dev/null || true

  echo "✓ supergfxd disabled"
  echo "⚠️  Please reboot for NVIDIA modules to load"
  
  # Guard notify-send for non-GUI environments
  if command -v notify-send >/dev/null 2>&1 && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    notify-send "NVIDIA fix applied" "Please reboot to enable NVIDIA GPU" || true
  fi
else
  echo "No supergfxd nvidia blacklist found, no action needed"
fi