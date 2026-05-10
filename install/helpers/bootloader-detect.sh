#!/bin/bash

# Bootloader detection and configuration for dualboot mode

handle_bootloader() {
  local mode="${OMARCHY_INSTALL_MODE:-fresh}"
  local skip="${OMARCHY_INSTALL_SKIP_BOOTLOADER:-false}"
  
  if [[ "$skip" == "true" ]] || [[ "$mode" == "overlay" ]]; then
    echo "Skipping bootloader installation (overlay mode)"
    return 0
  fi
  
  if [[ "$mode" == "fresh" ]]; then
    # Full limine install (existing behavior)
    echo "Installing Limine bootloader (fresh mode)"
    # Call existing limine-snapper.sh
    source "$OMARCHY_INSTALL/login/limine-snapper.sh"
    return 0
  fi
  
  if [[ "$mode" == "dualboot" ]]; then
    detect_and_configure_bootloader
  fi
}

detect_and_configure_bootloader() {
  echo "Detecting existing bootloader for dualboot..."
  
  # Check for Limine
  if command -v limine &>/dev/null; then
    echo "Limine detected - adding Omarchy entry"
    add_limine_entry
    return 0
  fi
  
  # Check for GRUB
  if [[ -f /boot/grub/grub.cfg ]]; then
    echo "GRUB detected - will update via os-prober after install"
    echo "grub-update-required" > /tmp/omarchy-bootloader-action
    return 0
  fi
  
  # Check for systemd-boot
  if [[ -d /boot/EFI/systemd ]]; then
    echo "systemd-boot detected - manual configuration needed"
    echo "systemd-boot-manual" > /tmp/omarchy-bootloader-action
    return 0
  fi
  
  # Check for Windows
  if [[ -f /boot/EFI/Microsoft/Boot/bootmgfw.efi ]]; then
    echo "Windows bootloader detected"
    echo "WARNING: Manual configuration required for Windows dualboot"
    echo "Consider installing rEFInd: sudo pacman -S refind"
    echo "windows-detected" > /tmp/omarchy-bootloader-action
    return 0
  fi
  
  # No bootloader found
  echo "No known bootloader detected - skipping"
  echo "no-bootloader" > /tmp/omarchy-bootloader-action
}

add_limine_entry() {
  # Add Omarchy entry to existing limine config
  local limine_cfg="/boot/limine.conf"
  
  if [[ -f "$limine_cfg" ]]; then
    # Backup
    cp "$limine_cfg" "$limine_cfg.backup"
    
    # Add entry (simplified - real implementation would be more robust)
    if ! grep -q "Omarchy" "$limine_cfg"; then
      echo "" >> "$limine_cfg"
      echo ":Omarchy" >> "$limine_cfg"
      echo "    /boot/vmlinuz-linux" >> "$limine_cfg"
      echo "    initrd=/boot/initramfs-linux.img" >> "$limine_cfg"
      echo "    append=root=LABEL=ROOT rw" >> "$limine_cfg"
      echo "Added Omarchy entry to limine.conf"
    else
      echo "Omarchy entry already exists in limine.conf"
    fi
  else
    echo "Limine config not found at $limine_cfg"
  fi
}

# Export for use in other scripts
export -f handle_bootloader
export -f detect_and_configure_bootloader
