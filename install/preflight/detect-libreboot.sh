#!/bin/bash

# Detect Libreboot/Coreboot systems without EFI payload
# This script runs in preflight to detect systems that need BIOS boot mode

detect_libreboot_coreboot() {
  local is_libreboot=false
  local detection_method=""
  
  # Method 1: Check for EFI absence (primary indicator)
  if [[ ! -d /sys/firmware/efi ]]; then
    # Method 2: Check dmesg for Coreboot/Libreboot markers
    if dmesg 2>/dev/null | grep -qiE "coreboot|libreboot"; then
      is_libreboot=true
      detection_method="dmesg"
    # Method 3: Check BIOS vendor/version for known Libreboot systems
    elif [[ -f /sys/class/dmi/id/bios_vendor ]]; then
      bios_vendor=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null | tr '[:upper:]' '[:lower:]')
      if [[ "$bios_vendor" == *"coreboot"* ]] || [[ "$bios_vendor" == *"libreboot"* ]]; then
        is_libreboot=true
        detection_method="bios_vendor"
      fi
    # Method 4: Check for absence of efibootmgr (indicates no EFI runtime)
    elif ! command -v efibootmgr &>/dev/null && \
         ! mountpoint -q /sys/firmware/efi/efivars 2>/dev/null; then
      # Additional check: Look for known Libreboot hardware
      # (ThinkPad T480, X200, etc. - these are commonly Librebooted)
      machine_model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "")
      if [[ -n "$machine_model" ]]; then
        # Common Libreboot/Coreboot machines (add more as needed)
        case "$machine_model" in
          *"ThinkPad"*)
            is_libreboot=true
            detection_method="hardware_model"
            ;;
        esac
      fi
    fi
  fi
  
  if [[ "$is_libreboot" == "true" ]]; then
    echo "$detection_method"
    return 0
  else
    return 1
  fi
}

# Main detection logic
if detect_libreboot_coreboot >/dev/null 2>&1; then
  detection_method=$(detect_libreboot_coreboot)
  
  # Set environment variables for use in later scripts
  export OMARCHY_BIOS_MODE=true
  export OMARCHY_NEEDS_BIOS_BOOT_PARTITION=true
  export OMARCHY_LIBREBOOT_DETECTED=true
  
  # Persist detection result to file (for use in chroot environment)
  # This ensures detection is available in login phase even if env vars don't persist
  echo "$detection_method" > /tmp/omarchy-libreboot-detected 2>/dev/null || true
  echo "true" > /tmp/omarchy-libreboot-detected-flag 2>/dev/null || true
  
  echo "=========================================="
  echo "Libreboot/Coreboot System Detected"
  echo "=========================================="
  echo ""
  echo "Detection method: $detection_method"
  echo "EFI services: Not available"
  echo "Boot mode: BIOS/Legacy"
  echo ""
  echo "IMPORTANT: This system requires:"
  echo "  - BIOS boot partition (1 MiB, type ef02) on GPT disks"
  echo "  - Limine installed in BIOS/MBR mode"
  echo ""
  echo "The installer will attempt to configure this automatically."
  echo "If you're using archinstall manually, ensure you create a"
  echo "BIOS boot partition when partitioning GPT disks."
  echo ""
  echo "Pausing for 10 seconds to allow screenshot..."
  echo ""
  
  # Pause to allow user to see the message and take a screenshot
  # Can be skipped by setting OMARCHY_SKIP_DETECTION_PAUSE=1
  if [[ -z "${OMARCHY_SKIP_DETECTION_PAUSE:-}" ]]; then
    sleep 10
  fi
  
  # Log for debugging
  echo "[$(date +%Y-%m-%d\ %H:%M:%S)] Libreboot/Coreboot detected (method: $detection_method)" >> "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null || true
else
  # Not a Libreboot/Coreboot system, but check if EFI is absent anyway
  if [[ ! -d /sys/firmware/efi ]]; then
    export OMARCHY_BIOS_MODE=true
    export OMARCHY_NEEDS_BIOS_BOOT_PARTITION=true
    echo "Note: No EFI detected - BIOS boot mode will be used"
  fi
fi
