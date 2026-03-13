#!/bin/bash

# Add 120s timeout to LUKS encryption password input screen

PATCH_FILE="$OMARCHY_PATH"/config/mkinitcpio/luks-timeout.patch
TARGET_HOOK="/usr/lib/initcpio/hooks/encrypt"

if [ ! -f "$TARGET_HOOK" ]; then
  echo "Error: Encryption hook not found"
  exit 1
fi

if [ ! -f "$PATCH_FILE" ]; then
  echo "Error: Patch file not found in repository"
  exit 1
fi

if grep -q "WATCHDOG_PID" "$TARGET_HOOK"; then
  echo "Hook already patched skipping"
  exit 0
fi

echo "Applying Timeout patch..."
if sudo patch "$TARGET_HOOK" "$PATCH_FILE"; then
  echo "Patch has been applied, regenerating initramfs"
  sudo limine-mkinitcpio
else
  echo "Failed to apply patch"
  exit 1
fi
