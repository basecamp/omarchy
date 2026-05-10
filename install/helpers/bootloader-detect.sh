#!/bin/bash
set -eEo pipefail

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
    local limine_snapper="$OMARCHY_INSTALL/login/limine-snapper.sh"
    if [[ -f "$limine_snapper" ]]; then
      source "$limine_snapper"
    else
      echo "ERROR: limine-snapper.sh not found at $limine_snapper"
      return 1
    fi
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
  local limine_cfg=""
  local kernel=""
  local initramfs=""
  local root_part=""

  if [[ -f /boot/limine.conf ]]; then
    limine_cfg="/boot/limine.conf"
  else
    limine_cfg=$(find /boot -maxdepth 1 -name "limine.conf" 2>/dev/null | head -n1)
  fi

  if [[ -z "$limine_cfg" ]] || [[ ! -f "$limine_cfg" ]]; then
    echo "ERROR: Limine config not found in /boot"
    return 1
  fi

  root_part=$(findmnt -n -o SOURCE / 2>/dev/null)
  if [[ -z "$root_part" ]]; then
    echo "ERROR: Could not detect root partition"
    return 1
  fi

  local candidates
  candidates=$(find /boot -maxdepth 1 \( -name "vmlinuz-*" -o -name "vmlinuz" \) 2>/dev/null | sort -V | tail -n1)
  if [[ -n "$candidates" ]]; then
    kernel="$candidates"
  fi

  if [[ -z "$kernel" ]]; then
    kernel="/boot/vmlinuz-linux"
  fi

  local initramfs_candidates
  initramfs_candidates=$(find /boot -maxdepth 1 -name "initramfs-*.img" 2>/dev/null | sort -V | tail -n1)
  if [[ -z "$initramfs_candidates" ]]; then
    initramfs_candidates=$(find /boot -maxdepth 1 -name "initramfs*.img" 2>/dev/null | sort -V | tail -n1)
  fi
  if [[ -n "$initramfs_candidates" ]]; then
    initramfs="$initramfs_candidates"
  fi

  if [[ -z "$initramfs" ]]; then
    initramfs="/boot/initramfs-linux.img"
  fi

  cp "$limine_cfg" "$limine_cfg.backup"

  if ! grep -q "Omarchy" "$limine_cfg"; then
    echo "" >> "$limine_cfg"
    echo ":Omarchy" >> "$limine_cfg"
    echo "    $kernel" >> "$limine_cfg"
    echo "    initrd=$initramfs" >> "$limine_cfg"
    echo "    append=root=$root_part rw" >> "$limine_cfg"
    echo "Added Omarchy entry to limine.conf"
  else
    echo "Omarchy entry already exists in limine.conf"
  fi
}

# Export for use in other scripts
export -f handle_bootloader
export -f detect_and_configure_bootloader
export -f add_limine_entry
