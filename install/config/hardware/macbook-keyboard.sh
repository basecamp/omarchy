#!/bin/bash

# ==============================================================================
# MacBook SPI Keyboard Support for Encryption
# ==============================================================================
# This script fixes the issue where MacBook 2015-2017 models with SPI keyboards
# require an external keyboard to enter the LUKS encryption password
# during boot. The internal keyboard uses SPI (Serial Peripheral Interface)
# which requires the applespi driver to be loaded in the initramfs.
#
# Affected Models:
# - MacBook12,1: 12" MacBook (2015-2017)
  # - MacBookPro13,2: 13" 2016 with Touch Bar  
  # - MacBookPro13,3: 15" 2016 with Touch Bar
  # - MacBookPro14,2: 13" 2017 with Touch Bar
  # - MacBookPro14,3: 15" 2017 with Touch Bar
  # Note: MacBookPro13,1 (13" 2016 without Touch Bar) uses USB HID - no fix needed
#
# Issue: https://github.com/roadrunner2/macbook12-spi-driver
# Solution: Add applespi module to mkinitcpio MODULES array
# ==============================================================================

# Detect MacBook Pro 2015-2017 models with SPI keyboard
if [ -f "/sys/class/dmi/id/product_name" ]; then
  PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
  
  # Check for models with SPI keyboards needing applespi driver:
  if [[ "$PRODUCT_NAME" =~ MacBook12,1|MacBookPro13,[23]|MacBookPro14,[23] ]]; then
    echo "Detected MacBook with SPI keyboard: $PRODUCT_NAME"
    
    # Ensure applespi is available; prefer in-tree module if present, otherwise install DKMS from AUR
    if ! modprobe -nq applespi 2>/dev/null && ! modinfo applespi &>/dev/null; then
      if ! pacman -Qi macbook12-spi-driver-dkms &>/dev/null; then
        echo "Installing macbook12-spi-driver-dkms for SPI keyboard support..."
        if command -v yay &>/dev/null; then
          yay -S --noconfirm macbook12-spi-driver-dkms
        elif command -v paru &>/dev/null; then
          paru -S --noconfirm macbook12-spi-driver-dkms
        else
          echo "Warning: AUR helper (yay/paru) not found. Please install macbook12-spi-driver-dkms manually:"
          echo "  yay -S macbook12-spi-driver-dkms"
        fi
      fi
    fi
    
    # Configure mkinitcpio using a conf.d drop-in for robustness and idempotence
    MKINITCPIO_DROPIN="/etc/mkinitcpio.conf.d/omarchy-macbook-spi.conf"
    NEEDS_REBUILD=false

    # Create or update drop-in: include required SPI stack and keyboard hook
    # applespi depends on intel_lpss_pci and spi_pxa2xx_platform on MBPs with SPI keyboard
    DESIRED_MODULES_LINE='MODULES+=(applespi intel_lpss_pci spi_pxa2xx_platform)'
    DESIRED_HOOKS_LINE='HOOKS+=(keyboard)'

    sudo mkdir -p /etc/mkinitcpio.conf.d

    # Ensure modules line present
    if [ ! -f "$MKINITCPIO_DROPIN" ] || ! grep -q "^${DESIRED_MODULES_LINE}$" "$MKINITCPIO_DROPIN"; then
      echo "$DESIRED_MODULES_LINE" | sudo tee -a "$MKINITCPIO_DROPIN" >/dev/null
      NEEDS_REBUILD=true
    fi

    # Ensure hooks line present
    if [ ! -f "$MKINITCPIO_DROPIN" ] || ! grep -q "^${DESIRED_HOOKS_LINE}$" "$MKINITCPIO_DROPIN"; then
      echo "$DESIRED_HOOKS_LINE" | sudo tee -a "$MKINITCPIO_DROPIN" >/dev/null
      NEEDS_REBUILD=true
    fi
    
    # Regenerate initramfs if changes were made
    if [ "$NEEDS_REBUILD" = true ]; then
      echo "Regenerating initramfs..."
      sudo mkinitcpio -P
      
      echo "MacBook Pro SPI keyboard fix applied successfully"
      echo "Internal keyboard will now work during LUKS encryption prompt"
      echo "Note: Reboot required for changes to take effect"
    else
      echo "MacBook Pro SPI keyboard support already configured"
    fi
  fi
fi
