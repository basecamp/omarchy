#!/bin/bash

# ==============================================================================
# Hyprland Nouveau Setup Script for Arch Linux
# ==============================================================================
# This script automates the installation and configuration of Nouveau drivers
# for use with Hyprland on Arch Linux. Nouveau is the open-source driver
# for NVIDIA graphics cards.
#
# Modified from original NVIDIA script to use Nouveau drivers
#
# ==============================================================================

# --- GPU Detection ---
if [ -n "$(lspci | grep -i 'nvidia')" ]; then
  show_logo
  show_subtext "Install Nouveau drivers..."

  # Check which kernel is installed and set appropriate headers package
  KERNEL_HEADERS="linux-headers" # Default
  if pacman -Q linux-zen &>/dev/null; then
    KERNEL_HEADERS="linux-zen-headers"
  elif pacman -Q linux-lts &>/dev/null; then
    KERNEL_HEADERS="linux-lts-headers"
  elif pacman -Q linux-hardened &>/dev/null; then
    KERNEL_HEADERS="linux-hardened-headers"
  fi

  # Enable multilib repository for 32-bit libraries
  if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
  fi

  # Force package database refresh
  sudo pacman -Syy

  # Install Nouveau packages
  PACKAGES_TO_INSTALL=(
    "${KERNEL_HEADERS}"
    "xf86-video-nouveau"    # Nouveau X.Org driver
    "mesa"                  # Open-source OpenGL implementation
    "lib32-mesa"           # 32-bit Mesa libraries
    "mesa-utils"           # Mesa utilities
    "libva-mesa-driver"    # VA-API hardware acceleration for Mesa
    "lib32-libva-mesa-driver" # 32-bit VA-API Mesa driver
    "vulkan-nouveau"       # Vulkan driver for Nouveau (experimental)
    "qt5-wayland"
    "qt6-wayland"
  )

  yay -S --needed --noconfirm "${PACKAGES_TO_INSTALL[@]}"

  # Ensure proprietary NVIDIA drivers are not loaded
  # Blacklist nvidia modules to prevent conflicts
  echo "# Blacklist proprietary NVIDIA drivers to ensure Nouveau is used
blacklist nvidia
blacklist nvidia-drm
blacklist nvidia-modeset
blacklist nvidia-uvm" | sudo tee /etc/modprobe.d/blacklist-nvidia.conf >/dev/null

  # Configure modprobe for Nouveau early KMS
  echo "options nouveau modeset=1" | sudo tee /etc/modprobe.d/nouveau.conf >/dev/null

  # Configure mkinitcpio for early loading of Nouveau
  MKINITCPIO_CONF="/etc/mkinitcpio.conf"

  # Define Nouveau modules
  NOUVEAU_MODULES="nouveau"

  # Create backup
  sudo cp "$MKINITCPIO_CONF" "${MKINITCPIO_CONF}.backup"

  # Remove any old nvidia modules to prevent conflicts
  sudo sed -i -E 's/ nvidia_drm//g; s/ nvidia_uvm//g; s/ nvidia_modeset//g; s/ nvidia//g;' "$MKINITCPIO_CONF"
  
  # Check if nouveau is already in MODULES, if not add it
  if ! grep -q "nouveau" "$MKINITCPIO_CONF"; then
    # Add nouveau module at the start of the MODULES array
    sudo sed -i -E "s/^(MODULES=\\()/\\1${NOUVEAU_MODULES} /" "$MKINITCPIO_CONF"
  fi
  
  # Clean up potential double spaces
  sudo sed -i -E 's/  +/ /g' "$MKINITCPIO_CONF"

  sudo mkinitcpio -P

  # Add Mesa/Nouveau environment variables to hyprland.conf
  HYPRLAND_CONF="$HOME/.config/hypr/hyprland.conf"
  if [ -f "$HYPRLAND_CONF" ]; then
    # Remove any existing NVIDIA environment variables first
    sudo sed -i '/# NVIDIA environment variables/,/env = __GLX_VENDOR_LIBRARY_NAME,nvidia/d' "$HYPRLAND_CONF"
    
    cat >>"$HYPRLAND_CONF" <<'EOF'

# Nouveau/Mesa environment variables
env = LIBVA_DRIVER_NAME,nouveau
env = WLR_NO_HARDWARE_CURSORS,1
env = WLR_RENDERER,vulkan
EOF
  fi

  # Remove any existing proprietary NVIDIA packages (optional safety measure)
  echo "Removing any existing proprietary NVIDIA packages..."
  yay -Rns nvidia nvidia-dkms nvidia-open-dkms nvidia-utils lib32-nvidia-utils --noconfirm 2>/dev/null || true
  
  echo "Nouveau driver installation complete!"
  echo "Please reboot your system to ensure the new drivers are properly loaded."
  echo ""
  echo "Note: Nouveau performance may be lower than proprietary drivers, but it should provide"
  echo "better compatibility with Wayland compositors like Hyprland."
fi
